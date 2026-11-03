import SwiftUI

struct MenuBarContentView: View {
    @Bindable var settings: SettingsStore
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
        VStack(alignment: .leading, spacing: 14) {
            header
            if !status.isReady || !engineReady {
                setupSection
            }
            suggestionsSection
            engineSection
            if showsClaudeModel {
                modelSection
            }
            HintCard()
            Divider()
                .padding(.horizontal, 2)
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(size: 32)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("NextWord")
                    .font(.system(size: 14, weight: .semibold))
                StatusPill(isReady: status.isReady)
            }
            Spacer()
            Toggle("Enable NextWord", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(settings.isEnabled ? "Turn off suggestions" : "Turn on suggestions")
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Setup")
            GroupedCard {
                ChecklistRow(
                    symbol: "accessibility",
                    title: "Accessibility access",
                    detail: status.accessibilityGranted ? "Granted" : "Needed to read and type text",
                    isDone: status.accessibilityGranted
                ) {
                    Button("Grant…") { status.onRequestAccessibility() }
                        .controlSize(.small)
                }
                Divider().padding(.leading, 38)
                ChecklistRow(
                    symbol: "keyboard",
                    title: "Long-press listener",
                    detail: status.hotkeyActive ? "Active" : "Starts after access is granted",
                    isDone: status.hotkeyActive
                ) {
                    EmptyView()
                }
                Divider().padding(.leading, 38)
                engineChecklistRow
            }
        }
    }

    @ViewBuilder
    private var engineChecklistRow: some View {
        switch settings.engine {
        case .onDevice:
            ChecklistRow(
                symbol: SuggestionEngine.onDevice.displaySymbol,
                title: "On-device model",
                detail: status.onDeviceMessage,
                isDone: status.onDeviceAvailable
            ) {
                Button("Open…") { status.onOpenAppleIntelligenceSettings() }
                    .controlSize(.small)
            }
        case .claude:
            ChecklistRow(
                symbol: "terminal",
                title: "Claude CLI",
                detail: claudeDetail,
                isDone: status.claudePath != nil
            ) {
                if status.isCheckingClaude {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Settings…") { status.onOpenSettings() }
                        .controlSize(.small)
                }
            }
        case .codex:
            ChecklistRow(
                symbol: SuggestionEngine.codex.displaySymbol,
                title: "Codex CLI",
                detail: codexDetail,
                isDone: status.codexPath != nil
            ) {
                Button("Settings…") { status.onOpenSettings() }
                    .controlSize(.small)
            }
        }
    }

    private var engineReady: Bool {
        switch settings.engine {
        case .onDevice: status.onDeviceAvailable
        case .claude: status.claudePath != nil
        case .codex: status.codexPath != nil
        }
    }

    private var showsClaudeModel: Bool {
        settings.engine == .claude || settings.fallBackToClaude
    }

    private var codexDetail: String {
        guard let path = status.codexPath else { return "Not found — open Settings" }
        let shortPath = (path as NSString).abbreviatingWithTildeInPath
        if let version = status.codexVersion { return "\(shortPath) · \(version)" }
        return shortPath
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Engine")
            Picker("Engine", selection: $settings.engine) {
                ForEach(SuggestionEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            Text(engineCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
        }
    }

    private var engineCaption: String {
        if settings.engine == .codex {
            let model = settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !model.isEmpty { return "Codex · \(model)" }
        }
        return settings.engine.detail
    }

    private var claudeDetail: String {
        if status.isCheckingClaude { return "Looking for the CLI…" }
        guard let path = status.claudePath else { return "Not found — open Settings" }
        let shortPath = (path as NSString).abbreviatingWithTildeInPath
        if let version = status.claudeVersion { return "\(shortPath) · \(version)" }
        return shortPath
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Suggestions")
            Picker("Suggestions", selection: $settings.suggestionCount) {
                ForEach(SettingsStore.countPresets, id: \.self) { count in
                    Text("\(count) words").tag(count)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Claude model", detail: settings.engine == .claude ? nil : "Fallback")
            GroupedCard {
                HStack(spacing: 10) {
                    Image(systemName: settings.selectedModelOption.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 1) {
                        Picker("Model", selection: $settings.modelID) {
                            ForEach(ClaudeModelOption.all) { option in
                                Label(option.name, systemImage: option.symbol).tag(option.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                        Text(modelDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.leading, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
            }
            .opacity(settings.engine == .claude ? 1 : 0.6)
        }
    }

    private var modelDetail: String {
        let option = settings.selectedModelOption
        if option.id == ClaudeModelOption.custom {
            return "Using “\(settings.effectiveModel)”"
        }
        return option.detail
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                status.onOpenSettings()
            } label: {
                HStack {
                    Label("Settings…", systemImage: "gearshape")
                    Spacer()
                    Text("⌘,").foregroundStyle(.tertiary)
                }
            }
            .keyboardShortcut(",", modifiers: .command)
            Button {
                status.onQuit()
            } label: {
                HStack {
                    Label("Quit NextWord", systemImage: "power")
                    Spacer()
                    Text("⌘Q").foregroundStyle(.tertiary)
                }
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(HoverRowButtonStyle())
        .font(.system(size: 13))
        .padding(.horizontal, -6)
    }
}

private struct ChecklistRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let isDone: Bool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Done")
            } else {
                accessory
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct HintCard: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
            Text("Long-press")
            HStack(spacing: 3) {
                KeyCap(label: "⇧", size: 20)
                KeyCap(label: "?", size: 20)
            }
            Text("in any text field")
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.09))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Long-press Shift and question mark in any text field")
    }
}
