import Testing
@testable import NextWord

private func context(_ before: String, _ after: String = "", selection: Int = 0) -> TextContext {
    TextContext(appName: "Test", bundleID: nil, windowTitle: nil, textBeforeCursor: before, textAfterCursor: after, caretRect: nil, selectionLength: selection)
}

@MainActor
struct TextInserterComposedTextTests {
    @Test func nilContextAddsOnlyTrailingSpace() {
        #expect(TextInserter.composedText(for: "hello", context: nil) == "hello ")
    }

    @Test func emptyContextAddsOnlyTrailingSpace() {
        #expect(TextInserter.composedText(for: "hello", context: context("")) == "hello ")
    }

    @Test(arguments: ["Hello ", "Hello\n", "Hello\t"])
    func noLeadingSpaceAfterWhitespace(before: String) {
        #expect(TextInserter.composedText(for: "world", context: context(before)) == "world ")
    }

    @Test(arguments: ["Hello", "Hello,", "Hello.", "Done!", "Really?", "end)"])
    func leadingSpaceAfterWordOrPunctuation(before: String) {
        #expect(TextInserter.composedText(for: "world", context: context(before)) == " world ")
    }

    @Test(arguments: ["(", "[", "{", "<", "\"", "'", "“", "‘", "«", "¿", "¡", "/", "@", "#"])
    func noLeadingSpaceAfterOpeningCharacter(opening: String) {
        #expect(TextInserter.composedText(for: "word", context: context("Say " + opening)) == "word ")
    }

    @Test(arguments: [".", ",", ";", ":", "!", "?", ")", "]", "}", "…", "'s", "’s"])
    func noLeadingSpaceBeforePunctuationWord(word: String) {
        #expect(TextInserter.composedText(for: word, context: context("Hello")) == word + " ")
    }

    @Test(arguments: [" more", "\nmore", "\tmore"])
    func noTrailingSpaceWhenTextAfterStartsWithWhitespace(after: String) {
        #expect(TextInserter.composedText(for: "world", context: context("Hello ", after)) == "world")
    }

    @Test func trailingSpaceWhenTextAfterStartsWithLetter() {
        #expect(TextInserter.composedText(for: "big", context: context("A ", "dog")) == "big ")
    }

    @Test func noTrailingSpaceBeforePunctuationAfterCursor() {
        #expect(TextInserter.composedText(for: "world", context: context("Hello ", ".")) == "world")
    }

    @Test(arguments: [".", ",", ";", ":", "!", "?", ")", "]", "}", "…", "'", "’", "\""])
    func noTrailingSpaceBeforeAnyPunctuationAfterCursor(after: String) {
        #expect(TextInserter.composedText(for: "world", context: context("Hello ", after + " more")) == "world")
    }

    @Test func trailingSpaceBeforeOpeningCharacterAfterCursor() {
        #expect(TextInserter.composedText(for: "world", context: context("Hello ", "(x)")) == "world ")
    }

    @Test func completesPartialWordWithoutLeadingSpace() {
        #expect(TextInserter.composedText(for: "fantastic", context: context("This is fantas")) == "fantastic ")
    }

    @Test func completionKeepsCapitalizationOfPartial() {
        #expect(TextInserter.composedText(for: "fantastic", context: context("Fantas")) == "Fantastic ")
    }

    @Test func completionKeepsCapitalizationAfterSentence() {
        #expect(TextInserter.composedText(for: "wonderful", context: context("It was fine. Wond")) == "Wonderful ")
    }

    @Test func completionHandlesAccents() {
        #expect(TextInserter.composedText(for: "perché", context: context("Non so perch")) == "perché ")
    }

    @Test func completionRespectsTextAfterCursor() {
        #expect(TextInserter.composedText(for: "fantastic", context: context("fantas", " day")) == "fantastic")
    }

    @Test func completionBeforePunctuationHasNoTrailingSpace() {
        #expect(TextInserter.composedText(for: "fantastic", context: context("This is fantas", ".")) == "fantastic")
    }

    @Test func wordAfterContractionGetsLeadingSpace() {
        #expect(TextInserter.composedText(for: "think", context: context("I don't")) == " think ")
        #expect(TextInserter.composedText(for: "making", context: context("I'm")) == " making ")
    }

    @Test func replacesUnfinishedTokenWithDifferentWord() {
        #expect(TextInserter.composedText(for: "imaginative", context: context("This is fantas")) == "imaginative ")
    }

    @Test func replacementKeepsCapitalizationOfUnfinishedToken() {
        #expect(TextInserter.composedText(for: "imaginative", context: context("This is Fantas")) == "Imaginative ")
    }

    @Test func completesHyphenatedToken() {
        #expect(TextInserter.composedText(for: "well-known", context: context("It is well-kno")) == "well-known ")
    }

    @Test func completionInsideSelection() {
        #expect(TextInserter.composedText(for: "world", context: context("Hello wor", "", selection: 2)) == "world ")
    }

    @Test func emojiBeforeCursorGetsLeadingSpace() {
        #expect(TextInserter.composedText(for: "day", context: context("Nice 😀")) == " day ")
    }

    @Test func emojiBeforeCursorIsNotAPartialWord() {
        #expect(TextInserter.completedPartialWord(for: "day", context: context("Nice 😀")) == nil)
    }
}

@MainActor
struct TextInserterCompletedPartialWordTests {
    @Test func nilContextHasNoPartial() {
        #expect(TextInserter.completedPartialWord(for: "hello", context: nil) == nil)
    }

