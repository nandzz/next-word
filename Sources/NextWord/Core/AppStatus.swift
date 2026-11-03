import Foundation
import Observation

enum ConnectionTestState: Equatable {
    case idle
    case running
    case success(String)
    case failure(String)
}

@MainActor
@Observable
final class AppStatus {
    static let shared = AppStatus()

    var accessibilityGranted = false
    var hotkeyActive = false
    var claudePath: String?
    var claudeVersion: String?
    var isCheckingClaude = false
    var connectionTest: ConnectionTestState = .idle
    var lastLatency: TimeInterval?
    var onDeviceAvailable = false
    var onDeviceMessage = "Checking…"
    var codexPath: String?
    var codexVersion: String?

    var onRequestAccessibility: () -> Void = {}
    var onOpenAccessibilitySettings: () -> Void = {}
    var onRefreshClaude: () -> Void = {}
    var onTestConnection: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    var onRefreshOnDevice: () -> Void = {}
    var onOpenAppleIntelligenceSettings: () -> Void = {}
    var onRefreshCodex: () -> Void = {}

    var isReady: Bool { accessibilityGranted && hotkeyActive && (claudePath != nil || onDeviceAvailable || codexPath != nil) }
}
