import AppKit
import CoreGraphics

enum SyntheticEvent {
    static let marker: Int64 = 0x4E57_5244

    static func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }
}

@MainActor
final class HotkeyMonitor {
    var longPressDuration: TimeInterval
    var onTrigger: (() -> Void)?
    var isPanelActive = false
    var isEnabled = true
    var onPanelKey: ((PanelKey) -> Void)?

    var isRunning: Bool { tap != nil }

    private enum TriggerState {
        case idle
        case waiting
        case consumed
    }

    private enum KeyCode {
        static let returnKey: Int64 = 36
        static let keypadEnter: Int64 = 76
        static let escape: Int64 = 53
        static let tab: Int64 = 48
        static let r: Int64 = 15
        static let e: Int64 = 14
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
        static let digits: [Int64: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10,
            83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 10,
        ]
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var state: TriggerState = .idle
    private var pendingKeyDown: CGEvent?
    private var triggerKeyCode: Int64?
    private var swallowedKeys: Set<Int64> = []

    init(longPressDuration: TimeInterval = 0.4) {
        self.longPressDuration = longPressDuration
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let shouldPass = MainActor.assumeIsolated {
                    monitor.handle(proxy: proxy, type: type, event: event)
                }
                return shouldPass ? Unmanaged.passUnretained(event) : nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        resetTriggerState()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            resetTriggerState()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .keyDown:
            if SyntheticEvent.isSynthetic(event) { return true }
            return handleKeyDown(proxy: proxy, event: event)
        case .keyUp:
            if SyntheticEvent.isSynthetic(event) { return true }
            return handleKeyUp(proxy: proxy, event: event)
        default:
            return true
        }
    }

    private func handleKeyDown(proxy: CGEventTapProxy, event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if state != .idle, keyCode == triggerKeyCode {
            return false
        }

        if state == .waiting {
            flushPendingTrigger(proxy: proxy, followedBy: event)
            return false
        }

        if isRepeat, swallowedKeys.contains(keyCode) {
            if isPanelActive, let key = panelKey(for: event), key.isNavigation {
                onPanelKey?(key)
            }
            return false
        }

        if isPanelActive {
            if isEnabled, isTriggerKey(event) {
                swallowedKeys.insert(keyCode)
                if !isRepeat { onPanelKey?(.dismiss) }
                return false
            }
            if let key = panelKey(for: event) {
                swallowedKeys.insert(keyCode)
                onPanelKey?(key)
                return false
            }
            onPanelKey?(.dismiss)
            return true
        }

        if isEnabled, !isRepeat, isTriggerKey(event) {
            triggerKeyCode = keyCode
            beginTrigger(with: event)
            return false
        }

        return true
    }

    private func handleKeyUp(proxy: CGEventTapProxy, event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == triggerKeyCode {
            switch state {
            case .waiting:
                cancelTimer()
                state = .idle
                if let pendingKeyDown {
                    post(pendingKeyDown, proxy: proxy)
                }
                post(event, proxy: proxy)
                pendingKeyDown = nil
                return false
            case .consumed:
                state = .idle
                return false
            case .idle:
                break
            }
        }

        if swallowedKeys.remove(keyCode) != nil {
            return false
        }
        return true
    }

    private func beginTrigger(with event: CGEvent) {
        pendingKeyDown = event.copy()
        state = .waiting
        cancelTimer()
        let timer = Timer(timeInterval: longPressDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.longPressFired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func longPressFired() {
        timer = nil
        guard state == .waiting else { return }
        state = .consumed
        pendingKeyDown = nil
        onTrigger?()
    }

    private func flushPendingTrigger(proxy: CGEventTapProxy, followedBy event: CGEvent) {
        cancelTimer()
        state = .idle
        if let pendingKeyDown {
            post(pendingKeyDown, proxy: proxy)
        }
        pendingKeyDown = nil
        post(event, proxy: proxy)
    }

    private func post(_ event: CGEvent, proxy: CGEventTapProxy) {
        guard let copy = event.copy() else { return }
        SyntheticEvent.tag(copy)
        copy.tapPostEvent(proxy)
    }

    private func resetTriggerState() {
        cancelTimer()
        state = .idle
        pendingKeyDown = nil
        swallowedKeys.removeAll()
    }

    private func isTriggerKey(_ event: CGEvent) -> Bool {
        !hasCommandModifiers(event.flags) && typesQuestionMark(event)
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func typesQuestionMark(_ event: CGEvent) -> Bool {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        if length > 0 {
            return String(utf16CodeUnits: buffer, count: length) == "?"
        }
        return NSEvent(cgEvent: event)?.characters == "?"
    }

    private func hasCommandModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
    }

    private func panelKey(for event: CGEvent) -> PanelKey? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let shift = flags.contains(.maskShift)

        if flags.contains(.maskCommand) {
            guard flags.intersection([.maskControl, .maskAlternate, .maskShift]).isEmpty else { return nil }
            switch keyCode {
            case KeyCode.r: return .refresh
            case KeyCode.e: return .rewrite
            default: return nil
            }
        }
        if hasCommandModifiers(flags) { return nil }

        switch keyCode {
        case KeyCode.up: return .up
        case KeyCode.down: return .down
        case KeyCode.left: return .left
        case KeyCode.right: return .right
        case KeyCode.returnKey, KeyCode.keypadEnter: return .select
        case KeyCode.escape: return .dismiss
        case KeyCode.tab: return shift ? .up : .down
        default:
            guard !shift, let number = KeyCode.digits[keyCode] else { return nil }
            return .number(number)
        }
    }
}

private extension PanelKey {
    var isNavigation: Bool {
        switch self {
        case .up, .down, .left, .right: true
        default: false
        }
    }
}
