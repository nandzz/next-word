import AppKit
import Observation
import OSLog
import SwiftUI

@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    let settings = SettingsStore.shared
    let status = AppStatus.shared
    let session = SuggestionSession()

    private let hotkey = HotkeyMonitor()
    private let client = ClaudeCLIClient()
    private let onDevice = OnDeviceProvider()
    private let codex = CodexCLIClient()
    private var meaningTask: Task<Void, Never>?
    private lazy var panel = SuggestionPanelController(session: session, settings: settings)
    private var requestTask: Task<Void, Never>?
    private var contextTask: Task<Void, Never>?
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?
    private let log = Logger(subsystem: AppInfo.bundleID, category: "coordinator")

    func start() {
        wireStatusActions()
        wirePanel()
        wireHotkey()
        observeLongPressDuration()
        refreshAccessibility()
        refreshClaude()
        refreshCodex()
        refreshOnDevice()
        observeActiveApplication()
    }

    private func observeActiveApplication() {
        if let front = NSWorkspace.shared.frontmostApplication, status.accessibilityGranted {
            Task.detached { FocusedTextReader.prepare(front) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                self.refreshOnDevice()
                guard self.status.accessibilityGranted else { return }
                Task.detached { FocusedTextReader.prepare(app) }
            }
        }
    }

    private func wireStatusActions() {
        status.onRequestAccessibility = { [weak self] in
            AccessibilityPermission.request()
            self?.watchAccessibility()
        }
        status.onOpenAccessibilitySettings = { [weak self] in
            AccessibilityPermission.openSystemSettings()
            self?.watchAccessibility()
        }
        status.onRefreshClaude = { [weak self] in self?.refreshClaude() }
        status.onTestConnection = { [weak self] in self?.testConnection() }
        status.onOpenSettings = { [weak self] in self?.openSettings() }
        status.onQuit = { NSApp.terminate(nil) }
        status.onRefreshOnDevice = { [weak self] in self?.refreshOnDevice() }
        status.onRefreshCodex = { [weak self] in self?.refreshCodex() }
        status.onOpenAppleIntelligenceSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func wirePanel() {
        panel.onSelect = { [weak self] word in self?.insert(word) }
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.onRefresh = { [weak self] in self?.fetchSuggestions() }
        panel.onOpenMeaning = { [weak self] in self?.handle(.right) }
        panel.onMeaningBack = { [weak self] in self?.handle(.left) }
    }

    private func wireHotkey() {
        hotkey.longPressDuration = settings.longPressDuration
        hotkey.isEnabled = settings.isEnabled
        hotkey.onTrigger = { [weak self] in self?.trigger() }
        hotkey.onPanelKey = { [weak self] key in self?.handle(key) }
    }

    private func observeLongPressDuration() {
        withObservationTracking {
            _ = settings.longPressDuration
            _ = settings.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.hotkey.longPressDuration = self.settings.longPressDuration
                self.hotkey.isEnabled = self.settings.isEnabled
                if !self.settings.isEnabled { self.dismiss() }
                self.observeLongPressDuration()
            }
        }
    }

    private func refreshAccessibility() {
        status.accessibilityGranted = AccessibilityPermission.isTrusted
        if status.accessibilityGranted {
            if !hotkey.isRunning {
                status.hotkeyActive = hotkey.start()
                log.notice("Accessibility granted, hotkey tap started: \(self.status.hotkeyActive)")
                DebugLog.write("accessibility granted, tap started=\(status.hotkeyActive)")
            }
            if hotkey.isRunning {
                permissionTimer?.invalidate()
                permissionTimer = nil
            } else {
                watchAccessibility()
            }
        } else {
            watchAccessibility()
        }
    }

    private func watchAccessibility() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibility() }
        }
    }

    private func refreshClaude() {
        status.isCheckingClaude = true
        let customPath = settings.makeRequest().claudePath
        Task {
            let url = await Task.detached { ClaudeCLILocator.locate(customPath: customPath) }.value
            var version: String?
            if let url {
                version = await ClaudeCLILocator.version(at: url)
            }
            status.claudePath = url?.path
            status.claudeVersion = version
            status.isCheckingClaude = false
        }
    }

    private func refreshCodex() {
        let customPath = settings.makeRequest().codexPath
        Task {
            let url = await Task.detached { CodexCLILocator.locate(customPath: customPath) }.value
            var version: String?
            if let url {
                version = await CodexCLILocator.version(at: url)
            }
            status.codexPath = url?.path
            status.codexVersion = version
        }
    }

    private func refreshOnDevice() {
        let availability = OnDeviceModel.availability()
        let becameAvailable = availability.available && !status.onDeviceAvailable
        status.onDeviceAvailable = availability.available
        status.onDeviceMessage = availability.message
        if becameAvailable || (availability.available && settings.engine == .onDevice) {
            OnDeviceModel.prewarm()
        }
    }

    private var resolution: EngineResolver.Resolution {
        EngineResolver.resolve(
            selected: settings.engine,
            onDeviceAvailable: status.onDeviceAvailable,
            onDeviceMessage: status.onDeviceMessage,
            codexAvailable: status.codexPath != nil,
            codexMissingMessage: CodexCLIError.notFound.errorDescription ?? "Codex CLI not found.",
            claudeAvailable: status.claudePath != nil,
            fallBackToClaude: settings.fallBackToClaude
        )
    }

    private func provider(for engine: SuggestionEngine) -> SuggestionProviding {
        switch engine {
        case .onDevice: onDevice
        case .claude: client
        case .codex: codex
        }
    }

    private func displayName(for engine: SuggestionEngine) -> String {
        switch engine {
        case .onDevice: SuggestionEngine.onDevice.title
        case .claude: modelDisplayName
        case .codex: settings.codexModel.isEmpty ? SuggestionEngine.codex.title : settings.codexModel
        }
    }

    private func testConnection() {
        status.connectionTest = .running
        let request = settings.makeRequest()
        Task {
            do {
                let result = try await client.testConnection(request: request)
                let seconds = String(format: "%.1f", result.latency)
                status.lastLatency = result.latency
                status.connectionTest = .success("Got \(result.sample.count) words in \(seconds) s")
            } catch {
                status.connectionTest = .failure(error.localizedDescription)
            }
        }
    }

    private func trigger() {
        guard settings.isEnabled else { return }
        contextTask?.cancel()
        let maxLength = settings.contextLength
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let front = NSWorkspace.shared.frontmostApplication
        let resolution = resolution
        session.reset(context: nil, model: displayName(for: resolution.engine))
        session.engine = resolution.engine
        session.isFallback = resolution.isFallback
        session.nativeLanguageName = settings.nativeLanguageName
        hotkey.isPanelActive = true

        contextTask = Task {
            let axContext = await Task.detached {
                FocusedTextReader.readContext(maxLength: maxLength, primaryScreenHeight: screenHeight)
            }.value
            guard !Task.isCancelled, hotkey.isPanelActive else { return }
            DebugLog.write("trigger: app=\(axContext?.bundleID ?? "nil") before=\(axContext?.textBeforeCursor.count ?? -1) readable=\(axContext?.valueReadable ?? false) caret=\(axContext?.caretRect != nil)")
            session.context = axContext
            panel.show(near: axContext?.caretRect)

            if let axContext, !axContext.textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fetchSuggestions()
                return
            }
            let bundleID = axContext?.bundleID ?? front?.bundleIdentifier
            guard ClipboardContextReader.canUseFallback(for: axContext, bundleID: bundleID) else {
                session.phase = .failed(axContext?.valueReadable == true
                    ? "Type a few words first, then long-press ? again."
                    : "NextWord cannot read the text in this app.")
                return
            }

            let copied = await ClipboardContextReader.readTextBeforeCursor()
            guard !Task.isCancelled, session.phase == .loading else { return }
            let text = String((copied ?? "").suffix(maxLength))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                session.phase = .failed("Could not read the text before the cursor. Type a few words first, then long-press ? again.")
                return
            }
            session.context = TextContext(
                appName: axContext?.appName ?? front?.localizedName ?? "Unknown",
                bundleID: bundleID,
                windowTitle: axContext?.windowTitle,
                textBeforeCursor: text,
                textAfterCursor: axContext?.textAfterCursor ?? "",
                caretRect: axContext?.caretRect
            )
            fetchSuggestions()
        }
    }

    private var modelDisplayName: String {
        settings.modelID == ClaudeModelOption.custom ? settings.effectiveModel : settings.selectedModelOption.name
    }

    private func fetchSuggestions() {
        requestTask?.cancel()
        meaningTask?.cancel()
        guard let context = session.context else { return }
        let resolution = resolution
        let engine = resolution.engine
        let unavailable = resolution.unavailableMessage
        session.engine = engine
        session.isFallback = resolution.isFallback
        session.model = displayName(for: engine)
        session.meaning = nil
        session.meaningCache = [:]
        session.selectedIndex = 0
        if let unavailable {
            session.phase = .failed(unavailable)
            return
        }
        session.phase = .loading
        let started = Date()
        session.startedAt = started
        let request = settings.makeRequest()
        let provider = provider(for: engine)
        requestTask = Task { [session, status] in
            do {
                let words = try await provider.suggestions(for: context, request: request)
                guard !Task.isCancelled else { return }
                status.lastLatency = Date().timeIntervalSince(started)
                DebugLog.write("suggestions engine=\(engine.rawValue) count=\(words.count) latency=\(String(format: "%.2f", Date().timeIntervalSince(started)))")
                session.phase = words.isEmpty ? .failed("No suggestions came back. Try again.") : .loaded(words)
                if let first = words.first {
                    NSAccessibility.post(
                        element: NSApp as Any,
                        notification: .announcementRequested,
                        userInfo: [.announcement: "\(words.count) suggestions. First: \(first)", .priority: NSAccessibilityPriorityLevel.high.rawValue]
                    )
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                DebugLog.write("suggestions engine=\(engine.rawValue) error=\(error.localizedDescription)")
                session.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func showMeaning(language: MeaningLanguage? = nil) {
        guard settings.meaningEnabled, let word = session.selectedWord, let context = session.context else { return }
        if let language { session.meaningLanguage = language }
        meaningTask?.cancel()
        if let cached = session.meaningCache[word] {
            session.meaning = .loaded(cached)
            return
        }
        session.meaning = .loading(word)
        let request = settings.makeRequest()
        let provider = provider(for: session.engine)
        meaningTask = Task { [session] in
            do {
                let meaning = try await provider.meaning(of: word, in: context, request: request)
                guard !Task.isCancelled, session.selectedWord == word, session.isShowingMeaning else { return }
                session.meaningCache[word] = meaning
                session.meaning = .loaded(meaning)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, session.selectedWord == word, session.isShowingMeaning else { return }
                session.meaning = .failed(word, error.localizedDescription)
            }
        }
    }

    private func hideMeaning() {
        meaningTask?.cancel()
        meaningTask = nil
        session.meaning = nil
    }

    private func handle(_ key: PanelKey) {
        let state = PanelState(
            isShowingMeaning: session.isShowingMeaning,
            meaningLanguage: session.meaningLanguage,
            meaningEnabled: settings.meaningEnabled,
            meaningStartsInNative: settings.meaningStartsInNative,
            hasSelection: session.selectedWord != nil,
            hasFailed: { if case .failed = session.phase { return true } else { return false } }(),
            wordCount: session.words.count
        )
        switch PanelNavigator.action(for: key, in: state) {
        case let .moveSelection(delta):
            session.moveSelection(by: delta)
            if session.isShowingMeaning { showMeaning() }
        case let .openMeaning(language):
            showMeaning(language: language)
        case let .setMeaningLanguage(language):
            session.meaningLanguage = language
        case .closeMeaning:
            hideMeaning()
        case .insertSelected:
            if let word = session.selectedWord { insert(word) }
        case let .insert(index):
            insert(session.words[index])
        case .retrySuggestions, .refreshSuggestions:
            fetchSuggestions()
        case .refreshMeaning:
            if let word = session.selectedWord { session.meaningCache[word] = nil }
            showMeaning()
        case .dismiss:
            dismiss()
        case .none:
            break
        }
    }

    private func insert(_ word: String) {
        let context = session.context
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            TextInserter.insert(word, after: context)
        }
    }

    private func dismiss() {
        contextTask?.cancel()
        contextTask = nil
        requestTask?.cancel()
        requestTask = nil
        hideMeaning()
        hotkey.isPanelActive = false
        panel.hide()
        session.phase = .idle
    }
    private func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, status: status))
            let window = NSWindow(contentViewController: host)
            window.title = "NextWord Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
