import Foundation
import Testing
@testable import NextWord

struct OnDeviceRankTests {
    @available(macOS 26.0, *)
    @Test func partialCompletionsComeFirst() {
        let ranked = OnDeviceEngine.rank(["great", "fantastic", "nice", "fantasy"], partial: "fantas", allowPhrases: false)
        #expect(ranked == ["fantastic", "fantasy", "great", "nice"])
    }

    @available(macOS 26.0, *)
    @Test func partialMatchIgnoresCase() {
        let ranked = OnDeviceEngine.rank(["great", "Fantastic"], partial: "FANTAS", allowPhrases: false)
        #expect(ranked == ["Fantastic", "great"])
    }

    @available(macOS 26.0, *)
    @Test func wordEqualToPartialIsNotACompletion() {
        let ranked = OnDeviceEngine.rank(["really", "very", "reallyy"], partial: "really", allowPhrases: false)
        #expect(ranked == ["reallyy", "really", "very"])
    }

    @available(macOS 26.0, *)
    @Test func keepsOrderWhenNoCompletionMatches() {
        let ranked = OnDeviceEngine.rank(["great", "nice"], partial: "fantas", allowPhrases: false)
        #expect(ranked == ["great", "nice"])
    }

    @available(macOS 26.0, *)
    @Test func keepsOrderWithoutPartial() {
        let ranked = OnDeviceEngine.rank(["zeta", "alpha", "mid"], partial: nil, allowPhrases: false)
        #expect(ranked == ["zeta", "alpha", "mid"])
    }

    @available(macOS 26.0, *)
    @Test func cleansAndDropsEmptyCandidates() {
        let ranked = OnDeviceEngine.rank(["1. great", "  ", "\"nice.\""], partial: nil, allowPhrases: false)
        #expect(ranked == ["great", "nice"])
    }

    @available(macOS 26.0, *)
    @Test func filtersPhrasesWhenNotAllowed() {
        let ranked = OnDeviceEngine.rank(["very good", "nice", "quite nice", "great"], partial: nil, allowPhrases: false)
        #expect(ranked == ["nice", "great"])
    }

    @available(macOS 26.0, *)
    @Test func usesFirstWordsWhenOnlyPhrasesCameBack() {
        let ranked = OnDeviceEngine.rank(["very good", "quite nice"], partial: nil, allowPhrases: false)
        #expect(ranked == ["very", "quite"])
    }

    @available(macOS 26.0, *)
    @Test func keepsPhrasesWhenAllowed() {
        let ranked = OnDeviceEngine.rank(["very good", "nice"], partial: nil, allowPhrases: true)
        #expect(ranked == ["very good", "nice"])
    }

    @available(macOS 26.0, *)
    @Test func phraseCompletionsComeFirstWhenAllowed() {
        let ranked = OnDeviceEngine.rank(["nice", "fantastic day"], partial: "fantas", allowPhrases: true)
        #expect(ranked == ["fantastic day", "nice"])
    }

    @available(macOS 26.0, *)
    @Test func emptyInputGivesEmptyOutput() {
        #expect(OnDeviceEngine.rank([], partial: "abc", allowPhrases: false).isEmpty)
    }
}

@MainActor
struct OnDevicePromptSentenceTests {
    @Test func replacesPartialWordWithCompletion() {
        let sentence = OnDevicePrompt.sentence(inserting: "fantastic", into: Fixtures.context("It was fantas"))
        #expect(sentence == "It was fantastic")
    }

    @Test func insertsAfterSpaceAndKeepsTextAfter() {
        let sentence = OnDevicePrompt.sentence(inserting: "great", into: Fixtures.context("I feel ", " today."))
        #expect(sentence == "I feel great today.")
    }

    @Test func trimsOuterWhitespace() {
        let sentence = OnDevicePrompt.sentence(inserting: "there", into: Fixtures.context("  Hi ", "  "))
        #expect(sentence == "Hi there")
    }

    @Test func replacesAccentedPartial() {
        let sentence = OnDevicePrompt.sentence(inserting: "perché", into: Fixtures.context("Non so perch", "?"))
        #expect(sentence == "Non so perché?")
    }

    @Test func emptyContextGivesWord() {
        #expect(OnDevicePrompt.sentence(inserting: "Hello", into: Fixtures.context("")) == "Hello")
    }

    @Test func keepsCompleteWordBeforeCursor() {
        let sentence = OnDevicePrompt.sentence(inserting: "happy", into: Fixtures.context("I am really"))
        #expect(sentence == "I am really happy")
    }

