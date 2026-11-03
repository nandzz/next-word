import Foundation
import Testing
@testable import NextWord

struct ModelsTests {
    @Test(arguments: Tone.allCases)
    func toneHasTitleAndPromptHint(tone: Tone) {
        #expect(!tone.title.isEmpty)
        #expect(!tone.promptHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(tone.id == tone.rawValue)
    }

    @Test func tonePromptHintsAreDistinct() {
        #expect(Set(Tone.allCases.map(\.promptHint)).count == Tone.allCases.count)
    }

    @Test func claudeModelOptionIDsAreUnique() {
        let ids = ClaudeModelOption.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func claudeModelOptionsContainCustom() {
        #expect(ClaudeModelOption.all.contains { $0.id == ClaudeModelOption.custom })
    }

    @Test func firstClaudeModelOptionIsHaiku() {
        #expect(ClaudeModelOption.all.first?.id == "haiku")
    }

    @Test(arguments: ClaudeModelOption.all)
    func claudeModelOptionHasDisplayFields(option: ClaudeModelOption) {
        #expect(!option.name.isEmpty)
        #expect(!option.detail.isEmpty)
        #expect(!option.symbol.isEmpty)
    }

    @Test(arguments: SuggestionEngine.allCases)
    func suggestionEngineHasDisplayFields(engine: SuggestionEngine) {
        #expect(!engine.title.isEmpty)
        #expect(!engine.detail.isEmpty)
        #expect(!engine.symbol.isEmpty)
        #expect(engine.id == engine.rawValue)
    }

    @Test func suggestionEngineTitlesAndSymbolsAreUnique() {
        let engines = SuggestionEngine.allCases
        #expect(Set(engines.map(\.title)).count == engines.count)
        #expect(Set(engines.map(\.symbol)).count == engines.count)
    }

    @Test func suggestionEngineTitles() {
        #expect(SuggestionEngine.onDevice.title == "On-device")
        #expect(SuggestionEngine.claude.title == "Claude")
        #expect(SuggestionEngine.codex.title == "Codex")
    }
}
