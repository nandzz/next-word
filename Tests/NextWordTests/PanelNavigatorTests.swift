import Testing
@testable import NextWord

private func listState(
    meaningEnabled: Bool = true,
    meaningStartsInNative: Bool = false,
    hasSelection: Bool = true,
    hasFailed: Bool = false,
    wordCount: Int = 5
) -> PanelState {
    PanelState(
        isShowingMeaning: false,
        meaningLanguage: .original,
        meaningEnabled: meaningEnabled,
        meaningStartsInNative: meaningStartsInNative,
        hasSelection: hasSelection,
        hasFailed: hasFailed,
        wordCount: wordCount
    )
}

private func meaningState(
    language: MeaningLanguage,
    meaningStartsInNative: Bool = false,
    wordCount: Int = 5
) -> PanelState {
    PanelState(
        isShowingMeaning: true,
        meaningLanguage: language,
        meaningEnabled: true,
        meaningStartsInNative: meaningStartsInNative,
        hasSelection: wordCount > 0,
        hasFailed: false,
        wordCount: wordCount
    )
}

struct PanelNavigatorTests {
    @Test func numberKeyWithNoWordsDoesNothing() {
        let state = PanelState(isShowingMeaning: false, meaningLanguage: .original, meaningEnabled: true, meaningStartsInNative: false, hasSelection: false, hasFailed: false, wordCount: 0)
        #expect(PanelNavigator.action(for: .number(1), in: state) == .none)
    }
}

struct PanelNavigatorListModeTests {
    @Test func upMovesSelectionBackWhenWordsExist() {
        #expect(PanelNavigator.action(for: .up, in: listState()) == .moveSelection(-1))
    }

    @Test func downMovesSelectionForwardWhenWordsExist() {
        #expect(PanelNavigator.action(for: .down, in: listState()) == .moveSelection(1))
    }

    @Test(arguments: [PanelKey.up, .down])
    func arrowsDoNothingWithoutWords(key: PanelKey) {
        #expect(PanelNavigator.action(for: key, in: listState(hasSelection: false, wordCount: 0)) == .none)
    }

    @Test func rightOpensMeaningInOriginalByDefault() {
        #expect(PanelNavigator.action(for: .right, in: listState()) == .openMeaning(.original))
    }

    @Test func rightOpensMeaningInNativeWhenConfigured() {
        #expect(PanelNavigator.action(for: .right, in: listState(meaningStartsInNative: true)) == .openMeaning(.native))
    }

    @Test(arguments: [false, true])
    func rightDoesNothingWhenMeaningDisabled(startsInNative: Bool) {
        let state = listState(meaningEnabled: false, meaningStartsInNative: startsInNative)
        #expect(PanelNavigator.action(for: .right, in: state) == .none)
    }

    @Test func rightDoesNothingWithoutSelection() {
        #expect(PanelNavigator.action(for: .right, in: listState(hasSelection: false, wordCount: 0)) == .none)
    }

    @Test func rightDoesNothingInFailedState() {
        #expect(PanelNavigator.action(for: .right, in: listState(hasSelection: false, hasFailed: true, wordCount: 0)) == .none)
    }

    @Test func leftDoesNothingInListMode() {
        #expect(PanelNavigator.action(for: .left, in: listState()) == .none)
    }

    @Test func selectInsertsSelectedWord() {
        #expect(PanelNavigator.action(for: .select, in: listState()) == .insertSelected)
    }

    @Test func selectRetriesAfterFailure() {
        #expect(PanelNavigator.action(for: .select, in: listState(hasSelection: false, hasFailed: true, wordCount: 0)) == .retrySuggestions)
    }

    @Test func selectDoesNothingWhileLoading() {
        #expect(PanelNavigator.action(for: .select, in: listState(hasSelection: false, wordCount: 0)) == .none)
    }

    @Test func refreshReloadsSuggestions() {
        #expect(PanelNavigator.action(for: .refresh, in: listState()) == .refreshSuggestions)
    }

