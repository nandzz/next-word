import Foundation
import Testing
@testable import NextWord

struct EngineCleanWordTests {
    @Test(arguments: [
        ("word", "word"),
        ("  word  ", "word"),
        ("1. word", "word"),
        ("1.word", "word"),
        ("12) word", "word"),
        ("3: word", "word"),
        ("4 - word", "word"),
        ("- word", "word"),
        ("* word", "word"),
        ("• word", "word"),
        ("– word", "word"),
        ("— word", "word"),
        ("\"word\"", "word"),
        ("'word'", "word"),
        ("`word`", "word"),
        ("“word”", "word"),
        ("‘word’", "word"),
        ("«word»", "word"),
        ("„word“", "word"),
        ("word.", "word"),
        ("word,", "word"),
        ("word;", "word"),
        ("word!", "word"),
        ("word?", "word"),
        ("word…", "word"),
        ("(word)", "word"),
        ("[word]", "word"),
        ("1. \"word.\"", "word"),
        ("\"word\".", "word"),
        ("don't", "don't"),
        ("well-known", "well-known"),
        ("very   good", "very good"),
        ("ice\tcream", "ice cream"),
        ("perché", "perché"),
    ])
    func cleansDecorations(raw: String, expected: String) {
        #expect(EngineResponse.cleanWord(raw) == expected)
    }

    @Test(arguments: ["", "   ", "\"\"", "...", "-", "•", "1.", "()"])
    func emptyWhenNothingRemains(raw: String) {
        #expect(EngineResponse.cleanWord(raw) == "")
    }
}

struct EngineCleanTests {
    @Test func cleansEachWord() {
        #expect(EngineResponse.clean(["1. alpha", "2. beta"], count: 10) == ["alpha", "beta"])
    }

    @Test func dropsEmptyEntries() {
        #expect(EngineResponse.clean(["", "  ", "alpha", "..."], count: 10) == ["alpha"])
    }

    @Test func dedupesCaseInsensitivelyKeepingFirst() {
        #expect(EngineResponse.clean(["Great", "great", "GREAT.", "good"], count: 10) == ["Great", "good"])
    }

    @Test func capsAtCount() {
        #expect(EngineResponse.clean(["a", "b", "c", "d"], count: 2) == ["a", "b"])
    }

    @Test(arguments: [0, -1])
    func countBelowOneKeepsOneWord(count: Int) {
        #expect(EngineResponse.clean(["a", "b"], count: count) == ["a"])
    }

    @Test func emptyInputGivesEmptyOutput() {
        #expect(EngineResponse.clean([], count: 5).isEmpty)
    }

    @Test func duplicatesDoNotUseUpCount() {
        #expect(EngineResponse.clean(["a", "A", "a.", "b"], count: 2) == ["a", "b"])
    }
}

struct EngineJSONObjectTests {
    @Test func parsesPlainObject() throws {
        let object = try #require(EngineResponse.jsonObject(in: #"{"a": 1}"#))
        #expect(object["a"] as? Int == 1)
    }

    @Test func parsesLastJSONLineAfterLogs() throws {
        let text = "warning: something\n{\"result\": \"ok\"}"
        let object = try #require(EngineResponse.jsonObject(in: text))
        #expect(object["result"] as? String == "ok")
    }

    @Test func parsesObjectSurroundedByProse() throws {
        let object = try #require(EngineResponse.jsonObject(in: #"Here you go: {"words": ["a", "b"]} Enjoy."#))
        #expect(object["words"] as? [String] == ["a", "b"])
    }

    @Test func parsesNestedObjects() throws {
        let object = try #require(EngineResponse.jsonObject(in: #"x {"outer": {"inner": {"v": 2}}} y"#))
        let outer = try #require(object["outer"] as? [String: Any])
        let inner = try #require(outer["inner"] as? [String: Any])
        #expect(inner["v"] as? Int == 2)
    }

    @Test(arguments: ["", "plain text", "[1, 2]", "{not json}", "} {", "{\"a\": "])
    func nilForNonObjects(text: String) {
        #expect(EngineResponse.jsonObject(in: text) == nil)
    }
}


struct EngineMakeMeaningTests {
    private let request = Fixtures.request(nativeLanguage: "Italian", includeExample: true)

