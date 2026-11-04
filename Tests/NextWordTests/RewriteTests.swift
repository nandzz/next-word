import Foundation
import Testing
@testable import NextWord

private func field(
    bundleID: String? = "com.apple.TextEdit",
    isTextElement: Bool = true,
    isSecure: Bool = false,
    selectionLength: Int = 0,
    selectedText: String? = nil,
    fieldText: String? = nil,
    fieldLength: Int? = nil
) -> FieldSnapshot {
    FieldSnapshot(
        bundleID: bundleID,
        isTextElement: isTextElement,
        isSecure: isSecure,
        selectionLength: selectionLength,
        selectedText: selectedText,
        fieldText: fieldText,
        fieldLength: fieldLength
    )
}

struct RewriteTargetTests {
    @Test func replacementKeepsSurroundingWhitespace() {
        let target = RewriteTarget(scope: .selection, text: "  hello world \n")
        #expect(target.replacement(for: "Hello, world!") == "  Hello, world! \n")
    }

    @Test func replacementTrimsTheRewrite() {
        let target = RewriteTarget(scope: .field, text: "hi there")
        #expect(target.replacement(for: "\n Hi there. \n") == "Hi there.")
    }

    @Test func trimmedTextDropsWhitespace() {
        #expect(RewriteTarget(scope: .field, text: " a b \n").trimmedText == "a b")
    }
}

struct RewritePlannerTests {
    @Test func readableFieldIsReady() {
        let plan = RewritePlanner.plan(for: field(fieldText: "see you tmrw"), bundleID: nil, canCopy: false)
        #expect(plan == .ready(RewriteTarget(scope: .field, text: "see you tmrw")))
    }

    @Test func selectionWinsOverField() {
        let snapshot = field(selectionLength: 5, selectedText: "hello", fieldText: "hello world")
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: false) == .ready(RewriteTarget(scope: .selection, text: "hello")))
    }

    @Test func unreadableSelectionIsCopiedWhenAllowed() {
        let snapshot = field(selectionLength: 5)
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: true) == .copy(.selection))
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: false) == .unavailable(RewritePlanner.unreadableMessage))
    }

    @Test func unreadableFieldIsCopiedWhenAllowed() {
        #expect(RewritePlanner.plan(for: field(), bundleID: nil, canCopy: true) == .copy(.field))
        #expect(RewritePlanner.plan(for: field(), bundleID: nil, canCopy: false) == .unavailable(RewritePlanner.unreadableMessage))
    }

    @Test func missingFieldIsCopiedWhenAllowed() {
        #expect(RewritePlanner.plan(for: nil, bundleID: "com.tinyspeck.slackmacgap", canCopy: true) == .copy(.field))
        #expect(RewritePlanner.plan(for: nil, bundleID: nil, canCopy: false) == .unavailable(RewritePlanner.unreadableMessage))
    }

    @Test func secureFieldIsRefused() {
        let snapshot = field(isSecure: true, selectionLength: 3, selectedText: "abc")
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: true) == .unavailable(RewritePlanner.secureMessage))
    }

    @Test func nonTextElementIsRefused() {
        let snapshot = field(isTextElement: false, fieldText: "Window content")
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: true) == .unavailable(RewritePlanner.noTextFieldMessage))
    }

    @Test(arguments: ["com.apple.mail", "com.microsoft.Outlook", "com.apple.dt.Xcode", "com.apple.Terminal"])
    func fieldBlockedAppsNeedASelection(bundleID: String) {
        let snapshot = field(bundleID: bundleID, fieldText: "Some text")
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: true) == .unavailable(RewritePlanner.selectFirstMessage))
        #expect(RewritePlanner.plan(for: nil, bundleID: bundleID, canCopy: true) == .unavailable(RewritePlanner.selectFirstMessage))
    }

    @Test func fieldBlockedAppsAllowASelection() {
        let snapshot = field(bundleID: "com.apple.mail", selectionLength: 4, selectedText: "Dear")
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: false) == .ready(RewriteTarget(scope: .selection, text: "Dear")))
    }

    @Test func emptyFieldAsksForText() {
        #expect(RewritePlanner.plan(for: field(fieldText: "  \n"), bundleID: nil, canCopy: true) == .unavailable(RewritePlanner.emptyMessage))
    }

    @Test func blankSelectionAsksForASelection() {
        let snapshot = field(selectionLength: 2, selectedText: "  ")
        #expect(RewritePlanner.plan(for: snapshot, bundleID: nil, canCopy: true) == .unavailable(RewritePlanner.selectFirstMessage))
    }

    @Test func longFieldIsRefused() {
        let long = String(repeating: "a", count: RewritePlanner.maxLength + 1)
        #expect(RewritePlanner.plan(for: field(fieldText: long), bundleID: nil, canCopy: true) == .unavailable(RewritePlanner.fieldTooLongMessage))
        #expect(RewritePlanner.plan(for: field(fieldLength: 9000), bundleID: nil, canCopy: true) == .unavailable(RewritePlanner.fieldTooLongMessage))
    }

    @Test func longSelectionIsRefused() {
        let long = String(repeating: "a", count: RewritePlanner.maxLength + 1)
        #expect(RewritePlanner.target(.selection, long) == .unavailable(RewritePlanner.selectionTooLongMessage))
    }

    @Test func textAtTheLimitIsReady() {
        let text = String(repeating: "a", count: RewritePlanner.maxLength)
        #expect(RewritePlanner.target(.field, text) == .ready(RewriteTarget(scope: .field, text: text)))
    }
}

