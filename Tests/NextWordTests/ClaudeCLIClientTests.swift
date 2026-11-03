import Foundation
import Testing
@testable import NextWord

struct ClaudeParseTests {
    @Test func readsStructuredOutput() throws {
        let stdout = Fixtures.json(["structured_output": ["words": ["alpha", "beta"]], "result": ""])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10) == ["alpha", "beta"])
    }

    @Test func structuredOutputIsCleanedAndCapped() throws {
        let stdout = Fixtures.json(["structured_output": ["words": ["1. Alpha", "alpha", "beta.", "gamma"]]])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 2) == ["Alpha", "beta"])
    }

    @Test func readsResultAsJSONString() throws {
        let stdout = Fixtures.json(["result": #"{"words": ["one", "two"]}"#])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10) == ["one", "two"])
    }

    @Test func readsResultAsFencedJSON() throws {
        let stdout = Fixtures.json(["result": "```json\n{\"words\": [\"one\", \"two\"]}\n```"])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10) == ["one", "two"])
    }

    @Test func readsResultAsJSONArrayString() throws {
        let stdout = Fixtures.json(["result": #"["one", "two"]"#])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10) == ["one", "two"])
    }

    @Test func fallsBackToNewlineAndCommaText() throws {
        let stdout = Fixtures.json(["result": "1. alpha\n2. beta, gamma\n"])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10) == ["alpha", "beta", "gamma"])
    }

    @Test func emptyStructuredWordsFallBackToResult() throws {
        let stdout = Fixtures.json(["structured_output": ["words": [String]()], "result": "alpha"])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10) == ["alpha"])
    }

    @Test func emptyWordsThrowInvalidOutput() {
        let stdout = Fixtures.json(["result": " , \n "])
        #expect {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10)
        } throws: { error in
            guard case .invalidOutput = error as? ClaudeCLIError else { return false }
            return true
        }
    }

    @Test func missingResultThrowsInvalidOutput() {
        let stdout = Fixtures.json(["type": "result"])
        #expect {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10)
        } throws: { error in
            guard case .invalidOutput = error as? ClaudeCLIError else { return false }
            return true
        }
    }

    @Test func isErrorThrowsCLIErrorWithMessage() {
        let stdout = Fixtures.json(["is_error": true, "result": "Rate limit reached"])
        #expect(throws: ClaudeCLIError.cliError("Rate limit reached")) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10)
        }
    }

    @Test func isErrorFallsBackToSubtype() {
        let stdout = Fixtures.json(["is_error": true, "result": "  ", "subtype": "error_max_turns"])
        #expect(throws: ClaudeCLIError.cliError("error_max_turns")) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10)
        }
    }

    @Test func isErrorWithoutAnyMessageIsUnknown() {
        let stdout = Fixtures.json(["is_error": true])
        #expect(throws: ClaudeCLIError.cliError("unknown error")) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10)
        }
    }

    @Test(arguments: [
        "Invalid API key · Please run /login",
        "Not logged in",
        "OAuth token has expired",
        "API Error: 401 Unauthorized",
    ])
    func isErrorWithAuthTextThrowsNotLoggedIn(message: String) {
        let stdout = Fixtures.json(["is_error": true, "result": message])
        #expect(throws: ClaudeCLIError.notLoggedIn) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10)
        }
    }

    @Test func isErrorWithUnrelatedLogInSubstringIsNotAuthFailure() {
        let stdout = Fixtures.json(["is_error": true, "result": "Could not open the catalog in time"])
        #expect(throws: ClaudeCLIError.cliError("Could not open the catalog in time")) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout), count: 10)
        }
    }

    @Test func nonZeroExitWithoutJSONThrowsProcessFailedWithStderr() {
        let result = Fixtures.result(stdout: "", stderr: "segmentation fault\n", status: 139)
        #expect(throws: ClaudeCLIError.processFailed(code: 139, stderr: "segmentation fault")) {
            try ClaudeCLIClient.parse(result, count: 10)
        }
    }

    @Test func nonZeroExitWithoutStderrUsesStdout() {
        let result = Fixtures.result(stdout: "boom", stderr: "", status: 2)
        #expect(throws: ClaudeCLIError.processFailed(code: 2, stderr: "boom")) {
            try ClaudeCLIClient.parse(result, count: 10)
        }
    }

    @Test func nonZeroExitWithAuthTextThrowsNotLoggedIn() {
        let result = Fixtures.result(stdout: "", stderr: "Error: not logged in. Please run /login", status: 1)
        #expect(throws: ClaudeCLIError.notLoggedIn) {
            try ClaudeCLIClient.parse(result, count: 10)
        }
    }

    @Test func zeroExitWithEmptyOutputThrowsInvalidOutput() {
        #expect(throws: ClaudeCLIError.invalidOutput("empty output")) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: "  \n"), count: 10)
        }
    }

    @Test func zeroExitWithPlainTextThrowsInvalidOutput() {
        #expect(throws: ClaudeCLIError.invalidOutput("hello there")) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: "hello there"), count: 10)
        }
    }

    @Test func timedOutWinsOverEverything() {
        let stdout = Fixtures.json(["structured_output": ["words": ["alpha"]]])
        #expect(throws: ClaudeCLIError.timedOut) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout, status: 15, timedOut: true), count: 10)
        }
    }

    @Test func validJSONWinsOverNonZeroExit() throws {
        let stdout = Fixtures.json(["structured_output": ["words": ["alpha"]]])
        #expect(try ClaudeCLIClient.parse(Fixtures.result(stdout: stdout, status: 1), count: 10) == ["alpha"])
    }

    @Test func longOutputIsSnippedInError() {
        let long = String(repeating: "x", count: 500)
        #expect(throws: ClaudeCLIError.invalidOutput(String(repeating: "x", count: 300) + "…")) {
            try ClaudeCLIClient.parse(Fixtures.result(stdout: long), count: 10)
        }
    }
}

