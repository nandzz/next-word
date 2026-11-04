import Foundation

enum RewriteStyle: String, CaseIterable, Sendable {
    case clearer, shorter, reworded

    var title: String {
        switch self {
        case .clearer: "Clearer"
        case .shorter: "Shorter"
        case .reworded: "Reworded"
        }
    }
}

struct Rewrite: Sendable, Equatable {
    var style: RewriteStyle
    var text: String
}

enum RewriteScope: String, Sendable, Equatable {
    case selection, field
}

struct RewriteTarget: Sendable, Equatable {
    var scope: RewriteScope
    var text: String

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func replacement(for rewrite: String) -> String {
        let leading = String(text.prefix(while: \.isWhitespace))
        let trailing = String(text.reversed().prefix(while: \.isWhitespace).reversed())
        return leading + rewrite.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
    }
}

struct FieldSnapshot: Sendable, Equatable {
    var bundleID: String?
    var isTextElement: Bool
    var isSecure: Bool
    var selectionLength: Int
    var selectedText: String? = nil
    var fieldText: String? = nil
    var fieldLength: Int? = nil
}

enum RewritePlan: Equatable {
    case ready(RewriteTarget)
    case copy(RewriteScope)
    case unavailable(String)
}

enum RewritePlanner {
    static let maxLength = 2000
    static let fieldBlockedBundleIDs: Set<String> = ["com.apple.mail", "com.microsoft.Outlook"]

    static let unreadableMessage = "NextWord cannot read the text in this app. Select the text, then push ⌘E."
    static let noTextFieldMessage = "Click in a text field, then try again."
    static let secureMessage = "NextWord does not rewrite password fields."
    static let selectFirstMessage = "Select the text to rewrite, then push ⌘E."
    static let emptyMessage = "Type a message first, then push ⌘E."
    static let fieldTooLongMessage = "This text is too long. Select the part to rewrite, then push ⌘E."
    static let selectionTooLongMessage = "This selection is too long. Select a shorter part, then push ⌘E."
    static let noChangesMessage = "NextWord found nothing to change in this text."

    static func plan(for field: FieldSnapshot?, bundleID: String?, canCopy: Bool) -> RewritePlan {
        let bundleID = field?.bundleID ?? bundleID
        let fieldBlocked = bundleID.map(blocksFieldRewrite) ?? false
        guard let field else {
            if fieldBlocked { return .unavailable(selectFirstMessage) }
            return canCopy ? .copy(.field) : .unavailable(unreadableMessage)
        }
        if field.isSecure { return .unavailable(secureMessage) }
        if field.selectionLength > 0 {
            if let selected = field.selectedText { return target(.selection, selected) }
            return canCopy ? .copy(.selection) : .unavailable(unreadableMessage)
        }
        guard field.isTextElement else { return .unavailable(noTextFieldMessage) }
        if fieldBlocked { return .unavailable(selectFirstMessage) }
        if let text = field.fieldText { return target(.field, text) }
        if let length = field.fieldLength, length > maxLength { return .unavailable(fieldTooLongMessage) }
        return canCopy ? .copy(.field) : .unavailable(unreadableMessage)
    }

    static func target(_ scope: RewriteScope, _ text: String) -> RewritePlan {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unavailable(scope == .selection ? selectFirstMessage : emptyMessage)
        }
        if text.count > maxLength {
            return .unavailable(scope == .selection ? selectionTooLongMessage : fieldTooLongMessage)
        }
        return .ready(RewriteTarget(scope: scope, text: text))
    }

    static func blocksFieldRewrite(_ bundleID: String) -> Bool {
        fieldBlockedBundleIDs.contains(bundleID) || ClipboardContextReader.isBlocked(bundleID)
    }
}
