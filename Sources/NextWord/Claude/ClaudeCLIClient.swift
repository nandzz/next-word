import Foundation

enum ClaudeCLIError: LocalizedError, Equatable {
    case notFound
    case timedOut
    case processFailed(code: Int32, stderr: String)
    case notLoggedIn
    case invalidOutput(String)
    case cliError(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            "Claude CLI not found. Set its path in Settings → Engines."
        case .timedOut:
            "Claude took too long to answer. Try again, pick a faster model, or raise the timeout in Settings."
        case let .processFailed(code, stderr):
            stderr.isEmpty ? "Claude CLI failed (exit code \(code))." : "Claude CLI failed (exit code \(code)): \(stderr)"
        case .notLoggedIn:
            "Claude CLI is not logged in. Run `claude` in Terminal once and log in."
        case let .invalidOutput(detail):
            "Claude returned an answer NextWord could not read: \(detail)"
        case let .cliError(message):
            "Claude CLI error: \(message)"
        }
    }
}

final class ClaudeCLIClient: SuggestionProviding {
    static let wordsSchema = #"{"type":"object","properties":{"words":{"type":"array","items":{"type":"string"}}},"required":["words"]}"#

    init() {}

    func suggestions(for context: TextContext, request: SuggestionRequest) async throws -> [String] {
        let result = try await run(
            system: PromptBuilder.systemPrompt(for: request),
            user: PromptBuilder.userPrompt(for: context, request: request),
            schema: Self.wordsSchema,
            request: request
        )
        return try Self.parse(result, count: request.count)
    }

    func meaning(of word: String, in context: TextContext, request: SuggestionRequest) async throws -> WordMeaning {
        let result = try await run(
            system: PromptBuilder.meaningSystemPrompt(for: request),
            user: PromptBuilder.meaningUserPrompt(word: word, context: context, request: request),
            schema: Self.meaningSchema(includeExample: request.includeExample),
            request: request
        )
        return try Self.parseMeaning(result, word: word, request: request)
    }

    private func run(system: String, user: String, schema: String, request: SuggestionRequest) async throws -> ProcessResult {
        let customPath = request.claudePath
        guard let executable = await Task.detached(operation: { ClaudeCLILocator.resolve(customPath: customPath) }).value else {
            throw ClaudeCLIError.notFound
        }
        return try await ProcessRunner.run(
            executable: executable,
            arguments: Self.arguments(system: system, model: request.model, schema: schema),
            environment: ClaudeCLILocator.environment(for: executable),
            currentDirectory: FileManager.default.temporaryDirectory,
            input: Data(user.utf8),
            timeout: request.timeout > 0 ? request.timeout : 30
        )
    }

    func testConnection(request: SuggestionRequest) async throws -> (latency: TimeInterval, sample: [String]) {
        let context = TextContext(
            appName: "NextWord",
            bundleID: nil,
            windowTitle: nil,
            textBeforeCursor: "The weather today is really ",
            textAfterCursor: "",
            caretRect: nil
        )
        var testRequest = request
        testRequest.count = min(max(request.count, 1), 5)
        let start = Date()
        let sample = try await suggestions(for: context, request: testRequest)
        return (Date().timeIntervalSince(start), sample)
    }

    static func meaningSchema(includeExample: Bool) -> String {
        var properties: [(String, String)] = [
            ("textLanguage", "string"),
            ("partOfSpeech", "string"),
            ("definition", "string"),
        ]
        if includeExample { properties.append(("example", "string")) }
        properties += [("nativeTranslation", "string"), ("nativeDefinition", "string")]
        let props = properties.map { "\"\($0.0)\":{\"type\":\"\($0.1)\"}" }.joined(separator: ",")
        let required = properties.map { "\"\($0.0)\"" }.joined(separator: ",")
        return "{\"type\":\"object\",\"properties\":{\(props)},\"required\":[\(required)]}"
    }

    static func arguments(system: String, model: String, schema: String = wordsSchema) -> [String] {
        [
            "-p",
            "--model", model,
            "--effort", "low",
            "--output-format", "json",
            "--tools", "",
            "--strict-mcp-config",
            "--setting-sources", "",
            "--no-session-persistence",
            "--disable-slash-commands",
            "--system-prompt", system,
            "--json-schema", schema,
        ]
    }

    static func parse(_ result: ProcessResult, count: Int) throws -> [String] {
        let object = try checkedObject(from: result)
        let words = EngineResponse.clean(extractWords(from: object), count: count)
        guard !words.isEmpty else {
            throw ClaudeCLIError.invalidOutput(EngineResponse.snippet((object["result"] as? String) ?? result.stdoutString))
        }
        return words
    }

    static func parseMeaning(_ result: ProcessResult, word: String, request: SuggestionRequest) throws -> WordMeaning {
        let object = try checkedObject(from: result)
        guard let fields = structuredObject(from: object),
              let meaning = EngineResponse.makeMeaning(from: fields, word: word, request: request) else {
            throw ClaudeCLIError.invalidOutput(EngineResponse.snippet((object["result"] as? String) ?? result.stdoutString))
        }
        return meaning
    }

    static func checkedObject(from result: ProcessResult) throws -> [String: Any] {
        if result.timedOut { throw ClaudeCLIError.timedOut }

        let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let object = EngineResponse.jsonObject(in: stdout) else {
            if EngineResponse.looksLikeAuthFailure(stderr + "\n" + stdout) { throw ClaudeCLIError.notLoggedIn }
            if result.status != 0 {
                throw ClaudeCLIError.processFailed(code: result.status, stderr: EngineResponse.snippet(stderr.isEmpty ? stdout : stderr))
            }
            throw ClaudeCLIError.invalidOutput(stdout.isEmpty ? "empty output" : EngineResponse.snippet(stdout))
        }

        if object["is_error"] as? Bool == true {
            let message = [object["result"] as? String, object["subtype"] as? String, stderr]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "unknown error"
            if EngineResponse.looksLikeAuthFailure(message + "\n" + stderr) { throw ClaudeCLIError.notLoggedIn }
            throw ClaudeCLIError.cliError(EngineResponse.snippet(message))
        }
        return object
    }

    static func structuredObject(from object: [String: Any]) -> [String: Any]? {
        if let structured = object["structured_output"] as? [String: Any], !structured.isEmpty {
            return structured
        }
        guard let text = object["result"] as? String else { return nil }
        return EngineResponse.jsonObject(in: text)
    }

    static func extractWords(from object: [String: Any]) -> [String] {
        if let structured = object["structured_output"] as? [String: Any],
           let words = structured["words"] as? [String], !words.isEmpty {
            return words
        }
        guard let text = object["result"] as? String else { return [] }
        if let inner = EngineResponse.jsonObject(in: text), let words = inner["words"] as? [String] {
            return words
        }
        if let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }
        return text.components(separatedBy: CharacterSet(charactersIn: "\n,"))
    }
}
