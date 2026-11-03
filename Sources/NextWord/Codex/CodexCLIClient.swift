import Foundation

enum CodexCLIError: LocalizedError, Equatable {
    case notFound
    case timedOut
    case notLoggedIn
    case processFailed(code: Int32, message: String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            "Codex CLI not found. Install it with `npm i -g @openai/codex`, then set its path in Settings → Engines if needed."
        case .timedOut:
            "Codex took too long to answer. Try again or raise the timeout in Settings."
        case .notLoggedIn:
            "Codex is not logged in. Run `codex login` in Terminal once."
        case let .processFailed(code, message):
            "Codex exited with code \(code). \(message)"
        case let .invalidOutput(message):
            "Codex returned an answer NextWord could not read. \(message)"
        }
    }
}

final class CodexCLIClient: SuggestionProviding {
    static let authFailureMarkers = ["codex login"]

    init() {}

    func suggestions(for context: TextContext, request: SuggestionRequest) async throws -> [String] {
        let prompt = [
            PromptBuilder.systemPrompt(for: request),
            PromptBuilder.userPrompt(for: context, request: request),
            #"Reply with only this JSON object and nothing else: {"words": ["...", "..."]}"#,
        ].joined(separator: "\n\n")
        let object = try await run(prompt: prompt, request: request)
        let words = (object["words"] as? [Any])?.compactMap { $0 as? String } ?? []
        let cleaned = EngineResponse.clean(words, count: request.count)
        guard !cleaned.isEmpty else { throw CodexCLIError.invalidOutput("No words in the answer.") }
        return cleaned
    }

    func meaning(of word: String, in context: TextContext, request: SuggestionRequest) async throws -> WordMeaning {
        let prompt = [
            PromptBuilder.meaningSystemPrompt(for: request),
            PromptBuilder.meaningUserPrompt(word: word, context: context, request: request),
            #"Reply with only this JSON object and nothing else: {"partOfSpeech": "...", "definition": "...", "example": "...", "nativeTranslation": "...", "nativeDefinition": "..."}"#,
        ].joined(separator: "\n\n")
        let object = try await run(prompt: prompt, request: request)
        guard let meaning = EngineResponse.makeMeaning(from: object, word: word, request: request) else {
            throw CodexCLIError.invalidOutput("The answer has no definition.")
        }
        return meaning
    }

    static func arguments(workingDirectory: URL, outputFile: URL, model: String?) -> [String] {
        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--ignore-user-config",
            "--sandbox", "read-only",
            "--color", "never",
            "--cd", workingDirectory.path,
            "-c", #"model_reasoning_effort="low""#,
            "-c", #"web_search="disabled""#,
            "-c", "features.shell_tool=false",
            "-c", "features.view_image=false",
            "-c", #"history.persistence="none""#,
            "--output-last-message", outputFile.path,
        ]
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        arguments.append("-")
        return arguments
    }

    private func run(prompt: String, request: SuggestionRequest) async throws -> [String: Any] {
        let customPath = request.codexPath
        guard let executable = await Task.detached(operation: { CodexCLILocator.resolve(customPath: customPath) }).value else {
            throw CodexCLIError.notFound
        }
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nextword-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let outputFile = workingDirectory.appendingPathComponent("answer.txt")

        let environment = await Task.detached(operation: { CodexCLILocator.environment(for: executable) }).value
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: Self.arguments(workingDirectory: workingDirectory, outputFile: outputFile, model: request.codexModel),
            environment: environment,
            currentDirectory: workingDirectory,
            input: Data(prompt.utf8),
            timeout: request.timeout > 0 ? request.timeout : 30
        )
        let answer = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? result.stdoutString
        return try Self.parse(result, answer: answer)
    }

    static func parse(_ result: ProcessResult, answer: String) throws -> [String: Any] {
        if result.timedOut { throw CodexCLIError.timedOut }
        let combined = result.stderrString + "\n" + result.stdoutString
        guard result.status == 0 else {
            if EngineResponse.looksLikeAuthFailure(combined, extraMarkers: authFailureMarkers) { throw CodexCLIError.notLoggedIn }
            let message = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.stdoutString : result.stderrString
            throw CodexCLIError.processFailed(code: result.status, message: EngineResponse.snippet(message))
        }
        guard let object = EngineResponse.jsonObject(in: answer) else {
            if EngineResponse.looksLikeAuthFailure(combined, extraMarkers: authFailureMarkers) { throw CodexCLIError.notLoggedIn }
            throw CodexCLIError.invalidOutput(EngineResponse.snippet(answer))
        }
        return object
    }
}