    @Test func refreshReloadsSuggestionsInFailedState() {
        #expect(PanelNavigator.action(for: .refresh, in: listState(hasSelection: false, hasFailed: true, wordCount: 0)) == .refreshSuggestions)
    }

    @Test func dismissDismisses() {
        #expect(PanelNavigator.action(for: .dismiss, in: listState()) == .dismiss)
    }

    @Test(arguments: [
        (1, 5, PanelAction.insert(index: 0)),
        (5, 5, PanelAction.insert(index: 4)),
        (10, 10, PanelAction.insert(index: 9)),
        (0, 5, PanelAction.none),
        (6, 5, PanelAction.none),
        (10, 5, PanelAction.none),
        (-1, 5, PanelAction.none),
        (1, 0, PanelAction.none),
    ])
    func numberKeyInsertsOnlyInRange(number: Int, wordCount: Int, expected: PanelAction) {
        let state = listState(hasSelection: wordCount > 0, wordCount: wordCount)
        #expect(PanelNavigator.action(for: .number(number), in: state) == expected)
    }
}

struct PanelNavigatorMeaningModeTests {
    @Test func rightSwitchesOriginalToNative() {
        #expect(PanelNavigator.action(for: .right, in: meaningState(language: .original)) == .setMeaningLanguage(.native))
    }

    @Test(arguments: [false, true])
    func rightDoesNothingWhenAlreadyNative(startsInNative: Bool) {
        let state = meaningState(language: .native, meaningStartsInNative: startsInNative)
        #expect(PanelNavigator.action(for: .right, in: state) == .none)
    }

    @Test func leftReturnsFromNativeToOriginal() {
        #expect(PanelNavigator.action(for: .left, in: meaningState(language: .native)) == .setMeaningLanguage(.original))
    }

    @Test func leftClosesNativeWhenMeaningStartsInNative() {
        let state = meaningState(language: .native, meaningStartsInNative: true)
        #expect(PanelNavigator.action(for: .left, in: state) == .closeMeaning)
    }

    @Test(arguments: [false, true])
    func leftClosesFromOriginal(startsInNative: Bool) {
        let state = meaningState(language: .original, meaningStartsInNative: startsInNative)
        #expect(PanelNavigator.action(for: .left, in: state) == .closeMeaning)
    }

    @Test func refreshReloadsMeaning() {
        #expect(PanelNavigator.action(for: .refresh, in: meaningState(language: .original)) == .refreshMeaning)
    }

    @Test(arguments: [MeaningLanguage.original, .native])
    func arrowsStillMoveSelection(language: MeaningLanguage) {
        let state = meaningState(language: language)
        #expect(PanelNavigator.action(for: .up, in: state) == .moveSelection(-1))
        #expect(PanelNavigator.action(for: .down, in: state) == .moveSelection(1))
    }

    @Test func selectInsertsSelectedWord() {
        #expect(PanelNavigator.action(for: .select, in: meaningState(language: .native)) == .insertSelected)
    }

    @Test func numberKeyInserts() {
        #expect(PanelNavigator.action(for: .number(2), in: meaningState(language: .original)) == .insert(index: 1))
    }

    @Test func numberKeyOutOfRangeDoesNothing() {
        #expect(PanelNavigator.action(for: .number(6), in: meaningState(language: .original)) == .none)
    }

    @Test func dismissDismisses() {
        #expect(PanelNavigator.action(for: .dismiss, in: meaningState(language: .native)) == .dismiss)
    }
}

