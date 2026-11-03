import AppKit
import CoreGraphics

enum TextInserter {
    private static let chunkLength = 20
    private static let openingCharacters: Set<Character> = ["(", "[", "{", "<", "\"", "'", "“", "‘", "«", "¿", "¡", "/", "@", "#"]
    private static let leadingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "…", "'", "’"]
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "…", "'", "’", "\""]

    private struct Plan {
        var text: String
        var backspaces: Int
    }

    @MainActor
    static func insert(_ word: String, after context: TextContext?) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let plan = plan(for: trimmed, context: context)
        if plan.backspaces > 0 {
            pressBackspace(times: plan.backspaces)
        }
        type(plan.text)
    }

    static func composedText(for word: String, context: TextContext?) -> String {
        plan(for: word, context: context).text
    }

    static func backspaceCount(for word: String, context: TextContext?) -> Int {
        plan(for: word, context: context).backspaces
    }

    static func completedPartialWord(for word: String, context: TextContext?) -> String? {
        let before = context?.textBeforeCursor ?? ""
        guard let first = word.first, first.isLetter || first.isNumber,
              let token = PartialWord.trailing(in: before) else { return nil }
        if word.count > token.count, word.lowercased().hasPrefix(token.lowercased()) {
            return token
        }
        guard token.count > 1 else { return nil }
        return PartialWord.isUnfinished(token, context: before) ? token : nil
    }

    private static func plan(for word: String, context: TextContext?) -> Plan {
        var text = word
        var backspaces = 0
        if let partial = completedPartialWord(for: word, context: context) {
            backspaces = partial.count + ((context?.selectionLength ?? 0) > 0 ? 1 : 0)
            if partial.first?.isUppercase == true {
                text = text.prefix(1).uppercased() + text.dropFirst()
            }
        } else if needsLeadingSpace(before: context?.textBeforeCursor ?? "", word: word) {
            text = " " + text
        }
        if needsTrailingSpace(after: context?.textAfterCursor ?? "") {
            text += " "
        }
        return Plan(text: text, backspaces: backspaces)
    }

    @MainActor
    private static func pressBackspace(times: Int) {
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<times {
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: keyDown) else { continue }
                event.flags = []
                SyntheticEvent.tag(event)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private static func needsLeadingSpace(before: String, word: String) -> Bool {
        guard let last = before.last else { return false }
        if last.isWhitespace || openingCharacters.contains(last) { return false }
        if let first = word.first, leadingPunctuation.contains(first) { return false }
        return true
    }

    private static func needsTrailingSpace(after: String) -> Bool {
        guard let next = after.first else { return true }
        return !(next.isWhitespace || trailingPunctuation.contains(next))
    }

    @MainActor
    private static func type(_ text: String) {
        let source = CGEventSource(stateID: .privateState)
        for chunk in chunks(of: text) {
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.flags = []
                chunk.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
                SyntheticEvent.tag(event)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private static func chunks(of text: String) -> [[UniChar]] {
        var result: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty, current.count + units.count > chunkLength {
                result.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
