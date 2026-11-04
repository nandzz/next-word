import AppKit
import Foundation

struct TextContext: Sendable, Equatable {
    var appName: String
    var bundleID: String?
    var windowTitle: String?
    var textBeforeCursor: String
    var textAfterCursor: String
    // Cocoa global coordinates: origin at the bottom-left of the primary screen (NSScreen.screens.first).
    var caretRect: CGRect?
    var selectionLength: Int = 0
    var valueReadable: Bool = true
    var isSecureField: Bool = false
}

enum SuggestionPhase: Equatable {
    case idle
    case loading
    case loaded([String])
    case failed(String)
}

enum PanelKey: Equatable {
    case up, down, left, right
    case select
    case dismiss
    case refresh
    case rewrite
    case number(Int)
}

enum Tone: String, CaseIterable, Identifiable, Codable, Sendable {
    case match, casual, neutral, formal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .match: "Match context"
        case .casual: "Casual"
        case .neutral: "Neutral"
        case .formal: "Formal"
        }
    }

    var promptHint: String {
        switch self {
        case .match: "Match the tone of the existing text and the app."
        case .casual: "Prefer casual, friendly words."
        case .neutral: "Prefer neutral, plain words."
        case .formal: "Prefer formal, professional words."
        }
    }
}

struct ClaudeModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let symbol: String

    static let custom = "custom"

    static let all: [ClaudeModelOption] = [
        .init(id: "haiku", name: "Haiku", detail: "Fastest. Best for live suggestions.", symbol: "hare"),
        .init(id: "sonnet", name: "Sonnet", detail: "Balanced speed and quality.", symbol: "dial.medium"),
        .init(id: "opus", name: "Opus", detail: "Highest quality. Slower.", symbol: "sparkles"),
        .init(id: "fable", name: "Fable", detail: "Most capable. Slowest.", symbol: "wand.and.stars"),
        .init(id: custom, name: "Custom", detail: "Any model name the CLI accepts.", symbol: "slider.horizontal.3"),
    ]
}

enum SuggestionEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case onDevice, claude, codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var detail: String {
        switch self {
        case .onDevice: "Apple Foundation Models. Instant and private."
        case .claude: "Claude Code CLI. Best quality, a few seconds."
        case .codex: "OpenAI Codex CLI. Uses your Codex login."
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: "apple.intelligence"
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct WordMeaning: Sendable, Equatable {
    var word: String
    var partOfSpeech: String?
    var definition: String
    var example: String?
    var nativeLanguage: String
    var nativeTranslation: String
    var nativeDefinition: String
}

struct SuggestionRequest: Sendable {
    var count: Int
    var model: String
    var tone: Tone
    var allowPhrases: Bool
    var language: String?
    var extraInstructions: String
    var claudePath: String?
    var timeout: TimeInterval
    var nativeLanguage: String
    var includeExample: Bool
    var codexPath: String? = nil
    var codexModel: String? = nil
}

protocol SuggestionProviding: Sendable {
    func suggestions(for context: TextContext, request: SuggestionRequest) async throws -> [String]
    func meaning(of word: String, in context: TextContext, request: SuggestionRequest) async throws -> WordMeaning
    func rewrites(of target: RewriteTarget, in context: TextContext, request: SuggestionRequest) async throws -> [Rewrite]
}