    @Test func emptyContextHasNoPartial() {
        #expect(TextInserter.completedPartialWord(for: "hello", context: context("")) == nil)
    }

    @Test func returnsPartialThatTheWordCompletes() {
        #expect(TextInserter.completedPartialWord(for: "fantastic", context: context("This is fantas")) == "fantas")
    }

    @Test func matchesCaseInsensitively() {
        #expect(TextInserter.completedPartialWord(for: "fantastic", context: context("FANTAS")) == "FANTAS")
    }

    @Test func returnsPartialWithAccentedCompletion() {
        #expect(TextInserter.completedPartialWord(for: "perché", context: context("perch")) == "perch")
    }

    @Test func returnsPartialWithAccentedLetters() {
        #expect(TextInserter.completedPartialWord(for: "café", context: context("un caf")) == "caf")
        #expect(TextInserter.completedPartialWord(for: "élève", context: context("un élè")) == "élè")
    }

    @Test func nilWhenWordDoesNotStartWithPartial() {
        #expect(TextInserter.completedPartialWord(for: "world", context: context("Hello")) == nil)
    }

    @Test func nilWhenWordEqualsPartial() {
        #expect(TextInserter.completedPartialWord(for: "really", context: context("It is really")) == nil)
    }

    @Test func nilWhenWordIsShorterThanCompleteWord() {
        #expect(TextInserter.completedPartialWord(for: "fan", context: context("It is fantastic")) == nil)
    }

    @Test func unfinishedTokenIsReplacedByShorterWord() {
        #expect(TextInserter.completedPartialWord(for: "fan", context: context("This is fantas")) == "fantas")
    }

    @Test func unfinishedTokenIsReplacedByDifferentWord() {
        #expect(TextInserter.completedPartialWord(for: "imaginative", context: context("This is fantas")) == "fantas")
    }

    @Test func singleLetterWordIsNotReplacedByDifferentWord() {
        #expect(TextInserter.completedPartialWord(for: "think", context: context("Yes, I")) == nil)
        #expect(TextInserter.composedText(for: "think", context: context("Yes, I")) == " think ")
    }

    @Test func punctuationWordNeverReplacesToken() {
        #expect(TextInserter.completedPartialWord(for: "'s", context: context("This is fantas")) == nil)
    }

    @Test func wholeHyphenatedTokenIsThePartial() {
        #expect(TextInserter.completedPartialWord(for: "well-known", context: context("It is well-kno")) == "well-kno")
    }

    @Test(arguments: ["fantas ", "fantas.", "fantas,", "(", ""])
    func nilWhenTextDoesNotEndInLetters(before: String) {
        #expect(TextInserter.completedPartialWord(for: "fantastic", context: context(before)) == nil)
    }

    @Test func includesTrailingDigits() {
        #expect(TextInserter.completedPartialWord(for: "mp3player", context: context("my mp3")) == "mp3")
    }

    @Test func doesNotTreatLettersAfterApostropheAsPartial() {
        #expect(TextInserter.completedPartialWord(for: "think", context: context("I don't")) == nil)
        #expect(TextInserter.composedText(for: "think", context: context("I don't")) == " think ")
    }

    @Test func contractionIsNotReplaced() {
        #expect(TextInserter.completedPartialWord(for: "making", context: context("I'm")) == nil)
    }

    @Test func contractionIsCompletedAsWholeToken() {
        #expect(TextInserter.completedPartialWord(for: "doesn't", context: context("It does")) == "does")
        #expect(TextInserter.completedPartialWord(for: "don't", context: context("I don")) == "don")
    }
}

@MainActor
struct TextInserterBackspaceCountTests {
    @Test func noBackspacesWithoutContext() {
        #expect(TextInserter.backspaceCount(for: "hello", context: nil) == 0)
    }

    @Test func noBackspacesForNextWord() {
        #expect(TextInserter.backspaceCount(for: "world", context: context("Hello ")) == 0)
    }

    @Test func deletesPartialForCompletion() {
        #expect(TextInserter.backspaceCount(for: "fantastic", context: context("This is fantas")) == 6)
    }

    @Test func deletesUnfinishedTokenForDifferentWord() {
        #expect(TextInserter.backspaceCount(for: "imaginative", context: context("This is fantas")) == 6)
    }

    @Test func deletesWholeHyphenatedToken() {
        #expect(TextInserter.backspaceCount(for: "well-known", context: context("It is well-kno")) == 8)
    }

    @Test func doesNotDeleteAfterContraction() {
        #expect(TextInserter.backspaceCount(for: "think", context: context("I don't")) == 0)
        #expect(TextInserter.backspaceCount(for: "making", context: context("I'm")) == 0)
    }

    @Test func extraBackspaceClearsSelectionBeforePartial() {
        #expect(TextInserter.backspaceCount(for: "world", context: context("Hello wor", "", selection: 2)) == 4)
    }

    @Test func noBackspaceForSelectionWithoutPartial() {
        #expect(TextInserter.backspaceCount(for: "world", context: context("Hello ", "", selection: 3)) == 0)
    }

    @Test func countsGraphemesNotCodeUnits() {
        #expect(TextInserter.backspaceCount(for: "perché", context: context("Non so perch")) == 5)
        #expect(TextInserter.backspaceCount(for: "élève", context: context("un élè")) == 3)
    }
}
