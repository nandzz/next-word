import AppKit
import ApplicationServices
import os

enum FocusedTextReader {
    private static let messagingTimeout: Float = 0.25
    private static let maxAfterLength = 200
    private static let retryDelays: [TimeInterval] = [0, 0.05, 0.12]
    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXSecureTextField"]
    private static let secureRole = "AXSecureTextField"
    private static let chromiumBrowserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
    ]
    private static let electronBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.microsoft.VSCode",
        "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",
    ]

    enum AppKind: Sendable {
        case native
        case electron
        case chromiumBrowser
    }

    private struct State {
        var kinds: [pid_t: AppKind] = [:]
        var enhancedPIDs: Set<pid_t> = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    private struct Focus {
        var app: AXUIElement
        var runningApp: NSRunningApplication?
        var kind: AppKind
        var focused: AXUIElement?
    }

    private static func focus() -> Focus? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        guard let (appElement, pid) = focusedApplication(systemWide: systemWide) else { return nil }
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let kind = appKind(pid: pid, bundleID: runningApp?.bundleIdentifier, bundleURL: runningApp?.bundleURL)
        enableAccessibility(appElement, pid: pid, kind: kind, atTrigger: true)

        var focused: AXUIElement?
        for delay in kind == .native ? [0] : retryDelays {
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            focused = element(appElement, kAXFocusedUIElementAttribute) ?? element(systemWide, kAXFocusedUIElementAttribute)
            if focused != nil { break }
        }
        if let focused { AXUIElementSetMessagingTimeout(focused, messagingTimeout) }
        return Focus(app: appElement, runningApp: runningApp, kind: kind, focused: focused)
    }

    private static func isSecure(role: String?, subrole: String?) -> Bool {
        role == secureRole || subrole == secureRole
    }

    nonisolated static func readContext(maxLength: Int, primaryScreenHeight: CGFloat) -> TextContext? {
        guard let focus = focus() else {
            DebugLog.write("ax: no focused application")
            return nil
        }
        let appName = focus.runningApp?.localizedName ?? "Unknown"
        let bundleID = focus.runningApp?.bundleIdentifier
        guard let focused = focus.focused else {
            DebugLog.write("ax: \(bundleID ?? appName) kind=\(focus.kind) no focused element, error=\(lastError(focus.app, kAXFocusedUIElementAttribute))")
            return nil
        }

        let windowTitle = element(focus.app, kAXFocusedWindowAttribute).flatMap { string($0, kAXTitleAttribute) }
        let role = string(focused, kAXRoleAttribute)
        let subrole = string(focused, kAXSubroleAttribute)
        let isSecure = isSecure(role: role, subrole: subrole)
        let selection = range(focused, kAXSelectedTextRangeAttribute)
        let isTextElement = role.map(textRoles.contains) == true || selection != nil

        var text: TextWindow?
        if !isSecure {
            text = readText(focused, selection: selection, maxLength: max(maxLength, 0))
        }

        let caretLocation = text?.caretLocation ?? selection.map { max($0.location, 0) }
        DebugLog.write("ax: \(bundleID ?? appName) role=\(role ?? "?") subrole=\(subrole ?? "?") read=\(text?.source ?? "none") before=\(text?.before.count ?? 0) after=\(text?.after.count ?? 0) selection=\(text?.selectionLength ?? 0) text=\(isTextElement) secure=\(isSecure) caret=\(caretLocation != nil)")

        let caretRect = caretLocation.flatMap { caretBounds(in: focused, at: $0) } ?? elementFallbackRect(focused)

        return TextContext(
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            textBeforeCursor: text?.before ?? "",
            textAfterCursor: text?.after ?? "",
            caretRect: caretRect.map { toCocoaCoordinates($0, primaryScreenHeight: primaryScreenHeight) },
            selectionLength: text?.selectionLength ?? max(selection?.length ?? 0, 0),
            valueReadable: text != nil || !isTextElement,
            isSecureField: isSecure
        )
    }

    nonisolated static func readField(maxLength: Int) -> FieldSnapshot? {
        guard let focus = focus(), let focused = focus.focused else { return nil }
        let bundleID = focus.runningApp?.bundleIdentifier
        let role = string(focused, kAXRoleAttribute)
        let subrole = string(focused, kAXSubroleAttribute)
        let isTextRole = role.map(textRoles.contains) == true
        let selection = range(focused, kAXSelectedTextRangeAttribute)
        var snapshot = FieldSnapshot(
            bundleID: bundleID,
            isEditable: isTextRole || isSettable(focused, kAXSelectedTextAttribute) || isSettable(focused, kAXValueAttribute),
            isSecure: isSecure(role: role, subrole: subrole),
            selectionLength: max(selection?.length ?? 0, 0)
        )
        guard !snapshot.isSecure else { return snapshot }

        if snapshot.selectionLength > 0, let selected = string(focused, kAXSelectedTextAttribute), !selected.isEmpty {
            snapshot.selectedText = selected
        }
        let count = integer(focused, kAXNumberOfCharactersAttribute)
        snapshot.fieldLength = count
        snapshot.fieldText = fieldText(of: focused, count: count, readsUnknownLength: isTextRole, maxLength: maxLength)
        if count == nil, let text = snapshot.fieldText {
            snapshot.fieldLength = (text as NSString).length
        }
        DebugLog.write("ax field: \(bundleID ?? "?") role=\(role ?? "?") editable=\(snapshot.isEditable) selection=\(snapshot.selectionLength) selected=\(snapshot.selectedText?.count ?? -1) field=\(snapshot.fieldText?.count ?? -1) length=\(snapshot.fieldLength ?? -1)")
        return snapshot
    }

    nonisolated static func focusedFieldText(maxLength: Int) -> String? {
        guard let focused = focus()?.focused else { return nil }
        let isTextRole = string(focused, kAXRoleAttribute).map(textRoles.contains) == true
        return fieldText(of: focused, count: integer(focused, kAXNumberOfCharactersAttribute), readsUnknownLength: isTextRole, maxLength: maxLength)
    }

    private static func fieldText(of focused: AXUIElement, count: Int?, readsUnknownLength: Bool, maxLength: Int) -> String? {
        if let count {
            guard count >= 0, count <= maxLength else { return nil }
            if count == 0 { return "" }
            if let text = string(focused, for: CFRange(location: 0, length: count)) { return text }
        } else if !readsUnknownLength {
            return nil
        }
        guard let value = string(focused, kAXValueAttribute), (value as NSString).length <= maxLength else { return nil }
        return value
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    nonisolated static func prepare(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier
        let bundleURL = app.bundleURL
        DispatchQueue.global(qos: .userInitiated).async {
            let kind = appKind(pid: pid, bundleID: bundleID, bundleURL: bundleURL)
            guard kind != .native else { return }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            enableAccessibility(element, pid: pid, kind: kind, atTrigger: false)
        }
    }

    private struct TextWindow {
        var before: String
        var after: String
        var selectionLength: Int
        var caretLocation: Int
        var source: String
    }

    private static func readText(_ focused: AXUIElement, selection: CFRange?, maxLength: Int) -> TextWindow? {
        if let selection, let count = integer(focused, kAXNumberOfCharactersAttribute), count >= 0 {
            let location = min(max(selection.location, 0), count)
            let selectionEnd = min(max(location + max(selection.length, 0), location), count)
            let start = max(0, location - maxLength)
            let end = min(count, selectionEnd + maxAfterLength)
            if end > start, let window = string(focused, for: CFRange(location: start, length: end - start)).map({ $0 as NSString }),
               window.length == end - start {
                return TextWindow(
                    before: substring(of: window, from: 0, to: location - start, clipsStart: start > 0),
                    after: substring(of: window, from: selectionEnd - start, to: window.length, clipsEnd: end < count),
                    selectionLength: selectionEnd - location,
                    caretLocation: location,
                    source: "range"
                )
            }
        }

        guard let value = string(focused, kAXValueAttribute) else { return nil }
        let text = value as NSString
        let resolved = selection ?? CFRange(location: text.length, length: 0)
        let location = min(max(resolved.location, 0), text.length)
        let selectionEnd = min(max(location + max(resolved.length, 0), location), text.length)
        return TextWindow(
            before: substring(of: text, from: max(0, location - maxLength), to: location),
            after: substring(of: text, from: selectionEnd, to: min(text.length, selectionEnd + maxAfterLength)),
            selectionLength: selectionEnd - location,
            caretLocation: location,
            source: "value"
        )
    }

    private static func appKind(pid: pid_t, bundleID: String?, bundleURL: URL?) -> AppKind {
        if let cached = state.withLock({ $0.kinds[pid] }) { return cached }
        let kind = detectKind(bundleID: bundleID, bundleURL: bundleURL)
        state.withLock { $0.kinds[pid] = kind }
        return kind
    }

    static func detectKind(bundleID: String?, bundleURL: URL?) -> AppKind {
        if let bundleID {
            if chromiumBrowserBundleIDs.contains(bundleID) { return .chromiumBrowser }
            if electronBundleIDs.contains(bundleID) { return .electron }
        }
        guard let bundleURL else { return .native }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        let markers = ["Electron Framework.framework", "Chromium Embedded Framework.framework"]
        let embedsChromium = markers.contains { FileManager.default.fileExists(atPath: frameworks.appendingPathComponent($0).path) }
        return embedsChromium ? .electron : .native
    }

    private static func enableAccessibility(_ appElement: AXUIElement, pid: pid_t, kind: AppKind, atTrigger: Bool) {
        switch kind {
        case .native:
            return
        case .electron:
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        case .chromiumBrowser:
            guard atTrigger else { return }
            let isNew = state.withLock { $0.enhancedPIDs.insert(pid).inserted }
            guard isNew else { return }
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    private static func lastError(_ element: AXUIElement, _ attribute: String) -> Int32 {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value).rawValue
    }

    private static func focusedApplication(systemWide: AXUIElement) -> (AXUIElement, pid_t)? {
        if let app = element(systemWide, kAXFocusedApplicationAttribute) {
            var pid: pid_t = 0
            if AXUIElementGetPid(app, &pid) == .success, pid > 0 {
                return (app, pid)
            }
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = front.processIdentifier
        return (AXUIElementCreateApplication(pid), pid)
    }

    private static func caretBounds(in element: AXUIElement, at location: Int) -> CGRect? {
        if let rect = bounds(element, for: CFRange(location: location, length: 0)), rect.height > 0 {
            return CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 1), height: rect.height)
        }
        if location > 0, let rect = bounds(element, for: CFRange(location: location - 1, length: 1)),
           rect.width > 0 || rect.height > 0 {
            return CGRect(x: rect.maxX, y: rect.minY, width: 1, height: max(rect.height, 1))
        }
        return nil
    }

    private static func elementFallbackRect(_ element: AXUIElement) -> CGRect? {
        guard let position = point(element, kAXPositionAttribute),
              let size = size(element, kAXSizeAttribute)
        else { return nil }
        let lineHeight = min(max(size.height, 1), 20)
        return CGRect(x: position.x + 4, y: position.y + size.height - lineHeight, width: 1, height: lineHeight)
    }

    static func toCocoaCoordinates(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        guard primaryScreenHeight > 0 else { return rect }
        return CGRect(x: rect.minX, y: primaryScreenHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
    }

    static func substring(of text: NSString, from start: Int, to end: Int, clipsStart: Bool = false, clipsEnd: Bool = false) -> String {
        var lower = min(max(start, 0), text.length)
        var upper = min(max(end, lower), text.length)
        if clipsStart, lower < upper, UTF16.isTrailSurrogate(text.character(at: lower)) { lower += 1 }
        if clipsEnd, upper > lower, UTF16.isLeadSurrogate(text.character(at: upper - 1)) { upper -= 1 }
        if lower > 0, lower < text.length {
            let sequence = text.rangeOfComposedCharacterSequence(at: lower)
            if sequence.location < lower { lower = NSMaxRange(sequence) }
        }
        if upper > 0, upper < text.length {
            let sequence = text.rangeOfComposedCharacterSequence(at: upper)
            if sequence.location < upper { upper = sequence.location }
        }
        guard upper > lower else { return "" }
        return text.substring(with: NSRange(location: lower, length: upper - lower))
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    private static func integer(_ element: AXUIElement, _ attribute: String) -> Int? {
        (copyValue(element, attribute) as? NSNumber)?.intValue
    }

    private static func string(_ element: AXUIElement, for range: CFRange) -> String? {
        var cfRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &result
        )
        guard status == .success else { return nil }
        return result as? String
    }

    private static func axValue(_ value: CFTypeRef?, type: AXValueType) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = axValue(copyValue(element, attribute), type: .cfRange) else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(copyValue(element, attribute), type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(copyValue(element, attribute), type: .cgSize) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func bounds(_ element: AXUIElement, for range: CFRange) -> CGRect? {
        var cfRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &result
        )
        guard status == .success, let value = axValue(result, type: .cgRect) else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect), !rect.isNull, !rect.isInfinite else { return nil }
        return rect
    }
}
