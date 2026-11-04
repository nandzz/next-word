import Foundation
import FoundationModels
@available(macOS 26.0, *)
enum OnDeviceEngine {
    static func availability() -> (available: Bool, message: String) {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return (true, model.supportsLocale() ? "Ready" : "Ready. Your system language may not be fully supported.")
        case let .unavailable(reason):
            return (false, message(for: reason))
        }
    }

    static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings."
        case .deviceNotEligible:
            "This Mac does not support Apple Intelligence."
        case .modelNotReady:
            "The on-device model is still downloading. Try again later."
        @unknown default:
            "The on-device model is not available."
        }
    }

    static func prewarm() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        LanguageModelSession(model: .default).prewarm()
    }

    static func suggestions(for context: TextContext, request: SuggestionRequest) async throws -> [String] {
        try ensureAvailable()
        let count = max(1, request.count)
        let language = OnDevicePrompt.textLanguage(of: context, request: request)
        let partial = OnDevicePrompt.unfinishedWord(in: context.textBeforeCursor)
        let session = LanguageModelSession(model: .default, instructions: OnDevicePrompt.suggestionInstructions(for: request, language: language, partial: partial))
        let prompt = OnDevicePrompt.suggestionPrompt(for: context, language: language, partial: partial)
        let requested = count + min(3, count)
        let schema = try wordsSchema(count: requested)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: requested * 12 + 64)

        let words = try await perform(timeout: request.timeout) {
            let response = try await session.respond(to: prompt, schema: schema, includeSchemaInPrompt: true, options: options)
            return try response.content.value([String].self, forProperty: "words")
        }
        let cleaned = EngineResponse.clean(rank(words, partial: partial, allowPhrases: request.allowPhrases), count: count)
        guard !cleaned.isEmpty else { throw OnDeviceError.failed("The model returned no words.") }
        return cleaned
    }

    static func rank(_ words: [String], partial: String?, allowPhrases: Bool) -> [String] {
        var candidates = words.map(EngineResponse.cleanWord).filter { !$0.isEmpty }
        if !allowPhrases {
            let single = candidates.filter { !$0.contains(where: \.isWhitespace) }
            candidates = single.isEmpty ? candidates.compactMap { $0.split(whereSeparator: \.isWhitespace).first.map(String.init) } : single
        }
        guard let partial = partial?.lowercased() else { return candidates }
        let completions = candidates.filter { $0.lowercased().hasPrefix(partial) && $0.count > partial.count }
        return completions.isEmpty ? candidates : completions + candidates.filter { !completions.contains($0) }
    }

    static func meaning(of word: String, in context: TextContext, request: SuggestionRequest) async throws -> WordMeaning {
        try ensureAvailable()
        let language = OnDevicePrompt.textLanguage(of: context, request: request)
        let session = LanguageModelSession(model: .default, instructions: OnDevicePrompt.meaningInstructions)
        let prompt = OnDevicePrompt.meaningPrompt(word: word, context: context, request: request, language: language)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 400)
        let schema = try meaningSchema(language: language, nativeLanguage: request.nativeLanguage, includeExample: request.includeExample)
        let keys = meaningKeys

        let fields: [String: String] = try await perform(timeout: request.timeout) {
            let content = try await session.respond(to: prompt, schema: schema, includeSchemaInPrompt: true, options: options).content
            var fields: [String: String] = [:]
            for key in keys {
                if let value = try? content.value(String.self, forProperty: key) { fields[key] = value }
            }
            return fields
        }
        guard var meaning = EngineResponse.makeMeaning(from: fields, word: word, request: request) else {
            throw OnDeviceError.failed("The model returned an empty definition.")
        }
        if let example = meaning.example, normalized(OnDevicePrompt.sentence(inserting: word, into: context)).contains(normalized(example)) {
            meaning.example = nil
        }
        return meaning
    }

    static func rewrites(of target: RewriteTarget, request: SuggestionRequest) async throws -> [Rewrite] {
        try ensureAvailable()
        let language = OnDevicePrompt.textLanguage(ofSample: target.trimmedText, request: request)
        let session = LanguageModelSession(model: .default, instructions: OnDevicePrompt.rewriteInstructions(for: request, language: language))
        let prompt = OnDevicePrompt.rewritePrompt(for: target, language: language)
        let schema = try rewriteSchema(language: language, tone: request.tone)
        let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: min(2400, max(240, target.text.count * 3 / 2 + 120)))
        let keys = RewriteStyle.allCases.map(\.rawValue)

        let fields: [String: String] = try await perform(timeout: request.timeout) {
            let content = try await session.respond(to: prompt, schema: schema, includeSchemaInPrompt: true, options: options).content
            var fields: [String: String] = [:]
            for key in keys {
                if let value = try? content.value(String.self, forProperty: key) { fields[key] = value }
            }
            return fields
        }
        guard EngineResponse.hasRewriteFields(fields) else { throw OnDeviceError.failed("The model returned no rewrite.") }
        return EngineResponse.makeRewrites(from: fields, original: target.text)
    }

    private static func rewriteSchema(language: String?, tone: Tone) throws -> GenerationSchema {
        let text = language ?? "the language of the message"
        func property(_ style: RewriteStyle, _ description: String) -> DynamicGenerationSchema.Property {
            DynamicGenerationSchema.Property(name: style.rawValue, description: description, schema: DynamicGenerationSchema(type: String.self))
        }
        let properties = [
            property(.clearer, "The message in \(text) with correct grammar, spelling and punctuation, clear and natural, about the same length"),
            property(.shorter, "The same message in \(text), shorter and more direct"),
            property(.reworded, "The same message in \(text) with different wording. \(tone.promptHint)"),
        ]
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Rewrites", properties: properties), dependencies: [])
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    private static func ensureAvailable() throws {
        if case let .unavailable(reason) = SystemLanguageModel.default.availability {
            throw OnDeviceError.unavailable(message(for: reason))
        }
    }

    private static let meaningKeys = ["partOfSpeech", "definition", "example", "nativeTranslation", "nativeDefinition"]

    private static func meaningSchema(language: String?, nativeLanguage: String, includeExample: Bool) throws -> GenerationSchema {
        let text = language ?? "the language of the sentence"
        func property(_ name: String, _ description: String) -> DynamicGenerationSchema.Property {
            DynamicGenerationSchema.Property(name: name, description: description, schema: DynamicGenerationSchema(type: String.self))
        }
        var properties = [
            property("partOfSpeech", "Part of speech, in \(text)"),
            property("definition", "Dictionary definition of the word in \(text), at most 15 words. Do not repeat the sentence."),
        ]
        if includeExample {
            properties.append(property("example", "A different short example sentence in \(text) using the word"))
        }
        properties += [
            property("nativeTranslation", "The \(nativeLanguage) translation of the word, 1 to 3 words"),
            property("nativeDefinition", "The definition translated into \(nativeLanguage)"),
        ]
        return try GenerationSchema(root: DynamicGenerationSchema(name: "DictionaryEntry", properties: properties), dependencies: [])
    }

    private static func wordsSchema(count: Int) throws -> GenerationSchema {
        let words = DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(type: String.self),
            minimumElements: count,
            maximumElements: count
        )
        let root = DynamicGenerationSchema(
            name: "Suggestions",
            properties: [
                DynamicGenerationSchema.Property(name: "words", description: "Candidates for the word at the cursor, best first", schema: words),
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func perform<T: Sendable>(
        timeout: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let seconds = timeout > 0 ? timeout : 30
        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw OnDeviceError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw CancellationError() }
                return first
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw mapError(error)
        }
    }

    static func mapError(_ error: Error) -> Error {
        if error is CancellationError || error is OnDeviceError { return error }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            if let mapped = mapModernError(error) { return mapped }
        }
        #endif
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize:
                return OnDeviceError.contextTooLong
            case .guardrailViolation, .refusal:
                return OnDeviceError.guardrail
            case .unsupportedLanguageOrLocale:
                return OnDeviceError.unsupportedLanguage
            case .assetsUnavailable:
                return OnDeviceError.unavailable(availability().message)
            case .rateLimited, .concurrentRequests:
                return OnDeviceError.failed("The on-device model is busy. Try again.")
            default:
                return OnDeviceError.failed(generation.localizedDescription)
            }
        }
        return OnDeviceError.failed(error.localizedDescription)
    }

    #if compiler(>=6.4)
    @available(macOS 27.0, *)
    private static func mapModernError(_ error: Error) -> OnDeviceError? {
        if let languageError = error as? LanguageModelError {
            switch languageError {
            case .contextSizeExceeded:
                return .contextTooLong
            case .guardrailViolation, .refusal:
                return .guardrail
            case .unsupportedLanguageOrLocale:
                return .unsupportedLanguage
            case .timeout:
                return .timedOut
            case .rateLimited:
                return .failed("The on-device model is busy. Try again.")
            default:
                return .failed(languageError.localizedDescription)
            }
        }
        if error is SystemLanguageModel.Error {
            return .unavailable(availability().message)
        }
        return nil
    }
    #endif
}
