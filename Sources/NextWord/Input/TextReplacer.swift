import AppKit

enum TextReplacer {
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let restoreDelay = 450

    @MainActor
    static func replace(_ target: RewriteTarget, with rewrite: String) async {
        let text = target.replacement(for: rewrite)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await ClipboardContextReader.waitForModifierRelease()

        let pasteboard = NSPasteboard.general
        let saved = ClipboardContextReader.snapshot(of: pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])
        let pastedCount = pasteboard.changeCount

        if target.scope == .field {
            ClipboardContextReader.press(KeyboardLayout.keyCode(for: "a", fallback: KeyboardLayout.ansiA), flags: [.maskCommand])
            await ClipboardContextReader.pause(milliseconds: 60)
        }
        ClipboardContextReader.press(KeyboardLayout.keyCode(for: "v", fallback: KeyboardLayout.ansiV), flags: [.maskCommand])

        // The target app reads the pasteboard after it handles ⌘V, so an early restore pastes the old clipboard.
        await ClipboardContextReader.pause(milliseconds: restoreDelay)
        if pasteboard.changeCount == pastedCount {
            ClipboardContextReader.restore(saved, to: pasteboard)
        }
        DebugLog.write("rewrite replaced scope=\(target.scope.rawValue) length=\(text.count)")
    }
}