struct ClaudeMeaningTests {
    private let request = Fixtures.request(nativeLanguage: "Italian", includeExample: true)

    @Test func parseMeaningReadsStructuredOutput() throws {
        let stdout = Fixtures.json(["structured_output": ["definition": "A greeting.", "nativeTranslation": "ciao"]])
        let meaning = try ClaudeCLIClient.parseMeaning(Fixtures.result(stdout: stdout), word: "hello", request: request)
        #expect(meaning.definition == "A greeting.")
        #expect(meaning.nativeTranslation == "ciao")
    }

    @Test func parseMeaningReadsResultJSONString() throws {
        let stdout = Fixtures.json(["result": #"{"definition": "A greeting.", "nativeDefinition": "Un saluto."}"#])
        let meaning = try ClaudeCLIClient.parseMeaning(Fixtures.result(stdout: stdout), word: "hello", request: request)
        #expect(meaning.nativeDefinition == "Un saluto.")
    }

    @Test func parseMeaningWithoutDefinitionThrowsInvalidOutput() {
        let stdout = Fixtures.json(["result": "I don't know this word."])
        #expect(throws: ClaudeCLIError.invalidOutput("I don't know this word.")) {
            try ClaudeCLIClient.parseMeaning(Fixtures.result(stdout: stdout), word: "hello", request: request)
        }
    }
}

struct ClaudeArgumentsTests {
    private let arguments = ClaudeCLIClient.arguments(system: "SYSTEM", model: "sonnet", schema: "SCHEMA")

    private func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @Test(arguments: [
        ("--model", "sonnet"),
        ("--system-prompt", "SYSTEM"),
        ("--json-schema", "SCHEMA"),
        ("--output-format", "json"),
        ("--effort", "low"),
        ("--tools", ""),
        ("--setting-sources", ""),
    ])
    func flagHasValue(flag: String, expected: String) {
        #expect(value(after: flag) == expected)
    }

    @Test(arguments: ["-p", "--strict-mcp-config", "--no-session-persistence", "--disable-slash-commands"])
    func containsSwitch(flag: String) {
        #expect(arguments.contains(flag))
    }

    @Test func promptIsNotAnArgument() {
        #expect(value(after: "-p") == "--model")
        #expect(!arguments.contains { $0.contains("USER") })
    }

    @Test func neverUsesBare() {
        #expect(!arguments.contains("--bare"))
    }

    @Test func defaultSchemaIsWordsSchema() {
        let defaults = ClaudeCLIClient.arguments(system: "S", model: "haiku")
        let index = defaults.firstIndex(of: "--json-schema")
        #expect(index.map { defaults[$0 + 1] } == ClaudeCLIClient.wordsSchema)
    }

    @Test func wordsSchemaIsValidJSON() throws {
        let object = try #require(EngineResponse.jsonObject(in: ClaudeCLIClient.wordsSchema))
        #expect(object["required"] as? [String] == ["words"])
    }
}

struct ClaudeMeaningSchemaTests {
    private func schema(includeExample: Bool) throws -> (properties: [String: Any], required: [String]) {
        let object = try #require(EngineResponse.jsonObject(in: ClaudeCLIClient.meaningSchema(includeExample: includeExample)))
        #expect(object["type"] as? String == "object")
        let properties = try #require(object["properties"] as? [String: Any])
        let required = try #require(object["required"] as? [String])
        return (properties, required)
    }

    @Test func includesExampleWhenEnabled() throws {
        let (properties, required) = try schema(includeExample: true)
        #expect(required == ["textLanguage", "partOfSpeech", "definition", "example", "nativeTranslation", "nativeDefinition"])
        #expect(Set(properties.keys) == Set(required))
    }

    @Test func omitsExampleWhenDisabled() throws {
        let (properties, required) = try schema(includeExample: false)
        #expect(required == ["textLanguage", "partOfSpeech", "definition", "nativeTranslation", "nativeDefinition"])
        #expect(properties["example"] == nil)
    }

    @Test(arguments: [true, false])
    func everyPropertyIsAString(includeExample: Bool) throws {
        let (properties, _) = try schema(includeExample: includeExample)
        for (_, value) in properties {
            let property = try #require(value as? [String: Any])
            #expect(property["type"] as? String == "string")
        }
    }
}

struct ClaudeCLIErrorTests {
    @Test(arguments: [
        ClaudeCLIError.notFound,
        .timedOut,
        .processFailed(code: 1, stderr: ""),
        .processFailed(code: 1, stderr: "boom"),
        .notLoggedIn,
        .invalidOutput("x"),
        .cliError("x"),
    ])
    func hasDescription(error: ClaudeCLIError) {
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test func notFoundPointsToEnginesTab() {
        #expect(ClaudeCLIError.notFound.errorDescription?.contains("Settings → Engines") == true)
    }

    @Test func processFailedMentionsStderr() {
        #expect(ClaudeCLIError.processFailed(code: 3, stderr: "boom").errorDescription == "Claude CLI failed (exit code 3): boom")
        #expect(ClaudeCLIError.processFailed(code: 3, stderr: "").errorDescription == "Claude CLI failed (exit code 3).")
    }
}
