import AppKit
import SwiftUI

@main
struct NextWordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = SettingsStore.shared
    @State private var status = AppStatus.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(settings: settings, status: status)
        } label: {
            Image(nsImage: StatusBarIcon.image(active: settings.isEnabled && status.isReady))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            AppCoordinator.shared.start()
        }
    }
}