    @Test func buildsMeaningFromAllFields() throws {
        let fields: [String: Any] = [
            "partOfSpeech": " noun ",
            "definition": " A happy accident. ",
            "example": "Meeting her was serendipity.",
            "nativeTranslation": "\"serendipità.\"",
            "nativeDefinition": "Una scoperta felice.",
        ]
        let meaning = try #require(EngineResponse.makeMeaning(from: fields, word: "serendipity", request: request))
        #expect(meaning == WordMeaning(
            word: "serendipity",
            partOfSpeech: "noun",
            definition: "A happy accident.",
            example: "Meeting her was serendipity.",
            nativeLanguage: "Italian",
            nativeTranslation: "serendipità",
            nativeDefinition: "Una scoperta felice."
        ))
    }

    @Test(arguments: [nil, "", "   "] as [String?])
    func nilWithoutDefinition(definition: String?) {
        var fields: [String: Any] = ["nativeTranslation": "ciao"]
        if let definition { fields["definition"] = definition }
        #expect(EngineResponse.makeMeaning(from: fields, word: "hello", request: request) == nil)
    }

    @Test func nonStringDefinitionIsIgnored() {
        #expect(EngineResponse.makeMeaning(from: ["definition": 42], word: "hello", request: request) == nil)
    }

    @Test func missingOptionalFieldsUseFallbacks() throws {
        let meaning = try #require(EngineResponse.makeMeaning(from: ["definition": "A greeting."], word: "hello", request: request))
        #expect(meaning.partOfSpeech == nil)
        #expect(meaning.example == nil)
        #expect(meaning.nativeTranslation == "hello")
        #expect(meaning.nativeDefinition == "A greeting.")
        #expect(meaning.nativeLanguage == "Italian")
    }

    @Test(arguments: ["", "  ", "\"\"", "..."])
    func emptyTranslationFallsBackToWord(translation: String) throws {
        let fields: [String: Any] = ["definition": "A greeting.", "nativeTranslation": translation]
        let meaning = try #require(EngineResponse.makeMeaning(from: fields, word: "hello", request: request))
        #expect(meaning.nativeTranslation == "hello")
    }

    @Test func translationWithSynonymIsKept() throws {
        let fields: [String: Any] = ["definition": "Felice.", "nativeTranslation": "felice, contento"]
        let meaning = try #require(EngineResponse.makeMeaning(from: fields, word: "felice", request: request))
        #expect(meaning.nativeTranslation == "felice, contento")
    }

    @Test func exampleIsDroppedWhenDisabled() throws {
        let fields: [String: Any] = ["definition": "A greeting.", "example": "Hello there."]
        let meaning = try #require(EngineResponse.makeMeaning(from: fields, word: "hello", request: Fixtures.request(includeExample: false)))
        #expect(meaning.example == nil)
    }
}

struct EngineAuthFailureTests {
    @Test(arguments: [
        "Invalid API key · Please run /login",
        "Error: not logged in.",
        "Please log in first",
        "LOGIN required",
        "Authentication failed",
        "API Error: 401 Unauthorized",
        "OAuth token has expired",
        "status=401",
    ])
    func detectsAuthFailure(text: String) {
        #expect(EngineResponse.looksLikeAuthFailure(text))
    }

    @Test(arguments: [
        "Could not open the catalog in time",
        "Read the blog in full",
        "Error code 4012",
        "Port 14010 is busy",
        "loginless mode",
        "Rate limit reached",
        "",
    ])
    func ignoresMarkersInsideOtherWords(text: String) {
        #expect(!EngineResponse.looksLikeAuthFailure(text))
    }

    @Test func extraMarkersAreMatched() {
        #expect(EngineResponse.looksLikeAuthFailure("Run codex login first", extraMarkers: ["codex login"]))
        #expect(!EngineResponse.looksLikeAuthFailure("Run codex first", extraMarkers: ["codex login"]))
    }
}

struct EngineSnippetTests {
    @Test func keepsShortText() {
        #expect(EngineResponse.snippet("  short \n") == "short")
    }

    @Test func cutsLongText() {
        #expect(EngineResponse.snippet(String(repeating: "x", count: 301)) == String(repeating: "x", count: 300) + "…")
    }
}
