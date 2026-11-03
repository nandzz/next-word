import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    static let countPresets = [5, 10, 20]

    private let defaults: UserDefaults

    var suggestionCount: Int { didSet { defaults.set(suggestionCount, forKey: Keys.suggestionCount) } }
    var modelID: String { didSet { defaults.set(modelID, forKey: Keys.modelID) } }
    var customModelID: String { didSet { defaults.set(customModelID, forKey: Keys.customModelID) } }
    var longPressDuration: Double { didSet { defaults.set(longPressDuration, forKey: Keys.longPressDuration) } }
    var claudePath: String { didSet { defaults.set(claudePath, forKey: Keys.claudePath) } }
    var tone: Tone { didSet { defaults.set(tone.rawValue, forKey: Keys.tone) } }
    var allowPhrases: Bool { didSet { defaults.set(allowPhrases, forKey: Keys.allowPhrases) } }
    var language: String { didSet { defaults.set(language, forKey: Keys.language) } }
    var extraInstructions: String { didSet { defaults.set(extraInstructions, forKey: Keys.extraInstructions) } }
    var contextLength: Int { didSet { defaults.set(contextLength, forKey: Keys.contextLength) } }
    var requestTimeout: Double { didSet { defaults.set(requestTimeout, forKey: Keys.requestTimeout) } }
    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) } }
    var engine: SuggestionEngine { didSet { defaults.set(engine.rawValue, forKey: Keys.engine) } }
    var fallBackToClaude: Bool { didSet { defaults.set(fallBackToClaude, forKey: Keys.fallBackToClaude) } }
    var meaningEnabled: Bool { didSet { defaults.set(meaningEnabled, forKey: Keys.meaningEnabled) } }
    var nativeLanguageCode: String { didSet { defaults.set(nativeLanguageCode, forKey: Keys.nativeLanguageCode) } }
    var meaningStartsInNative: Bool { didSet { defaults.set(meaningStartsInNative, forKey: Keys.meaningStartsInNative) } }
    var includeExample: Bool { didSet { defaults.set(includeExample, forKey: Keys.includeExample) } }
    var codexPath: String { didSet { defaults.set(codexPath, forKey: Keys.codexPath) } }
    var codexModel: String { didSet { defaults.set(codexModel, forKey: Keys.codexModel) } }

    var nativeLanguageName: String {
        Self.languageName(for: nativeLanguageCode)
    }

    static func languageName(for code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    static let languageOptions: [String] = [
        "pt", "it", "es", "fr", "de", "en", "nl", "pl", "ro", "ru", "uk", "tr", "ar", "he", "hi", "zh", "ja", "ko", "sv", "da", "no", "fi", "el", "cs", "hu",
    ]

    static var systemLanguageCode: String {
        Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
    }

    var effectiveModel: String {
        if modelID == ClaudeModelOption.custom {
            let trimmed = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "haiku" : trimmed
        }
        return modelID
    }

    var selectedModelOption: ClaudeModelOption {
        ClaudeModelOption.all.first { $0.id == modelID } ?? ClaudeModelOption.all[0]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.suggestionCount: 10,
            Keys.modelID: "haiku",
            Keys.customModelID: "",
            Keys.longPressDuration: 0.4,
            Keys.claudePath: "",
            Keys.tone: Tone.match.rawValue,
            Keys.allowPhrases: false,
            Keys.language: "",
            Keys.extraInstructions: "",
            Keys.contextLength: 1500,
            Keys.requestTimeout: 30.0,
            Keys.isEnabled: true,
            Keys.engine: SuggestionEngine.onDevice.rawValue,
            Keys.fallBackToClaude: false,
            Keys.meaningEnabled: true,
            Keys.nativeLanguageCode: Self.systemLanguageCode,
            Keys.meaningStartsInNative: false,
            Keys.includeExample: true,
            Keys.codexPath: "",
            Keys.codexModel: "",
        ])
        suggestionCount = defaults.integer(forKey: Keys.suggestionCount)
        modelID = defaults.string(forKey: Keys.modelID) ?? "haiku"
        customModelID = defaults.string(forKey: Keys.customModelID) ?? ""
        longPressDuration = defaults.double(forKey: Keys.longPressDuration)
        claudePath = defaults.string(forKey: Keys.claudePath) ?? ""
        tone = Tone(rawValue: defaults.string(forKey: Keys.tone) ?? "") ?? .match
        allowPhrases = defaults.bool(forKey: Keys.allowPhrases)
        language = defaults.string(forKey: Keys.language) ?? ""
        extraInstructions = defaults.string(forKey: Keys.extraInstructions) ?? ""
        contextLength = defaults.integer(forKey: Keys.contextLength)
        requestTimeout = defaults.double(forKey: Keys.requestTimeout)
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        engine = SuggestionEngine(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .onDevice
        fallBackToClaude = defaults.bool(forKey: Keys.fallBackToClaude)
        meaningEnabled = defaults.bool(forKey: Keys.meaningEnabled)
        nativeLanguageCode = defaults.string(forKey: Keys.nativeLanguageCode) ?? Self.systemLanguageCode
        meaningStartsInNative = defaults.bool(forKey: Keys.meaningStartsInNative)
        includeExample = defaults.bool(forKey: Keys.includeExample)
        codexPath = defaults.string(forKey: Keys.codexPath) ?? ""
        codexModel = defaults.string(forKey: Keys.codexModel) ?? ""
    }

    func makeRequest() -> SuggestionRequest {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = claudePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return SuggestionRequest(
            count: suggestionCount,
            model: effectiveModel,
            tone: tone,
            allowPhrases: allowPhrases,
            language: lang.isEmpty ? nil : lang,
            extraInstructions: extraInstructions,
            claudePath: path.isEmpty ? nil : path,
            timeout: requestTimeout,
            nativeLanguage: nativeLanguageName,
            includeExample: includeExample,
            codexPath: Self.nonEmpty(codexPath),
            codexModel: Self.nonEmpty(codexModel)
        )
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum Keys {
        static let suggestionCount = "suggestionCount"
        static let modelID = "modelID"
        static let customModelID = "customModelID"
        static let longPressDuration = "longPressDuration"
        static let claudePath = "claudePath"
        static let tone = "tone"
        static let allowPhrases = "allowPhrases"
        static let language = "language"
        static let extraInstructions = "extraInstructions"
        static let contextLength = "contextLength"
        static let requestTimeout = "requestTimeout"
        static let isEnabled = "isEnabled"
        static let engine = "engine"
        static let fallBackToClaude = "fallBackToClaude"
        static let meaningEnabled = "meaningEnabled"
        static let nativeLanguageCode = "nativeLanguageCode"
        static let meaningStartsInNative = "meaningStartsInNative"
        static let includeExample = "includeExample"
        static let codexPath = "codexPath"
        static let codexModel = "codexModel"
    }
}
