import Foundation
import Observation

enum MeaningLanguage: Equatable {
    case original, native
}

enum MeaningPhase: Equatable {
    case loading(String)
    case loaded(WordMeaning)
    case failed(String, String)
}

enum RewritePhase: Equatable {
    case loading
    case loaded([Rewrite])
    case failed(String)
}

@MainActor
@Observable
final class SuggestionSession {
    var context: TextContext?
    var phase: SuggestionPhase = .idle
    var selectedIndex: Int = 0
    var model: String = ""
    var engine: SuggestionEngine = .onDevice
    var isFallback = false
    var startedAt: Date?
    var meaning: MeaningPhase?
    var meaningLanguage: MeaningLanguage = .original
    var nativeLanguageName: String = ""
    var meaningCache: [String: WordMeaning] = [:]
    var isRewriting = false
    var rewrite: RewritePhase?
    var rewriteTarget: RewriteTarget?
    var rewriteIndex = 0

    var rewrites: [Rewrite] {
        if case let .loaded(rewrites)? = rewrite { return rewrites }
        return []
    }

    var selectedRewrite: Rewrite? {
        rewrites.indices.contains(rewriteIndex) ? rewrites[rewriteIndex] : nil
    }

    func moveRewriteSelection(by delta: Int) {
        guard !rewrites.isEmpty else { return }
        rewriteIndex = ((rewriteIndex + delta) % rewrites.count + rewrites.count) % rewrites.count
    }

    func clearRewrite() {
        isRewriting = false
        rewrite = nil
        rewriteTarget = nil
        rewriteIndex = 0
    }

    var words: [String] {
        if case let .loaded(words) = phase { return words }
        return []
    }

    var isShowingMeaning: Bool { meaning != nil }

    func reset(context: TextContext?, model: String) {
        self.context = context
        self.model = model
        phase = .loading
        selectedIndex = 0
        startedAt = Date()
        meaning = nil
        meaningCache = [:]
        clearRewrite()
    }

    func moveSelection(by delta: Int) {
        guard !words.isEmpty else { return }
        selectedIndex = ((selectedIndex + delta) % words.count + words.count) % words.count
    }

    var selectedWord: String? {
        words.indices.contains(selectedIndex) ? words[selectedIndex] : nil
    }
}
