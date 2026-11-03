import AppKit
import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    let status: AppStatus

    init(settings: SettingsStore, status: AppStatus) {
        self.settings = settings
        self.status = status
    }

    @MainActor
    init() {
        self.init(settings: .shared, status: .shared)
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings, status: status)
                .tabItem { Label("General", systemImage: "gearshape") }
            ModelSettingsTab(settings: settings, status: status)
                .tabItem { Label("Engines", systemImage: "cpu") }
            MeaningSettingsTab(settings: settings)
                .tabItem { Label("Meaning", systemImage: "character.book.closed") }
            StyleSettingsTab(settings: settings)
                .tabItem { Label("Style", systemImage: "textformat") }
            PermissionsSettingsTab(status: status)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    let status: AppStatus

    var body: some View {
        Form {
            Section("Engine") {
                HStack(spacing: 8) {
                    ForEach(SuggestionEngine.allCases) { engine in
                        EngineCard(engine: engine, isSelected: settings.engine == engine) {
                            withAnimation(.snappy(duration: 0.2)) { settings.engine = engine }
                        }
                    }
                }
                .padding(.vertical, 2)
                EngineAvailabilityRow(engine: settings.engine, status: status)
                Toggle(isOn: $settings.fallBackToClaude) {
                    Text("Fall back to Claude when the selected engine is unavailable")
                    Text(fallbackDetail)
                }
                .disabled(settings.engine == .claude)
            }

            Section {
                Toggle(isOn: $settings.isEnabled) {
                    Text("Enable NextWord")
                    Text("Long-press ? in any text field to see suggestions.")
                }
            }

            Section("Suggestions") {
                Picker("Number of words", selection: $settings.suggestionCount) {
                    ForEach(SettingsStore.countPresets, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Custom amount") {
                    HStack(spacing: 6) {
                        Text("\(settings.suggestionCount) words")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper("Custom amount", value: $settings.suggestionCount, in: 3...30)
                            .labelsHidden()
                    }
                }
                Toggle(isOn: $settings.allowPhrases) {
                    Text("Suggest short phrases")
                    Text("Allow two- or three-word continuations, not only single words.")
                }
            }

            Section("Trigger") {
                LabeledContent("Long-press duration") {
                    HStack(spacing: 10) {
                        Slider(value: longPressDuration, in: 0.2...1.0)
                            .frame(width: 180)
                        Text(String(format: "%.2f s", settings.longPressDuration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }

            Section {
                LabeledContent("Context length") {
                    HStack(spacing: 10) {
                        Slider(value: contextLength, in: 300...4000)
                            .frame(width: 140)
                        Text("\(settings.contextLength) chars")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Stepper("Context length", value: $settings.contextLength, in: 300...4000, step: 100)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Context")
            } footer: {
                Text("How much text before the cursor NextWord sends to the engine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var fallbackDetail: String {
        if settings.engine == .claude { return "Claude is already the selected engine." }
        return status.claudePath == nil ? "The Claude CLI is not installed, so this has no effect now." : "Your text then goes to Claude (Anthropic) instead of staying on this Mac. The panel shows “fallback” when this happens."
    }

    private var contextLength: Binding<Double> {
        Binding(
            get: { Double(settings.contextLength) },
            set: { settings.contextLength = Int(($0 / 100).rounded()) * 100 }
        )
    }

    private var longPressDuration: Binding<Double> {
        Binding(
            get: { settings.longPressDuration },
            set: { settings.longPressDuration = ($0 / 0.05).rounded() * 0.05 }
        )
    }
}

struct ModelSettingsTab: View {
    @Bindable var settings: SettingsStore
    let status: AppStatus

    var body: some View {
        Form {
            if settings.engine != .claude {
                Section {
                    Label {
                        Text(noteText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Section {
                ForEach(ClaudeModelOption.all) { option in
                    ModelOptionRow(option: option, isSelected: settings.modelID == option.id) {
                        withAnimation(.snappy(duration: 0.2)) { settings.modelID = option.id }
                    }
                }
                if settings.modelID == ClaudeModelOption.custom {
                    LabeledContent("Model name") {
                        TextField("Model name", text: $settings.customModelID, prompt: Text("claude-sonnet-4-5"))
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                    }
                }
            } header: {
                EngineSectionHeader(engine: .claude, title: "Claude model", isActive: settings.engine == .claude)
            }

            Section("Claude CLI") {
                LabeledContent("Detected") {
                    detectedCLI
                }
                LabeledContent("Path override") {
                    HStack(spacing: 6) {
                        TextField("Path override", text: $settings.claudePath, prompt: Text("Automatic"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Browse…", action: browseForCLI)
                    }
                }
                HStack {
                    Button {
                        status.onRefreshClaude()
                    } label: {
                        Label("Re-detect", systemImage: "arrow.clockwise")
                    }
                    .disabled(status.isCheckingClaude)
                    Spacer()
                    ConnectionTestResult(state: status.connectionTest)
                    Button("Test connection") { status.onTestConnection() }
                        .disabled(status.connectionTest == .running)
                }
            }

            Section {
                LabeledContent("Detected") {
                    detectedCodex
                }
                LabeledContent("Path override") {
                    HStack(spacing: 6) {
                        TextField("Path override", text: $settings.codexPath, prompt: Text("Automatic"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Browse…") {
                            browse(title: "Choose the Codex CLI") {
                                settings.codexPath = $0
                                status.onRefreshCodex()
                            }
                        }
                    }
                }
                LabeledContent("Model") {
                    TextField("Model", text: $settings.codexModel, prompt: Text("Default (from Codex config)"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .font(.system(size: 12, design: .monospaced))
                }
                HStack {
                    Button {
                        status.onRefreshCodex()
                    } label: {
                        Label("Re-detect", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                }
            } header: {
                EngineSectionHeader(engine: .codex, title: "Codex CLI", isActive: settings.engine == .codex)
            }

            Section("Requests") {
                LabeledContent("Request timeout") {
                    HStack(spacing: 6) {
                        Text("\(Int(settings.requestTimeout)) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper("Request timeout", value: $settings.requestTimeout, in: 5...120, step: 5)
                            .labelsHidden()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var noteText: String {
        switch settings.engine {
        case .onDevice, .codex: "Claude is used when the engine is Claude, or as a fallback. Codex is used when the engine is Codex."
        case .claude: ""
        }
    }

    @ViewBuilder
    private var detectedCodex: some View {
        if let path = status.codexPath {
            VStack(alignment: .trailing, spacing: 2) {
                Label {
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let version = status.codexVersion {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Label("Not found", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("Install with `npm i -g @openai/codex`, then run `codex login`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var detectedCLI: some View {
        if status.isCheckingClaude {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Looking…").foregroundStyle(.secondary)
            }
        } else if let path = status.claudePath {
            VStack(alignment: .trailing, spacing: 2) {
                Label {
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let version = status.claudeVersion {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("Not found", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func browseForCLI() {
        browse(title: "Choose the Claude CLI") {
            settings.claudePath = $0
            status.onRefreshClaude()
        }
    }

    private func browse(title: String, onChoose: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(url.path)
        }
    }
}

private struct EngineSectionHeader: View {
    let engine: SuggestionEngine
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: engine.displaySymbol)
            Text(title)
            if isActive {
                Text("In use")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
        }
    }
}

private struct EngineCard: View {
    let engine: SuggestionEngine
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Image(systemName: engine.displaySymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                        }
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                }
                Text(engine.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(engine.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035)))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.10),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(engine.title). \(engine.detail)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct EngineAvailabilityRow: View {
    let engine: SuggestionEngine
    let status: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatusDot(isOn: isAvailable, size: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Check again", action: refresh)
                    .disabled(engine == .claude && status.isCheckingClaude)
            }
            if engine == .onDevice, !status.onDeviceAvailable {
                HStack {
                    Spacer()
                    Button("Open Apple Intelligence Settings…") { status.onOpenAppleIntelligenceSettings() }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isAvailable: Bool {
        switch engine {
        case .onDevice: status.onDeviceAvailable
        case .claude: status.claudePath != nil
        case .codex: status.codexPath != nil
        }
    }

    private var title: String {
        switch engine {
        case .onDevice: "On-device model"
        case .claude: "Claude CLI"
        case .codex: "Codex CLI"
        }
    }

    private var message: String {
        switch engine {
        case .onDevice:
            return status.onDeviceMessage
        case .claude:
            if status.isCheckingClaude { return "Looking for the CLI…" }
            return Self.describe(path: status.claudePath, version: status.claudeVersion) ?? "Not found. See the Engines tab."
        case .codex:
            return Self.describe(path: status.codexPath, version: status.codexVersion) ?? "Not found. See the Engines tab."
        }
    }

    private func refresh() {
        switch engine {
        case .onDevice: status.onRefreshOnDevice()
        case .claude: status.onRefreshClaude()
        case .codex: status.onRefreshCodex()
        }
    }

    private static func describe(path: String?, version: String?) -> String? {
        guard let path else { return nil }
        let short = (path as NSString).abbreviatingWithTildeInPath
        return version.map { "\(short) · \($0)" } ?? short
    }
}

struct MeaningSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var previewLanguage: MeaningLanguage = .original

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.meaningEnabled) {
                    Text("Show meaning with →")
                    Text("In the suggestions, press → to see what the selected word means.")
                }
            }

            Section("Meaning") {
                Picker("My language", selection: $settings.nativeLanguageCode) {
                    ForEach(languageCodes, id: \.self) { code in
                        Text(label(for: code)).tag(code)
                    }
                }
                Toggle("Open meanings in my language first", isOn: $settings.meaningStartsInNative)
                Toggle("Include an example sentence", isOn: $settings.includeExample)
            }
            .disabled(!settings.meaningEnabled)

            Section {
                MeaningPreview(
                    meaning: MeaningSample.meaning(
                        languageCode: settings.nativeLanguageCode,
                        languageName: settings.nativeLanguageName,
                        includeExample: settings.includeExample
                    ),
                    language: $previewLanguage
                )
                .opacity(settings.meaningEnabled ? 1 : 0.5)
            } header: {
                Text("Preview")
            } footer: {
                Text("Press → again to switch to \(settings.nativeLanguageName). Press ← to go back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { previewLanguage = settings.meaningStartsInNative ? .native : .original }
        .onChange(of: settings.meaningStartsInNative) { _, startsInNative in
            withAnimation(.snappy(duration: 0.22)) { previewLanguage = startsInNative ? .native : .original }
        }
    }

    private var languageCodes: [String] {
        var codes = SettingsStore.languageOptions
        for code in [SettingsStore.systemLanguageCode, settings.nativeLanguageCode] where !codes.contains(code) {
            codes.append(code)
        }
        return codes.sorted { SettingsStore.languageName(for: $0) < SettingsStore.languageName(for: $1) }
    }

    private func label(for code: String) -> String {
        let name = SettingsStore.languageName(for: code)
        return code == SettingsStore.systemLanguageCode ? "\(name) (System)" : name
    }
}

private struct MeaningPreview: View {
    let meaning: WordMeaning
    @Binding var language: MeaningLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        MeaningCard(
            phase: .loaded(meaning),
            language: language,
            nativeLanguageName: meaning.nativeLanguage,
            onSelectLanguage: { language = $0 },
            onBack: { language = .original }
        )
        .padding(6)
        .frame(width: 300)
        .background(shape.fill(colorScheme == .dark ? Color(white: 0.20) : Color.white))
        .overlay(shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 6, y: 2)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private struct ModelOptionRow: View {
    let option: ClaudeModelOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: option.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(option.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.name). \(option.detail)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ConnectionTestResult: View {
    let state: ConnectionTestState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…").foregroundStyle(.secondary)
            }
        case let .success(message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        case let .failure(message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
        }
    }
}

struct StyleSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Tone", selection: $settings.tone) {
                    ForEach(Tone.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Tone")
            } footer: {
                Text(settings.tone.promptHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Language", text: $settings.language, prompt: Text("Auto-detect"))
            } header: {
                Text("Language")
            } footer: {
                Text("Leave empty to match the language of the text you write.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Extra instructions") {
                TextEditor(text: $settings.extraInstructions)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if settings.extraInstructions.isEmpty {
                            Text("Prefer British spelling. Never suggest emoji.")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Extra instructions")
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionsSettingsTab: View {
    let status: AppStatus

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: status.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, status.accessibilityGranted ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.headline)
                        Text(status.accessibilityGranted ? "Access granted" : "Access required")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !status.accessibilityGranted {
                        Button("Grant Access…") { status.onRequestAccessibility() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Open System Settings") { status.onOpenAccessibilitySettings() }
                }
                .padding(.vertical, 4)
            }

            Section("Why NextWord needs access") {
                ReasonRow(symbol: "hand.tap", text: "Detect when you long-press ? on the keyboard.")
                ReasonRow(symbol: "text.viewfinder", text: "Read the text near the cursor, so the suggestions fit what you write.")
                ReasonRow(symbol: "keyboard", text: "Type the word you choose into the app.")
            }

            Section("Privacy") {
                ReasonRow(
                    symbol: "lock.fill",
                    text: "With the on-device engine, your text stays on this Mac. With Claude or Codex (also when Claude is used as a fallback), NextWord passes the text near the cursor to that CLI, which sends it to Anthropic or OpenAI with your account. NextWord keeps no copy of your text."
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct ReasonRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 14) {
            AppIconView(size: 88)
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text("NextWord")
                    .font(.system(size: 22, weight: .bold))
                Text(versionString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Next-word suggestions in any app.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9) {
                UsageStep(number: 1, text: "Put the cursor in any text field.")
                HStack(spacing: 10) {
                    StepBadge(number: 2)
                    Text("Long-press")
                    KeyCap(label: "⇧", size: 20)
                    KeyCap(label: "?", size: 20)
                }
                UsageStep(number: 3, text: "Pick a word with ↑↓, a number key, or a click.")
                UsageStep(number: 4, text: "Press → to see its meaning. Press ⏎ to insert it.")
            }
            .padding(14)
            .frame(maxWidth: 360, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "Version \(version) (\(build))"
        case let (version?, nil): return "Version \(version)"
        default: return "Development build"
        }
    }
}

private struct UsageStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            StepBadge(number: number)
            Text(text)
        }
    }
}

private struct StepBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.accentColor))
            .accessibilityHidden(true)
    }
}
