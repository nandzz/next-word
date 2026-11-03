import Foundation

enum OnDeviceError: LocalizedError, Equatable {
    case unavailable(String)
    case guardrail
    case unsupportedLanguage
    case contextTooLong
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            message
        case .guardrail:
            "Apple's safety filter blocked this text. Try Claude instead."
        case .unsupportedLanguage:
            "The on-device model does not support the language of this text. Try Claude instead."
        case .contextTooLong:
            "The text is too long for the on-device model. Lower the context length in Settings or try Claude."
        case .timedOut:
            "The on-device model took too long to answer. Try again."
        case let .failed(message):
            message.isEmpty ? "The on-device model failed." : "The on-device model failed: \(message)"
        }
    }
}
