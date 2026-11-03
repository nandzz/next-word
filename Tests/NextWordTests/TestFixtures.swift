import Foundation
@testable import NextWord

enum Fixtures {
    static func request(
        count: Int = 10,
        model: String = "haiku",
        tone: Tone = .match,
        allowPhrases: Bool = false,
        language: String? = nil,
        extraInstructions: String = "",
        nativeLanguage: String = "Italian",
        includeExample: Bool = true
    ) -> SuggestionRequest {
        SuggestionRequest(
            count: count,
            model: model,
            tone: tone,
            allowPhrases: allowPhrases,
            language: language,
            extraInstructions: extraInstructions,
            claudePath: nil,
            timeout: 30,
            nativeLanguage: nativeLanguage,
            includeExample: includeExample
        )
    }

    static func context(
        _ before: String,
        _ after: String = "",
        appName: String = "Notes",
        windowTitle: String? = nil
    ) -> TextContext {
        TextContext(
            appName: appName,
            bundleID: nil,
            windowTitle: windowTitle,
            textBeforeCursor: before,
            textAfterCursor: after,
            caretRect: nil
        )
    }

    static func result(
        stdout: String,
        stderr: String = "",
        status: Int32 = 0,
        timedOut: Bool = false
    ) -> ProcessResult {
        ProcessResult(
            status: status,
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8),
            timedOut: timedOut,
            cancelled: false
        )
    }

    static func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