struct EngineResolverTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let selected: SuggestionEngine
        let onDevice: Bool
        let codex: Bool
        let fallback: Bool
        let engine: SuggestionEngine
        let message: String?
        var claude = true
        var isFallback = false

        var testDescription: String {
            "\(selected.rawValue) onDevice=\(onDevice) codex=\(codex) claude=\(claude) fallback=\(fallback)"
        }
    }

    static let onDeviceMessage = "on-device missing"
    static let codexMessage = "codex missing"

    static let cases: [Case] = [
        Case(selected: .onDevice, onDevice: true, codex: true, fallback: true, engine: .onDevice, message: nil),
        Case(selected: .onDevice, onDevice: true, codex: true, fallback: false, engine: .onDevice, message: nil),
        Case(selected: .onDevice, onDevice: true, codex: false, fallback: true, engine: .onDevice, message: nil),
        Case(selected: .onDevice, onDevice: true, codex: false, fallback: false, engine: .onDevice, message: nil),
        Case(selected: .onDevice, onDevice: false, codex: true, fallback: true, engine: .claude, message: nil, isFallback: true),
        Case(selected: .onDevice, onDevice: false, codex: true, fallback: false, engine: .onDevice, message: onDeviceMessage),
        Case(selected: .onDevice, onDevice: false, codex: false, fallback: true, engine: .claude, message: nil, isFallback: true),
        Case(selected: .onDevice, onDevice: false, codex: false, fallback: false, engine: .onDevice, message: onDeviceMessage),
        Case(selected: .claude, onDevice: true, codex: true, fallback: true, engine: .claude, message: nil),
        Case(selected: .claude, onDevice: true, codex: true, fallback: false, engine: .claude, message: nil),
        Case(selected: .claude, onDevice: true, codex: false, fallback: true, engine: .claude, message: nil),
        Case(selected: .claude, onDevice: true, codex: false, fallback: false, engine: .claude, message: nil),
        Case(selected: .claude, onDevice: false, codex: true, fallback: true, engine: .claude, message: nil),
        Case(selected: .claude, onDevice: false, codex: true, fallback: false, engine: .claude, message: nil),
        Case(selected: .claude, onDevice: false, codex: false, fallback: true, engine: .claude, message: nil),
        Case(selected: .claude, onDevice: false, codex: false, fallback: false, engine: .claude, message: nil),
        Case(selected: .codex, onDevice: true, codex: true, fallback: true, engine: .codex, message: nil),
        Case(selected: .codex, onDevice: true, codex: true, fallback: false, engine: .codex, message: nil),
        Case(selected: .codex, onDevice: true, codex: false, fallback: true, engine: .claude, message: nil, isFallback: true),
        Case(selected: .codex, onDevice: true, codex: false, fallback: false, engine: .codex, message: codexMessage),
        Case(selected: .codex, onDevice: false, codex: true, fallback: true, engine: .codex, message: nil),
        Case(selected: .codex, onDevice: false, codex: true, fallback: false, engine: .codex, message: nil),
        Case(selected: .codex, onDevice: false, codex: false, fallback: true, engine: .claude, message: nil, isFallback: true),
        Case(selected: .codex, onDevice: false, codex: false, fallback: false, engine: .codex, message: codexMessage),
        Case(selected: .onDevice, onDevice: false, codex: true, fallback: true, engine: .onDevice, message: onDeviceMessage, claude: false),
        Case(selected: .onDevice, onDevice: true, codex: true, fallback: true, engine: .onDevice, message: nil, claude: false),
        Case(selected: .codex, onDevice: true, codex: false, fallback: true, engine: .codex, message: codexMessage, claude: false),
        Case(selected: .codex, onDevice: true, codex: true, fallback: true, engine: .codex, message: nil, claude: false),
        Case(selected: .claude, onDevice: true, codex: true, fallback: true, engine: .claude, message: nil, claude: false),
    ]

    @Test(arguments: cases)
    func resolvesEveryCombination(testCase: Case) {
        let resolution = EngineResolver.resolve(
            selected: testCase.selected,
            onDeviceAvailable: testCase.onDevice,
            onDeviceMessage: Self.onDeviceMessage,
            codexAvailable: testCase.codex,
            codexMissingMessage: Self.codexMessage,
            claudeAvailable: testCase.claude,
            fallBackToClaude: testCase.fallback
        )
        #expect(resolution == EngineResolver.Resolution(engine: testCase.engine, unavailableMessage: testCase.message, isFallback: testCase.isFallback))
    }

    @Test func casesCoverEveryEngine() {
        #expect(Set(Self.cases.map(\.selected)) == Set(SuggestionEngine.allCases))
        #expect(Self.cases.filter(\.claude).count == SuggestionEngine.allCases.count * 8)
    }
}
