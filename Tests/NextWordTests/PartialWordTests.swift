import Testing
@testable import NextWord

struct PartialWordTrailingTests {
    @Test(arguments: [
        ("I think this is a fantas", "fantas"),
        ("I don't", "don't"),
        ("I don'", "don'"),
        ("it’s", "it’s"),
        ("a well-kno", "well-kno"),
        ("-abc", "abc"),
        ("perch", "perch"),
        ("perché", "perché"),
        ("route 66", "66"),
    ])
    func returnsTrailingToken(text: String, expected: String) {
        #expect(PartialWord.trailing(in: text) == expected)
    }

    @Test(arguments: ["", "Hello ", "Hello,", "said '", "end.", "dash -", "emoji 😀", "she said 'quoted'"])
    func returnsNilWithoutTrailingWord(text: String) {
        #expect(PartialWord.trailing(in: text) == nil)
    }
}

@MainActor
struct PartialWordUnfinishedTests {
    @Test func singleLetterIsUnfinished() {
        #expect(PartialWord.isUnfinished("x", context: "Then x"))
    }

    @Test func correctlySpelledWordIsFinished() {
        #expect(!PartialWord.isUnfinished("really", context: "The release went really"))
    }

    @Test func fragmentIsUnfinished() {
        #expect(PartialWord.isUnfinished("fantas", context: "This movie was absolutely fantas"))
    }
}