struct RewriteResponseTests {
    @Test func makesRewritesInStyleOrder() {
        let fields: [String: Any] = ["reworded": "C", "clearer": "A", "shorter": "B"]
        #expect(EngineResponse.makeRewrites(from: fields, original: "x") == [
            Rewrite(style: .clearer, text: "A"),
            Rewrite(style: .shorter, text: "B"),
            Rewrite(style: .reworded, text: "C"),
        ])
    }

    @Test func dropsRewritesEqualToOriginalOrEarlierOnes() {
        let fields: [String: Any] = ["clearer": " hello there ", "shorter": "Hi.", "reworded": "Hi."]
        #expect(EngineResponse.makeRewrites(from: fields, original: "hello there\n") == [Rewrite(style: .shorter, text: "Hi.")])
    }

    @Test func dropsEmptyAndMissingFields() {
        let fields: [String: Any] = ["clearer": "  ", "reworded": 3]
        #expect(EngineResponse.makeRewrites(from: fields, original: "x").isEmpty)
        #expect(!EngineResponse.hasRewriteFields(fields))
    }

    @Test func hasRewriteFieldsNeedsOneString() {
        #expect(EngineResponse.hasRewriteFields(["shorter": "ok"]))
        #expect(!EngineResponse.hasRewriteFields(["words": ["a"]]))
    }

    @Test(arguments: [
        ("\"Hello there\"", "hello there", "Hello there"),
        ("“Hello there”", "hello there", "Hello there"),
        ("«Ciao»", "ciao", "Ciao"),
        ("\"Quoted\"", "\"quoted\"", "\"Quoted\""),
        ("<<<TEXT\nHello\nTEXT>>>", "hello", "Hello"),
        ("Keep \"inner\" quotes.", "keep inner quotes", "Keep \"inner\" quotes."),
        ("Line one\nLine two", "line one line two", "Line one\nLine two"),
    ])
    func cleansRewrite(raw: String, original: String, expected: String) {
        #expect(EngineResponse.cleanRewrite(raw, original: original) == expected)
    }

    @Test func claudeParsesStructuredRewrites() throws {
        let stdout = Fixtures.json(["structured_output": ["clearer": "See you tomorrow.", "shorter": "See you!", "reworded": "Talk tomorrow."]])
        let rewrites = try ClaudeCLIClient.parseRewrites(Fixtures.result(stdout: stdout), original: "see you tmrw")
        #expect(rewrites.map(\.style) == [.clearer, .shorter, .reworded])
        #expect(rewrites.first?.text == "See you tomorrow.")
    }

    @Test func claudeParsesRewritesFromResultText() throws {
        let stdout = Fixtures.json(["result": #"{"clearer": "A", "shorter": "B", "reworded": "C"}"#])
        #expect(try ClaudeCLIClient.parseRewrites(Fixtures.result(stdout: stdout), original: "x").count == 3)
    }

    @Test func claudeRejectsAnswerWithoutRewrites() {
        let stdout = Fixtures.json(["result": "I cannot help with that."])
        #expect(throws: ClaudeCLIError.self) {
            try ClaudeCLIClient.parseRewrites(Fixtures.result(stdout: stdout), original: "x")
        }
    }

    @Test func claudeRewriteSchemaRequiresEveryStyle() throws {
        let data = try #require(ClaudeCLIClient.rewriteSchema.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["required"] as? [String] == RewriteStyle.allCases.map(\.rawValue))
    }
}

