import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum ClipboardContextReader {
    private enum KeyCode {
        static let left: CGKeyCode = 123
        static let right: CGKeyCode = 124
    }

    private static let copyTimeout: Duration = .milliseconds(600)
    private static let maxSnapshotTypeSize = 5 * 1024 * 1024
    private static let blockedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.apple.dt.Xcode",
        "com.apple.finder",
    ]
    private static let blockedBundlePrefixes = ["com.jetbrains.", "com.sublimetext."]

    static func canUseFallback(for context: TextContext?, bundleID: String?) -> Bool {
        canUseFallback(for: context, bundleID: bundleID, secureInput: IsSecureEventInputEnabled())
    }

    static func canUseFallback(for context: TextContext?, bundleID: String?, secureInput: Bool) -> Bool {
        if secureInput || context?.isSecureField == true { return false }
        if let bundleID = bundleID ?? context?.bundleID, isBlocked(bundleID) { return false }
        if let context, context.valueReadable { return false }
        return true
    }

    static func isBlocked(_ bundleID: String) -> Bool {
        blockedBundleIDs.contains(bundleID) || blockedBundlePrefixes.contains { bundleID.hasPrefix($0) }
    }

    @MainActor
    static func readTextBeforeCursor() async -> String? {
        await waitForModifierRelease()
        guard !Task.isCancelled else { return nil }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let startCount = pasteboard.changeCount

        press(KeyCode.left, flags: [.maskCommand, .maskShift])
        await pause(milliseconds: 60)

        var copySent = false
        var copied: String?
        if !Task.isCancelled {
            press(KeyboardLayout.keyCode(for: "c", fallback: KeyboardLayout.ansiC), flags: [.maskCommand])
            copySent = true
            copied = await waitForCopiedString(on: pasteboard, since: startCount)
        }

        let changed = pasteboard.changeCount != startCount
        if !copySent || copied != nil || changed {
            press(KeyCode.right, flags: [])
        }
        if changed {
            restore(saved, to: pasteboard)
        }

        let cancelled = Task.isCancelled
        DebugLog.write("clipboard fallback copied=\(copied != nil) length=\(copied?.count ?? 0) changed=\(changed) cancelled=\(cancelled)")
        return cancelled ? nil : copied
    }

    @MainActor
    static func copyText(selectingAll: Bool) async -> String? {
        await waitForModifierRelease()
        guard !Task.isCancelled else { return nil }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let startCount = pasteboard.changeCount

        if selectingAll {
            press(KeyboardLayout.keyCode(for: "a", fallback: KeyboardLayout.ansiA), flags: [.maskCommand])
            await pause(milliseconds: 60)
        }
        press(KeyboardLayout.keyCode(for: "c", fallback: KeyboardLayout.ansiC), flags: [.maskCommand])
        let copied = await waitForCopiedString(on: pasteboard, since: startCount)

        if selectingAll {
            press(KeyCode.right, flags: [])
        }
        let changed = pasteboard.changeCount != startCount
        if changed {
            restore(saved, to: pasteboard)
        }

        let cancelled = Task.isCancelled
        DebugLog.write("clipboard copy selectAll=\(selectingAll) copied=\(copied != nil) length=\(copied?.count ?? 0) changed=\(changed) cancelled=\(cancelled)")
        return cancelled ? nil : copied
    }

    @MainActor
    static func waitForModifierRelease() async {
        for _ in 0..<60 where modifiersHeld() {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor
    private static func waitForCopiedString(on pasteboard: NSPasteboard, since startCount: Int) async -> String? {
        let deadline = ContinuousClock.now + copyTimeout
        while ContinuousClock.now < deadline {
            await pause(milliseconds: 25)
            if pasteboard.changeCount != startCount, let string = pasteboard.string(forType: .string) {
                return string
            }
        }
        return nil
    }

    @MainActor
    static func pause(milliseconds: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
    }

    private static func modifiersHeld() -> Bool {
        !CGEventSource.flagsState(.hidSystemState).intersection([.maskShift, .maskCommand, .maskAlternate, .maskControl]).isEmpty
    }

    @MainActor
    static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { continue }
            event.flags = flags
            SyntheticEvent.tag(event)
            event.post(tap: .cghidEventTap)
        }
    }

    static func typesToSnapshot(_ types: [NSPasteboard.PasteboardType]) -> [NSPasteboard.PasteboardType] {
        let kept = types.filter { !$0.rawValue.lowercased().contains("promise") }
        let declared = kept.filter { !$0.rawValue.hasPrefix("dyn.") }
        return declared.isEmpty ? kept : declared
    }

    static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in typesToSnapshot(item.types) {
                guard let data = item.data(forType: type), data.count <= maxSnapshotTypeSize else { continue }
                entry[type] = data
            }
            return entry
        }
    }

    static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.filter { !$0.isEmpty }.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        guard !restored.isEmpty else { return }
        pasteboard.writeObjects(restored)
    }
}