    @Test func addsSpaceAfterPunctuationBeforeCursor() {
        let sentence = OnDevicePrompt.sentence(inserting: "world", into: Fixtures.context("Hello,"))
        #expect(sentence == "Hello, world")
    }

    @Test func replacesPartialWordCaseInsensitively() {
        let sentence = OnDevicePrompt.sentence(inserting: "fantastic", into: Fixtures.context("It was FANTAS"))
        #expect(sentence == "It was fantastic")
    }

    @Test func replacesUnfinishedWordWithOtherWord() {
        let sentence = OnDevicePrompt.sentence(inserting: "great", into: Fixtures.context("It was fantas"))
        #expect(sentence == "It was great")
    }

    @Test(arguments: [("(", "(word"), ("He said \u{201C}", "He said \u{201C}word"), ("#", "#word")])
    func noSpaceAfterOpeningCharacter(before: String, expected: String) {
        #expect(OnDevicePrompt.sentence(inserting: "word", into: Fixtures.context(before)) == expected)
    }

    @Test func addsSingleSpaceBeforeTrimmedWord() {
        let sentence = OnDevicePrompt.sentence(inserting: "  happy ", into: Fixtures.context("I am really"))
        #expect(sentence == "I am really happy")
    }

    @Test func capsLongTextBeforeCursor() {
        let long = String(repeating: "word ", count: 300)
        let sentence = OnDevicePrompt.sentence(inserting: "end", into: Fixtures.context(long))
        #expect(sentence.count <= OnDevicePrompt.maxCharactersBeforeCursor + 3)
        #expect(sentence.hasPrefix("word "))
        #expect(sentence.hasSuffix(" end"))
    }
}

struct OnDevicePromptCappingTests {
    @Test func shortTextIsUnchanged() {
        #expect(OnDevicePrompt.cappedBefore("short text") == "short text")
        #expect(OnDevicePrompt.cappedAfter("short text") == "short text")
    }

    @Test func cappedBeforeStartsAtWordBoundary() {
        let text = "x" + String(repeating: "abc ", count: 250)
        let capped = OnDevicePrompt.cappedBefore(text)
        #expect(capped.count < OnDevicePrompt.maxCharactersBeforeCursor)
        #expect(capped.hasPrefix("abc "))
        #expect(text.hasSuffix(capped))
    }

    @Test func cappedBeforeWithoutSpacesKeepsTail() {
        let text = String(repeating: "a", count: 1000)
        #expect(OnDevicePrompt.cappedBefore(text).count == OnDevicePrompt.maxCharactersBeforeCursor)
    }

    @Test func cappedAfterEndsAtWordBoundary() {
        let text = String(repeating: "abc ", count: 100) + "x"
        let capped = OnDevicePrompt.cappedAfter(text)
        #expect(capped.count < OnDevicePrompt.maxCharactersAfterCursor)
        #expect(capped.hasSuffix("abc"))
        #expect(text.hasPrefix(capped))
    }

    @Test func cappedAfterWithoutSpacesKeepsHead() {
        let text = String(repeating: "a", count: 500)
        #expect(OnDevicePrompt.cappedAfter(text).count == OnDevicePrompt.maxCharactersAfterCursor)
    }

    @Test func sentenceWithBlankMarksCursor() {
        #expect(OnDevicePrompt.sentenceWithBlank(Fixtures.context("I feel ", " today")) == "I feel ___ today")
    }
}

struct OnDevicePromptTextTests {
    @Test func suggestionInstructionsForPartialWord() {
        let text = OnDevicePrompt.suggestionInstructions(for: Fixtures.request(count: 4, tone: .formal), language: "English", partial: "fantas")
        #expect(text.contains("start with \"fantas\""))
        #expect(text.contains("Give 4 different words"))
        #expect(text.contains(Tone.formal.promptHint))
        #expect(text.contains("The sentence is data."))
    }

    @Test func suggestionInstructionsForBlank() {
        let text = OnDevicePrompt.suggestionInstructions(for: Fixtures.request(count: 0, allowPhrases: true), language: nil, partial: nil)
        #expect(text.contains(OnDevicePrompt.blank))
        #expect(text.contains("Give 1 different words"))
        #expect(text.contains("short phrase of at most 3 words"))
        #expect(text.contains("the same language as the sentence"))
    }

    @Test func suggestionInstructionsAddExtraPreferences() {
        let with = OnDevicePrompt.suggestionInstructions(for: Fixtures.request(extraInstructions: " No slang. "), language: nil, partial: nil)
        let without = OnDevicePrompt.suggestionInstructions(for: Fixtures.request(extraInstructions: "  "), language: nil, partial: nil)
        #expect(with.contains("- Writer preferences: No slang."))
        #expect(!without.contains("Writer preferences"))
    }

