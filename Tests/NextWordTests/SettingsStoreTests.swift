import Foundation
import Testing
@testable import NextWord

@MainActor
final class SettingsStoreTests {
    private let suiteName = "NextWordTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    @Test func freshStoreHasDefaults() {
        let store = makeStore()
        #expect(store.suggestionCount == 10)
        #expect(store.modelID == "haiku")
        #expect(store.customModelID == "")
        #expect(store.longPressDuration == 0.4)
        #expect(store.claudePath == "")
        #expect(store.tone == .match)
        #expect(store.allowPhrases == false)
        #expect(store.language == "")
        #expect(store.extraInstructions == "")
        #expect(store.contextLength == 1500)
        #expect(store.requestTimeout == 30)
        #expect(store.isEnabled == true)
        #expect(store.engine == .onDevice)
        #expect(store.fallBackToClaude == false)
        #expect(store.meaningEnabled == true)
        #expect(store.nativeLanguageCode == SettingsStore.systemLanguageCode)
        #expect(store.meaningStartsInNative == false)
        #expect(store.includeExample == true)
        #expect(store.codexPath == "")
        #expect(store.codexModel == "")
        #expect(store.effectiveModel == "haiku")
    }

    @Test func valuesPersistAcrossInstances() {
        let store = makeStore()
        store.suggestionCount = 20
        store.modelID = "opus"
        store.customModelID = "my-model"
        store.longPressDuration = 0.8
        store.claudePath = "/opt/claude"
        store.tone = .formal
        store.allowPhrases = true
        store.language = "Italian"
        store.extraInstructions = "Be short."
        store.contextLength = 500
        store.requestTimeout = 12
        store.isEnabled = false
        store.engine = .codex
        store.fallBackToClaude = true
        store.meaningEnabled = false
        store.nativeLanguageCode = "pt"
        store.meaningStartsInNative = true
        store.includeExample = false
        store.codexPath = "/opt/codex"
        store.codexModel = "gpt-5"

        let reloaded = makeStore()
        #expect(reloaded.suggestionCount == 20)
        #expect(reloaded.modelID == "opus")
        #expect(reloaded.customModelID == "my-model")
        #expect(reloaded.longPressDuration == 0.8)
        #expect(reloaded.claudePath == "/opt/claude")
        #expect(reloaded.tone == .formal)
        #expect(reloaded.allowPhrases == true)
        #expect(reloaded.language == "Italian")
        #expect(reloaded.extraInstructions == "Be short.")
        #expect(reloaded.contextLength == 500)
        #expect(reloaded.requestTimeout == 12)
        #expect(reloaded.isEnabled == false)
        #expect(reloaded.engine == .codex)
        #expect(reloaded.fallBackToClaude == true)
        #expect(reloaded.meaningEnabled == false)
        #expect(reloaded.nativeLanguageCode == "pt")
        #expect(reloaded.meaningStartsInNative == true)
        #expect(reloaded.includeExample == false)
        #expect(reloaded.codexPath == "/opt/codex")
        #expect(reloaded.codexModel == "gpt-5")
    }

    @Test func unknownStoredEnumValuesFallBackToDefaults() {
        defaults.set("shouty", forKey: "tone")
        defaults.set("gemini", forKey: "engine")
        let store = makeStore()
        #expect(store.tone == .match)
        #expect(store.engine == .onDevice)
    }

    @Test(arguments: ["haiku", "sonnet", "opus", "fable"])
    func effectiveModelUsesPresetID(id: String) {
        let store = makeStore()
        store.modelID = id
        store.customModelID = "ignored"
        #expect(store.effectiveModel == id)
    }

    @Test func effectiveModelUsesTrimmedCustomID() {
        let store = makeStore()
        store.modelID = ClaudeModelOption.custom
        store.customModelID = "  claude-custom-1 \n"
        #expect(store.effectiveModel == "claude-custom-1")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func effectiveModelFallsBackToHaikuForEmptyCustomID(custom: String) {
        let store = makeStore()
        store.modelID = ClaudeModelOption.custom
        store.customModelID = custom
        #expect(store.effectiveModel == "haiku")
    }

    @Test func selectedModelOptionMatchesModelID() {
        let store = makeStore()
        store.modelID = "opus"
        #expect(store.selectedModelOption.id == "opus")
        store.modelID = "not-a-model"
        #expect(store.selectedModelOption == ClaudeModelOption.all[0])
    }

    @Test func makeRequestCopiesAndTrimsSettings() {
        let store = makeStore()
        store.suggestionCount = 5
        store.modelID = "sonnet"
        store.tone = .casual
        store.allowPhrases = true
        store.language = "  Italian \n"
        store.extraInstructions = "  keep spaces  "
        store.claudePath = "  /usr/local/bin/claude  "
        store.requestTimeout = 7
        store.nativeLanguageCode = "it"
        store.includeExample = false
        store.codexPath = " /opt/homebrew/bin/codex "
        store.codexModel = " gpt-5-codex "

        let request = store.makeRequest()
        #expect(request.count == 5)
        #expect(request.model == "sonnet")
        #expect(request.tone == .casual)
        #expect(request.allowPhrases == true)
        #expect(request.language == "Italian")
        #expect(request.extraInstructions == "  keep spaces  ")
        #expect(request.claudePath == "/usr/local/bin/claude")
        #expect(request.timeout == 7)
        #expect(request.nativeLanguage == "Italian")
        #expect(request.includeExample == false)
        #expect(request.codexPath == "/opt/homebrew/bin/codex")
        #expect(request.codexModel == "gpt-5-codex")
    }

    @Test(arguments: ["", "  ", "\n"])
    func makeRequestUsesNilForEmptyOptionalFields(value: String) {
        let store = makeStore()
        store.language = value
        store.claudePath = value
        store.codexPath = value
        store.codexModel = value

        let request = store.makeRequest()
        #expect(request.language == nil)
        #expect(request.claudePath == nil)
        #expect(request.codexPath == nil)
        #expect(request.codexModel == nil)
    }

    @Test func makeRequestUsesEffectiveCustomModel() {
        let store = makeStore()
        store.modelID = ClaudeModelOption.custom
        store.customModelID = " claude-x "
        #expect(store.makeRequest().model == "claude-x")
    }

    @Test func nativeLanguageNameFollowsCode() {
        let store = makeStore()
        store.nativeLanguageCode = "de"
        #expect(store.nativeLanguageName == "German")
    }

    @Test(arguments: [
        ("pt", "Portuguese"),
        ("it", "Italian"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("en", "English"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
    ])
    func languageNameIsEnglishName(code: String, name: String) {
        #expect(SettingsStore.languageName(for: code) == name)
    }

    @Test func everyLanguageOptionHasAName() {
        for code in SettingsStore.languageOptions {
            let name = SettingsStore.languageName(for: code)
            #expect(!name.isEmpty, "\(code)")
            #expect(name != code, "\(code)")
        }
    }

    @Test func languageOptionsAreUnique() {
        #expect(Set(SettingsStore.languageOptions).count == SettingsStore.languageOptions.count)
    }
}