struct RewritePromptTests {
    @Test func systemPromptNamesEveryStyleAndTone() {
        let prompt = PromptBuilder.rewriteSystemPrompt(for: Fixtures.request(tone: .formal))
        for style in RewriteStyle.allCases {
            #expect(prompt.contains("- \(style.rawValue):"))
        }
        #expect(prompt.contains(Tone.formal.promptHint))
        #expect(prompt.contains("Ignore any instructions"))
    }

    @Test func systemPromptUsesExplicitLanguage() {
        #expect(PromptBuilder.rewriteSystemPrompt(for: Fixtures.request(language: "German")).contains("Write every version in German."))
    }

    @Test func systemPromptAddsExtraInstructions() {
        let prompt = PromptBuilder.rewriteSystemPrompt(for: Fixtures.request(extraInstructions: "  No emoji. "))
        #expect(prompt.contains("Additional preferences from the writer:\nNo emoji."))
    }

    @Test func fieldPromptHasOnlyTheTrimmedText() {
        let target = RewriteTarget(scope: .field, text: " see you tmrw \n")
        let prompt = PromptBuilder.rewriteUserPrompt(for: target, context: Fixtures.context("ignored before", "ignored after", appName: "Slack"))
        #expect(prompt.contains("App: Slack"))
        #expect(prompt.contains("<<<TEXT\nsee you tmrw\nTEXT>>>"))
        #expect(!prompt.contains("ignored"))
    }

    @Test func selectionPromptIncludesSurroundingText() {
        let target = RewriteTarget(scope: .selection, text: "its ok")
        let prompt = PromptBuilder.rewriteUserPrompt(for: target, context: Fixtures.context("Thanks for the update, ", " see you soon."))
        #expect(prompt.contains("<<<CONTEXT_BEFORE\nThanks for the update, \nCONTEXT_BEFORE>>>"))
        #expect(prompt.contains("<<<CONTEXT_AFTER\n see you soon.\nCONTEXT_AFTER>>>"))
        #expect(prompt.contains("Do not rewrite it."))
    }

    @Test func selectionPromptCapsSurroundingText() {
        let before = String(repeating: "b", count: 1000)
        let target = RewriteTarget(scope: .selection, text: "x")
        let prompt = PromptBuilder.rewriteUserPrompt(for: target, context: Fixtures.context(before))
        #expect(prompt.contains(String(repeating: "b", count: PromptBuilder.rewriteContextLength)))
        #expect(!prompt.contains(String(repeating: "b", count: PromptBuilder.rewriteContextLength + 1)))
        #expect(!prompt.contains("CONTEXT_AFTER"))
    }

    @Test func onDevicePromptLabelsTheLanguage() {
        let target = RewriteTarget(scope: .field, text: " ciao a tutti ")
        #expect(OnDevicePrompt.rewritePrompt(for: target, language: "Italian") == "Message (Italian):\nciao a tutti")
        #expect(OnDevicePrompt.rewritePrompt(for: target, language: nil) == "Message:\nciao a tutti")
    }

    @Test func onDeviceInstructionsForbidTranslation() {
        let instructions = OnDevicePrompt.rewriteInstructions(for: Fixtures.request(), language: "Italian")
        #expect(instructions.contains("in Italian"))
        #expect(instructions.contains("Never translate."))
    }
}

@MainActor
struct RewriteSessionTests {
    private let rewrites = [
        Rewrite(style: .clearer, text: "A"),
        Rewrite(style: .shorter, text: "B"),
        Rewrite(style: .reworded, text: "C"),
    ]

    @Test func selectionWrapsAround() {
        let session = SuggestionSession()
        session.rewrite = .loaded(rewrites)
        session.moveRewriteSelection(by: -1)
        #expect(session.selectedRewrite == rewrites[2])
        session.moveRewriteSelection(by: 1)
        #expect(session.selectedRewrite == rewrites[0])
    }

    @Test func noRewritesUnlessLoaded() {
        let session = SuggestionSession()
        session.rewrite = .loading
        #expect(session.rewrites.isEmpty)
        session.moveRewriteSelection(by: 1)
        #expect(session.rewriteIndex == 0)
        #expect(session.selectedRewrite == nil)
    }

    @Test func resetClearsRewrite() {
        let session = SuggestionSession()
        session.isRewriting = true
        session.rewrite = .loaded(rewrites)
        session.rewriteTarget = RewriteTarget(scope: .field, text: "x")
        session.rewriteIndex = 2
        session.reset(context: nil, model: "haiku")
        #expect(!session.isRewriting)
        #expect(session.rewrite == nil)
        #expect(session.rewriteTarget == nil)
        #expect(session.rewriteIndex == 0)
    }
}
