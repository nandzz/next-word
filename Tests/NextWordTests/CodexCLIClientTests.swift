import Foundation
import Testing
@testable import NextWord

struct CodexJSONObjectTests {
    @Test func parsesPlainObject() throws {
        let object = try #require(EngineResponse.jsonObject(in: #"{"words": ["a", "b"]}"#))
        #expect(object["words"] as? [String] == ["a", "b"])
    }

    @Test func parsesObjectSurroundedByProse() throws {
        let text = "Sure! Here is the answer:\n{\"words\": [\"alpha\"]}\nLet me know if you need more."
        let object = try #require(EngineResponse.jsonObject(in: text))
        #expect(object["words"] as? [String] == ["alpha"])
    }

    @Test func parsesFencedObject() throws {
        let text = "```json\n{\"definition\": \"A greeting.\"}\n```"
        let object = try #require(EngineResponse.jsonObject(in: text))
        #expect(object["definition"] as? String == "A greeting.")
    }

    @Test func parsesNestedBraces() throws {
        let text = #"x {"outer": {"inner": {"v": "{curly}"}}} y"#
        let object = try #require(EngineResponse.jsonObject(in: text))
        let outer = try #require(object["outer"] as? [String: Any])
        let inner = try #require(outer["inner"] as? [String: Any])
        #expect(inner["v"] as? String == "{curly}")
    }

    @Test func parsesUnicodeValues() throws {
        let object = try #require(EngineResponse.jsonObject(in: #"{"words": ["perché", "😀"]}"#))
        #expect(object["words"] as? [String] == ["perché", "😀"])
    }

    @Test(arguments: ["", "no json here", "{not json}", "} {", "{\"a\": 1", "[\"a\"]", "{\"a\": 1} and {\"b\": 2}"])
    func nilForInvalidJSON(text: String) {
        #expect(EngineResponse.jsonObject(in: text) == nil)
    }
}

struct CodexArgumentsTests {
    private let directory = URL(fileURLWithPath: "/tmp/nextword-codex-test", isDirectory: true)
    private let output = URL(fileURLWithPath: "/tmp/nextword-codex-test/answer.txt")

    private func arguments(model: String? = nil) -> [String] {
        CodexCLIClient.arguments(workingDirectory: directory, outputFile: output, model: model)
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @Test func startsWithExecAndReadsPromptFromStdin() {
        let arguments = arguments()
        #expect(arguments.first == "exec")
        #expect(arguments.last == "-")
    }

    @Test(arguments: [
        ("--sandbox", "read-only"),
        ("--color", "never"),
        ("--cd", "/tmp/nextword-codex-test"),
        ("--output-last-message", "/tmp/nextword-codex-test/answer.txt"),
    ])
    func flagHasValue(flag: String, expected: String) {
        #expect(value(after: flag, in: arguments()) == expected)
    }

    @Test(arguments: ["--skip-git-repo-check", "--ephemeral", "--ignore-user-config"])
    func containsSwitch(flag: String) {
        #expect(arguments().contains(flag))
    }

    @Test(arguments: [
        #"model_reasoning_effort="low""#,
        #"web_search="disabled""#,
        "features.shell_tool=false",
        "features.view_image=false",
        #"history.persistence="none""#,
    ])
    func containsConfigOverride(override: String) {
        let arguments = arguments()
        let overrides = arguments.indices.dropLast().filter { arguments[$0] == "-c" }.map { arguments[$0 + 1] }
        #expect(overrides.contains(override))
    }

    @Test func addsModelOnlyWhenSet() {
        #expect(value(after: "--model", in: arguments(model: "gpt-5")) == "gpt-5")
        #expect(!arguments().contains("--model"))
        #expect(!arguments(model: "").contains("--model"))
    }
}

struct CodexParseTests {
    @Test func readsAnswerObject() throws {
        let object = try CodexCLIClient.parse(Fixtures.result(stdout: ""), answer: #"{"words": ["alpha"]}"#)
        #expect(object["words"] as? [String] == ["alpha"])
    }

    @Test func timedOutWins() {
        #expect(throws: CodexCLIError.timedOut) {
            try CodexCLIClient.parse(Fixtures.result(stdout: "", status: 15, timedOut: true), answer: #"{"words": []}"#)
        }
    }

    @Test func nonZeroExitWithLoginTextIsNotLoggedIn() {
        #expect(throws: CodexCLIError.notLoggedIn) {
            try CodexCLIClient.parse(Fixtures.result(stdout: "", stderr: "Please run codex login", status: 1), answer: "")
        }
    }

    @Test func nonZeroExitWithUnrelatedTextIsProcessFailed() {
        #expect(throws: CodexCLIError.processFailed(code: 2, message: "Could not open the catalog in time")) {
            try CodexCLIClient.parse(Fixtures.result(stdout: "", stderr: "Could not open the catalog in time", status: 2), answer: "")
        }
    }

    @Test func nonZeroExitWithoutStderrUsesStdout() {
        #expect(throws: CodexCLIError.processFailed(code: 3, message: "boom")) {
            try CodexCLIClient.parse(Fixtures.result(stdout: "boom", stderr: " \n", status: 3), answer: "")
        }
    }

    @Test func answerWithoutJSONIsInvalidOutput() {
        #expect(throws: CodexCLIError.invalidOutput("no json")) {
            try CodexCLIClient.parse(Fixtures.result(stdout: ""), answer: "no json")
        }
    }
}

struct CodexCLIErrorTests {
    @Test(arguments: [
        CodexCLIError.notFound,
        .timedOut,
        .notLoggedIn,
        .processFailed(code: 1, message: ""),
        .processFailed(code: 1, message: "boom"),
        .invalidOutput(""),
        .invalidOutput("bad"),
    ])
    func hasDescription(error: CodexCLIError) {
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test func processFailedIncludesCodeAndMessage() {
        let description = CodexCLIError.processFailed(code: 7, message: "boom").errorDescription ?? ""
        #expect(description.contains("7"))
        #expect(description.contains("boom"))
    }

    @Test func invalidOutputIncludesMessage() {
        #expect(CodexCLIError.invalidOutput("No words.").errorDescription?.contains("No words.") == true)
    }
}
