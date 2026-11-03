import Foundation
import Testing
@testable import NextWord

@MainActor
struct SuggestionSessionTests {
    private func loadedSession(_ words: [String], selected: Int = 0) -> SuggestionSession {
        let session = SuggestionSession()
        session.phase = .loaded(words)
        session.selectedIndex = selected
        return session
    }

    private let sampleContext = TextContext(
        appName: "Notes",
        bundleID: "com.apple.Notes",
        windowTitle: nil,
        textBeforeCursor: "Hello ",
        textAfterCursor: "",
        caretRect: nil
    )

    private let sampleMeaning = WordMeaning(
        word: "world",
        partOfSpeech: "noun",
        definition: "The earth.",
        example: nil,
        nativeLanguage: "Italian",
        nativeTranslation: "mondo",
        nativeDefinition: "La terra."
    )

    @Test func resetClearsStateAndStartsLoading() {
        let session = loadedSession(["a", "b", "c"], selected: 2)
        session.meaning = .loaded(sampleMeaning)
        session.meaningCache = ["world": sampleMeaning]

        session.reset(context: sampleContext, model: "sonnet")

        #expect(session.context == sampleContext)
        #expect(session.model == "sonnet")
        #expect(session.phase == .loading)
        #expect(session.selectedIndex == 0)
        #expect(session.startedAt != nil)
        #expect(session.meaning == nil)
        #expect(session.meaningCache.isEmpty)
        #expect(session.words.isEmpty)
    }

    @Test func resetAcceptsNilContext() {
        let session = SuggestionSession()
        session.context = sampleContext
        session.reset(context: nil, model: "haiku")
        #expect(session.context == nil)
        #expect(session.phase == .loading)
    }

    @Test func wordsAreEmptyUnlessLoaded() {
        let session = SuggestionSession()
        for phase in [SuggestionPhase.idle, .loading, .failed("boom")] {
            session.phase = phase
            #expect(session.words.isEmpty)
        }
        session.phase = .loaded(["x"])
        #expect(session.words == ["x"])
    }

    @Test(arguments: [
        (0, 1, 1),
        (1, 1, 2),
        (2, 1, 0),
        (0, -1, 2),
        (2, -1, 1),
        (1, 3, 1),
        (1, -3, 1),
    ])
    func moveSelectionWrapsAround(start: Int, delta: Int, expected: Int) {
        let session = loadedSession(["a", "b", "c"], selected: start)
        session.moveSelection(by: delta)
        #expect(session.selectedIndex == expected)
    }

    @Test(arguments: [1, -1])
    func moveSelectionWithSingleWordStaysOnIt(delta: Int) {
        let session = loadedSession(["only"])
        session.moveSelection(by: delta)
        #expect(session.selectedIndex == 0)
    }

    @Test(arguments: [1, -1])
    func moveSelectionWithoutWordsDoesNothing(delta: Int) {
        let session = SuggestionSession()
        session.phase = .loading
        session.moveSelection(by: delta)
        #expect(session.selectedIndex == 0)
    }

    @Test func moveSelectionByMoreThanCountStaysInRange() {
        let session = loadedSession(["a", "b", "c"], selected: 0)
        session.moveSelection(by: -4)
        #expect(session.selectedIndex == 2)
    }

    @Test func selectedWordFollowsIndex() {
        let session = loadedSession(["a", "b", "c"], selected: 1)
        #expect(session.selectedWord == "b")
        session.moveSelection(by: 1)
        #expect(session.selectedWord == "c")
    }

    @Test func selectedWordIsNilWithoutWords() {
        let session = SuggestionSession()
        session.phase = .failed("boom")
        #expect(session.selectedWord == nil)
    }

    @Test func selectedWordIsNilWhenIndexOutOfRange() {
        let session = loadedSession(["a"], selected: 3)
        #expect(session.selectedWord == nil)
    }

    @Test func isShowingMeaningTracksMeaningPhase() {
        let session = SuggestionSession()
        #expect(!session.isShowingMeaning)
        session.meaning = .loading("world")
        #expect(session.isShowingMeaning)
        session.meaning = .failed("world", "boom")
        #expect(session.isShowingMeaning)
        session.meaning = .loaded(sampleMeaning)
        #expect(session.isShowingMeaning)
        session.meaning = nil
        #expect(!session.isShowingMeaning)
    }
}
