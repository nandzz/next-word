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
    }

    func moveSelection(by delta: Int) {
        guard !words.isEmpty else { return }
        selectedIndex = ((selectedIndex + delta) % words.count + words.count) % words.count
    }

    var selectedWord: String? {
        words.indices.contains(selectedIndex) ? words[selectedIndex] : nil
    }
}
