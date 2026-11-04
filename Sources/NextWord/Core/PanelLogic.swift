import Foundation

enum EngineResolver {
    struct Resolution: Equatable {
        let engine: SuggestionEngine
        let unavailableMessage: String?
        var isFallback: Bool = false
    }

    static func resolve(
        selected: SuggestionEngine,
        onDeviceAvailable: Bool,
        onDeviceMessage: String,
        codexAvailable: Bool,
        codexMissingMessage: String,
        claudeAvailable: Bool,
        fallBackToClaude: Bool
    ) -> Resolution {
        let missingMessage: String
        switch selected {
        case .onDevice where !onDeviceAvailable:
            missingMessage = onDeviceMessage
        case .codex where !codexAvailable:
            missingMessage = codexMissingMessage
        default:
            return Resolution(engine: selected, unavailableMessage: nil)
        }
        if fallBackToClaude, claudeAvailable {
            return Resolution(engine: .claude, unavailableMessage: nil, isFallback: true)
        }
        return Resolution(engine: selected, unavailableMessage: missingMessage)
    }
}

enum PanelAction: Equatable {
    case moveSelection(Int)
    case openMeaning(MeaningLanguage)
    case setMeaningLanguage(MeaningLanguage)
    case closeMeaning
    case insertSelected
    case insert(index: Int)
    case retrySuggestions
    case refreshSuggestions
    case refreshMeaning
    case openRewrite
    case closeRewrite
    case moveRewriteSelection(Int)
    case applySelectedRewrite
    case applyRewrite(index: Int)
    case refreshRewrite
    case dismiss
    case none
}

struct PanelState: Equatable {
    var isShowingMeaning: Bool
    var meaningLanguage: MeaningLanguage
    var meaningEnabled: Bool
    var meaningStartsInNative: Bool
    var hasSelection: Bool
    var hasFailed: Bool
    var wordCount: Int
    var isRewriting = false
    var rewriteCount = 0
    var rewriteFailed = false
}

enum PanelNavigator {
    static func action(for key: PanelKey, in state: PanelState) -> PanelAction {
        if state.isRewriting { return rewriteAction(for: key, in: state) }
        switch key {
        case .up:
            return state.wordCount > 0 ? .moveSelection(-1) : .none
        case .down:
            return state.wordCount > 0 ? .moveSelection(1) : .none
        case .right:
            if !state.isShowingMeaning {
                guard state.meaningEnabled, state.hasSelection else { return .none }
                return .openMeaning(state.meaningStartsInNative ? .native : .original)
            }
            return state.meaningLanguage == .original ? .setMeaningLanguage(.native) : .none
        case .left:
            guard state.isShowingMeaning else { return .none }
            if state.meaningLanguage == .native, !state.meaningStartsInNative {
                return .setMeaningLanguage(.original)
            }
            return .closeMeaning
        case .select:
            if state.hasSelection { return .insertSelected }
            return state.hasFailed ? .retrySuggestions : .none
        case let .number(n):
            return n >= 1 && n <= state.wordCount ? .insert(index: n - 1) : .none
        case .refresh:
            return state.isShowingMeaning ? .refreshMeaning : .refreshSuggestions
        case .rewrite:
            return .openRewrite
        case .dismiss:
            return .dismiss
        }
    }

    private static func rewriteAction(for key: PanelKey, in state: PanelState) -> PanelAction {
        switch key {
        case .up:
            return state.rewriteCount > 0 ? .moveRewriteSelection(-1) : .none
        case .down:
            return state.rewriteCount > 0 ? .moveRewriteSelection(1) : .none
        case .left, .rewrite:
            return .closeRewrite
        case .right:
            return .none
        case .select:
            if state.rewriteCount > 0 { return .applySelectedRewrite }
            return state.rewriteFailed ? .refreshRewrite : .none
        case let .number(n):
            return n >= 1 && n <= state.rewriteCount ? .applyRewrite(index: n - 1) : .none
        case .refresh:
            return .refreshRewrite
        case .dismiss:
            return .dismiss
        }
    }
}