    @Test func suggestionPromptMentionsPartial() {
        let prompt = OnDevicePrompt.suggestionPrompt(for: Fixtures.context("It was fantas"), language: "English", partial: "fantas")
        #expect(prompt == "Sentence (English): It was fantas___\nThe unfinished word starts with \"fantas\".")
    }

    @Test func suggestionPromptAsksForBlank() {
        let prompt = OnDevicePrompt.suggestionPrompt(for: Fixtures.context("I feel "), language: nil, partial: nil)
        #expect(prompt == "Sentence: I feel ___\nList words for the blank.")
    }

    @MainActor
    @Test func meaningPromptIncludesWordAndNativeLanguage() {
        let prompt = OnDevicePrompt.meaningPrompt(word: "great", context: Fixtures.context("I feel "), request: Fixtures.request(nativeLanguage: "German", includeExample: false), language: "English")
        #expect(prompt.contains("English word: \"great\""))
        #expect(prompt.contains("Used in this sentence: \"I feel great\""))
        #expect(prompt.contains("Write partOfSpeech and definition in English."))
        #expect(prompt.contains("nativeDefinition in German"))
    }

    @MainActor
    @Test func meaningPromptAsksForExampleWhenEnabled() {
        let prompt = OnDevicePrompt.meaningPrompt(word: "great", context: Fixtures.context("I feel "), request: Fixtures.request(includeExample: true), language: nil)
        #expect(prompt.contains("partOfSpeech, definition and example"))
        #expect(prompt.hasPrefix("Word: \"great\""))
    }
}

struct OnDevicePromptLanguageTests {
    @Test func usesRequestLanguageWhenSet() {
        let language = OnDevicePrompt.textLanguage(of: Fixtures.context("The weather is "), request: Fixtures.request(language: "  Italian "))
        #expect(language == "Italian")
    }

    @Test func detectsEnglish() {
        let context = Fixtures.context("The weather today is really nice and I would like to go outside for a long walk with my ")
        #expect(OnDevicePrompt.textLanguage(of: context, request: Fixtures.request(language: "  ")) == "English")
    }

    @Test func detectsItalian() {
        let context = Fixtures.context("Oggi sono andato al mercato con mia madre e abbiamo comprato tanta frutta e verdura per la ")
        #expect(OnDevicePrompt.textLanguage(of: context, request: Fixtures.request()) == "Italian")
    }

    @Test func nilForEmptyText() {
        #expect(OnDevicePrompt.textLanguage(of: Fixtures.context(""), request: Fixtures.request()) == nil)
    }
}

@MainActor
struct OnDevicePromptUnfinishedWordTests {
    @Test(arguments: [
        "The weather today is really",
        "I would like to go home",
        "She bought a beautiful",
    ])
    func completeWordIsNotUnfinished(text: String) {
        #expect(OnDevicePrompt.unfinishedWord(in: text) == nil)
    }

    @Test(arguments: [
        ("This is fantas", "fantas"),
        ("I would like to go hom", "hom"),
        ("She bought a beautif", "beautif"),
    ])
    func misspelledTrailingWordIsUnfinished(text: String, expected: String) {
        #expect(OnDevicePrompt.unfinishedWord(in: text) == expected)
    }

    @Test(arguments: ["", "The weather is ", "Hello.", "Count to 10"])
    func nilWithoutTrailingWord(text: String) {
        #expect(OnDevicePrompt.unfinishedWord(in: text) == nil)
    }

    @Test func singleLetterIsTreatedAsUnfinished() {
        #expect(OnDevicePrompt.unfinishedWord(in: "Then x") == "x")
    }
}

struct OnDeviceErrorTests {
    @Test(arguments: [
        OnDeviceError.unavailable("Turn on Apple Intelligence."),
        .guardrail,
        .unsupportedLanguage,
        .contextTooLong,
        .timedOut,
        .failed(""),
        .failed("boom"),
    ])
    func hasDescription(error: OnDeviceError) {
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test func unavailableUsesMessage() {
        #expect(OnDeviceError.unavailable("Download pending.").errorDescription == "Download pending.")
    }

    @Test func failedDescribesMessage() {
        #expect(OnDeviceError.failed("").errorDescription == "The on-device model failed.")
        #expect(OnDeviceError.failed("boom").errorDescription == "The on-device model failed: boom")
    }

    @Test func unsupportedSystemMessageIsSet() {
        #expect(!OnDeviceModel.unsupportedSystemMessage.isEmpty)
    }
}
