import AppKit
import SwiftUI

@MainActor
final class SuggestionPanelController {
    var onSelect: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenMeaning: (() -> Void)?
    var onMeaningBack: (() -> Void)?

    var isVisible: Bool { isShown }

    private let session: SuggestionSession
    private let settings: SettingsStore
    private let panel = SuggestionPanel()
    private let hostingView: PanelHostingView<SuggestionPanelView>
    private var isShown = false
    private var anchorRect: CGRect = .zero
    private var placement: PanelPlacement = .below
    private var presentationID = UUID()
    private var contentSize: CGSize = .zero
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private static let caretGap: CGFloat = 6
    private static let screenMargin: CGFloat = 6

    init(session: SuggestionSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
        hostingView = PanelHostingView(rootView: SuggestionPanelView(session: session, settings: settings))
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
    }

    func show(near caretRect: CGRect?) {
        anchorRect = caretRect.flatMap { $0.isNull || $0.isInfinite ? nil : $0 } ?? Self.mouseAnchor()
        let wasShown = isShown
        isShown = true
        if !wasShown {
            presentationID = UUID()
        }

        hostingView.rootView = makeRootView()
        let size = measuredSize()
        contentSize = size
        let frame = resolveFrame(for: size, preferring: nil)
        hostingView.rootView = makeRootView()
        panel.setFrame(frame, display: true)

        if wasShown {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        installMonitors()
        refreshShadowSoon()
        DebugLog.write("panel show anchor=\(anchorRect) fitting=\(size) frame=\(panel.frame) visible=\(panel.isVisible) screens=\(NSScreen.screens.map(\.frame))")
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        DebugLog.write("panel hide")
        removeMonitors()
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func makeRootView() -> SuggestionPanelView {
        SuggestionPanelView(
            session: session,
            settings: settings,
            placement: placement,
            presentationID: presentationID,
            onSelect: { [weak self] word in self?.onSelect?(word) },
            onRefresh: { [weak self] in self?.onRefresh?() },
            onClose: { [weak self] in self?.onDismiss?() },
            onSizeChange: { [weak self] size in
                Task { @MainActor in self?.contentSizeDidChange(size) }
            },
            onOpenMeaning: onOpenMeaning.map { _ in { [weak self] in self?.onOpenMeaning?() } },
            onMeaningBack: onMeaningBack.map { _ in { [weak self] in self?.onMeaningBack?() } }
        )
    }

    private func measuredSize() -> CGSize {
        let measuring = NSHostingController(rootView: makeRootView().fixedSize())
        let size = measuring.sizeThatFits(in: CGSize(width: 800, height: 1200))
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    private func contentSizeDidChange(_ size: CGSize) {
        guard isShown, size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard rounded != contentSize else { return }
        contentSize = rounded
        DebugLog.write("panel resize \(rounded)")
        let previous = placement
        let frame = resolveFrame(for: rounded, preferring: placement)
        if placement != previous {
            hostingView.rootView = makeRootView()
        }
        panel.setFrame(frame, display: true)
        refreshShadowSoon()
    }

    private func resolveFrame(for size: CGSize, preferring preferred: PanelPlacement?) -> CGRect {
        let screen = Self.screen(containing: anchorRect)
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let margin = Self.screenMargin

        let belowY = anchorRect.minY - Self.caretGap - size.height
        let aboveY = anchorRect.maxY + Self.caretGap
        let fitsBelow = belowY >= visible.minY + margin
        let fitsAbove = aboveY + size.height <= visible.maxY - margin

        switch preferred {
        case .above? where fitsAbove:
            placement = .above
        case .below? where fitsBelow:
            placement = .below
        default:
            placement = fitsBelow || !fitsAbove ? .below : .above
        }

        var y = placement == .below ? belowY : aboveY
        y = min(max(y, visible.minY + margin), visible.maxY - margin - size.height)

        var x = anchorRect.minX - 8
        x = min(max(x, visible.minX + margin), visible.maxX - margin - size.width)

        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func refreshShadowSoon() {
        Task { @MainActor [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseDown(at: NSEvent.mouseLocation, in: nil)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseDown(at: NSEvent.mouseLocation, in: event.window)
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleMouseDown(at location: CGPoint, in window: NSWindow?) {
        guard isShown else { return }
        if window === panel || panel.frame.contains(location) { return }
        onDismiss?()
    }

    private static func mouseAnchor() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y - 20, width: 1, height: 20)
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
    }
}

final class SuggestionPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PanelHostingView<Content: View>: NSHostingView<Content> {
    private var hoverTrackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        // SwiftUI hover tracking is inactive in a window of an app that is not active; this keeps it alive.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }
}
