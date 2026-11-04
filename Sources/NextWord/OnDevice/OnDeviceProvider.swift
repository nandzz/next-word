import Foundation
import os

enum OnDeviceModel {
    static let unsupportedSystemMessage = "Requires macOS 26 or later."
    static let prewarmInterval: TimeInterval = 120

    private static let lastPrewarm = OSAllocatedUnfairLock<Date?>(initialState: nil)

    static func availability() -> (available: Bool, message: String) {
        guard #available(macOS 26.0, *) else { return (false, unsupportedSystemMessage) }
        return OnDeviceEngine.availability()
    }

    static func prewarm() {
        guard #available(macOS 26.0, *) else { return }
        let now = Date()
        let due = lastPrewarm.withLock { last -> Bool in
            if let last, now.timeIntervalSince(last) < prewarmInterval { return false }
            last = now
            return true
        }
        if due { OnDeviceEngine.prewarm() }
    }
}

final class OnDeviceProvider: SuggestionProviding {
    init() {}

    func suggestions(for context: TextContext, request: SuggestionRequest) async throws -> [String] {
        guard #available(macOS 26.0, *) else { throw OnDeviceError.unavailable(OnDeviceModel.unsupportedSystemMessage) }
        return try await OnDeviceEngine.suggestions(for: context, request: request)
    }

    func meaning(of word: String, in context: TextContext, request: SuggestionRequest) async throws -> WordMeaning {
        guard #available(macOS 26.0, *) else { throw OnDeviceError.unavailable(OnDeviceModel.unsupportedSystemMessage) }
        return try await OnDeviceEngine.meaning(of: word, in: context, request: request)
    }

    func rewrites(of target: RewriteTarget, in context: TextContext, request: SuggestionRequest) async throws -> [Rewrite] {
        guard #available(macOS 26.0, *) else { throw OnDeviceError.unavailable(OnDeviceModel.unsupportedSystemMessage) }
        return try await OnDeviceEngine.rewrites(of: target, request: request)
    }
}
