import AppKit

enum TextReplacer {
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let snapshotTypeSize = 64 * 1024 * 1024
    private static let pollInterval = 80
    private static let unreadableDelay: Duration = .milliseconds(1000)
    private static let maxWait: Duration = .milliseconds(3000)

    @MainActor
    static func replace(_ target: RewriteTarget, with rewrite: String) async {
        let text = target.replacement(for: rewrite)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await ClipboardContextReader.waitForModifierRelease()

        let pasteboard = NSPasteboard.general
        let saved = ClipboardContextReader.snapshot(of: pasteboard, maxTypeSize: snapshotTypeSize)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])
        let pastedCount = pasteboard.changeCount
        let limit = max(RewritePlanner.maxLength * 2, (text as NSString).length * 2)
        let before = await Task.detached { FocusedTextReader.focusedFieldText(maxLength: limit) }.value

        if target.scope == .field {
            ClipboardContextReader.press(KeyboardLayout.keyCode(for: "a", fallback: KeyboardLayout.ansiA), flags: [.maskCommand])
            await ClipboardContextReader.pause(milliseconds: 60)
        }
        ClipboardContextReader.press(KeyboardLayout.keyCode(for: "v", fallback: KeyboardLayout.ansiV), flags: [.maskCommand])

        let confirmed = await waitForPaste(of: text, scope: target.scope, before: before, limit: limit)
        if pasteboard.changeCount == pastedCount {
            ClipboardContextReader.restore(saved, to: pasteboard)
        }
        DebugLog.write("rewrite replaced scope=\(target.scope.rawValue) length=\(text.count) confirmed=\(confirmed)")
    }

    // The target app reads the pasteboard only when it handles ⌘V, so an early restore pastes the old clipboard.
    @MainActor
    private static func waitForPaste(of text: String, scope: RewriteScope, before: String?, limit: Int) async -> Bool {
        let expected = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = ContinuousClock.now
        var readable = false
        while ContinuousClock.now - start < maxWait {
            await ClipboardContextReader.pause(milliseconds: pollInterval)
            let current = await Task.detached { FocusedTextReader.focusedFieldText(maxLength: limit) }.value
            if let current {
                readable = true
                if isPasted(expected, scope: scope, before: before, current: current) { return true }
            } else if !readable, ContinuousClock.now - start >= unreadableDelay {
                return false
            }
        }
        return false
    }

    static func isPasted(_ expected: String, scope: RewriteScope, before: String?, current: String) -> Bool {
        if scope == .field, current.trimmingCharacters(in: .whitespacesAndNewlines) == expected { return true }
        return occurrences(of: expected, in: current) > occurrences(of: expected, in: before ?? "")
    }

    static func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return text.components(separatedBy: needle).count - 1
    }
}
