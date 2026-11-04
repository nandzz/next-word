import AppKit
import SwiftUI

enum PanelPlacement: Equatable {
    case below
    case above
}

struct SuggestionPanelView: View {
    let session: SuggestionSession
    let settings: SettingsStore
    var status: AppStatus = .shared
    var placement: PanelPlacement = .below
    var presentationID = UUID()
    var animatesEntrance = true
    var onSelect: (String) -> Void = { _ in }
    var onRefresh: () -> Void = {}
    var onClose: () -> Void = {}
    var onSizeChange: (CGSize) -> Void = { _ in }
    var onOpenMeaning: (() -> Void)?
    var onMeaningBack: (() -> Void)?
    var onToggleRewrite: () -> Void = {}
    var onSelectRewrite: (Int) -> Void = { _ in }

    static let maxShortcutRows = 10

    var body: some View {
        PanelChrome(width: panelWidth, placement: placement, animatesEntrance: animatesEntrance) {
            VStack(spacing: 0) {
                PanelHeader(context: session.context, model: modelBadge)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 9)
                Divider().opacity(0.6)
                ZStack(alignment: .top) {
                    if session.isRewriting {
                        rewriteContent
                            .transition(.asymmetric(
                                insertion: .offset(x: 36).combined(with: .opacity),
                                removal: .identity
                            ))
                    } else if let meaning = session.meaning {
                        meaningContent(meaning)
                            .transition(.asymmetric(
                                insertion: .offset(x: 36).combined(with: .opacity),
                                removal: .identity
                            ))
                    } else {
                        content
                            .transition(.asymmetric(
                                insertion: .offset(x: -36).combined(with: .opacity),
                                removal: .identity
                            ))
                    }
                }
                .padding(6)
                .animation(.spring(response: 0.3, dampingFraction: 0.88), value: session.isShowingMeaning)
                .animation(.spring(response: 0.3, dampingFraction: 0.88), value: session.isRewriting)
                Divider().opacity(0.6)
                PanelFooter(
                    mode: footerMode,
                    latency: showsLatency ? status.lastLatency : nil,
                    onRefresh: onRefresh,
                    onClose: onClose,
                    onBack: session.isRewriting ? onToggleRewrite : goBack,
                    onNative: { session.meaningLanguage = .native },
                    onInsert: session.isRewriting ? { onSelectRewrite(session.rewriteIndex) } : insertMeaningWord,
                    onRewrite: onToggleRewrite
                )
            }
        }
        .id(presentationID)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            onSizeChange(size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement == .below ? .top : .bottom)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle, .loading:
            LoadingContent(
                rowCount: min(settings.suggestionCount, Self.maxShortcutRows),
                columns: columns,
                engine: session.engine
            )
        case let .loaded(words) where words.isEmpty:
            MessageContent(
                symbol: "text.magnifyingglass",
                tint: .secondary,
                title: "No suggestions",
                message: "\(engineDisplayName) had nothing to add here.",
                onRetry: onRefresh
            )
        case let .loaded(words):
            SuggestionList(
                words: words,
                columns: columns,
                selectedIndex: session.selectedIndex,
                showsMeaningHint: settings.meaningEnabled,
                onHover: { session.selectedIndex = $0 },
                onSelect: onSelect,
                onOpenMeaning: onOpenMeaning
            )
            .id(words.joined(separator: "\u{1F}"))
        case let .failed(message):
            MessageContent(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Couldn’t get suggestions",
                message: message,
                onRetry: onRefresh
            )
        }
    }

    @ViewBuilder
    private var rewriteContent: some View {
        switch session.rewrite {
        case .loading?, nil:
            RewriteLoadingContent(engine: session.engine)
        case let .loaded(rewrites)?:
            RewriteList(
                rewrites: rewrites,
                scope: session.rewriteTarget?.scope ?? .field,
                selectedIndex: session.rewriteIndex,
                onHover: { session.rewriteIndex = $0 },
                onSelect: onSelectRewrite
            )
            .id(rewrites.map(\.text).joined(separator: "\u{1F}"))
        case let .failed(message)?:
            MessageContent(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Couldn’t rewrite",
                message: message,
                onRetry: onRefresh
            )
        }
    }

    private func meaningContent(_ meaning: MeaningPhase) -> some View {
        MeaningCard(
            phase: meaning,
            language: session.meaningLanguage,
            nativeLanguageName: nativeLanguageName,
            position: session.words.isEmpty ? nil : (session.selectedIndex + 1, session.words.count),
            onSelectLanguage: { session.meaningLanguage = $0 },
            onBack: goBack
        )
    }

    private var footerMode: PanelFooter.Mode {
        if session.isRewriting {
            return .rewrite(canReplace: !session.rewrites.isEmpty)
        }
        guard session.isShowingMeaning else {
            return .list(showsMeaning: settings.meaningEnabled && isLoaded && !session.words.isEmpty)
        }
        return .meaning(nativeLanguageName: session.meaningLanguage == .original ? nativeLanguageName : nil)
    }

    private var nativeLanguageName: String {
        session.nativeLanguageName.isEmpty ? settings.nativeLanguageName : session.nativeLanguageName
    }

    private var meaningWord: String? {
        switch session.meaning {
        case let .loading(word)?: word
        case let .loaded(meaning)?: meaning.word
        case let .failed(word, _)?: word
        case nil: nil
        }
    }

    private func goBack() {
        if let onMeaningBack {
            onMeaningBack()
        } else if session.meaningLanguage == .native {
            session.meaningLanguage = .original
        } else {
            session.meaning = nil
        }
    }

    private func insertMeaningWord() {
        if let word = meaningWord { onSelect(word) }
    }

    private var showsLatency: Bool {
        session.isRewriting ? !session.rewrites.isEmpty : isLoaded && !session.isShowingMeaning
    }

    private var isLoaded: Bool {
        if case .loaded = session.phase { return true }
        return false
    }

    private var isGrid: Bool {
        settings.suggestionCount > Self.maxShortcutRows || session.words.count > Self.maxShortcutRows
    }

    private var columns: Int { isGrid ? 2 : 1 }

    private var panelWidth: CGFloat {
        if session.isRewriting { return 380 }
        return isGrid ? 420 : 300
    }

    private var engineDisplayName: String {
        switch session.engine {
        case .onDevice: "The on-device model"
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    private var modelBadge: ModelBadge {
        switch session.engine {
        case .onDevice:
            return ModelBadge(name: SuggestionEngine.onDevice.title, symbol: SuggestionEngine.onDevice.displaySymbol)
        case .codex:
            let model = settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = model.isEmpty ? SuggestionEngine.codex.title : "Codex · \(model)"
            return ModelBadge(name: name, symbol: SuggestionEngine.codex.displaySymbol)
        case .claude:
            let modelID = session.model.isEmpty ? settings.effectiveModel : session.model
            if let option = ClaudeModelOption.all.first(where: {
                $0.id != ClaudeModelOption.custom && ($0.id == modelID.lowercased() || $0.name == modelID)
            }) {
                return ModelBadge(name: session.isFallback ? "\(option.name) · fallback" : option.name, symbol: option.symbol)
            }
            let custom = ClaudeModelOption.all.first { $0.id == ClaudeModelOption.custom }
            return ModelBadge(name: session.isFallback ? "\(modelID) · fallback" : modelID, symbol: custom?.symbol ?? "cpu")
        }
    }
}

struct ModelBadge: Equatable {
    let name: String
    let symbol: String
}

private struct PanelChrome<Content: View>: View {
    let width: CGFloat
    let placement: PanelPlacement
    let animatesEntrance: Bool
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(VisualEffectBackground(material: .popover))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10),
                    lineWidth: 0.5
                )
            }
            .scaleEffect(appeared || !animatesEntrance ? 1 : 0.965, anchor: placement == .below ? .topLeading : .bottomLeading)
            .onAppear {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { appeared = true }
            }
    }
}

private struct PanelHeader: View {
    let context: TextContext?
    let model: ModelBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                EngineLabel(badge: model)
                Spacer(minLength: 8)
                AppChip(context: context)
            }
            CaretPreview(text: context?.textBeforeCursor ?? "")
        }
    }
}

private struct EngineLabel: View {
    let badge: ModelBadge

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: badge.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.14)))
            Text(badge.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Engine: \(badge.name)")
    }
}

private struct AppChip: View {
    let context: TextContext?

    var body: some View {
        HStack(spacing: 4) {
            Text("in")
                .foregroundStyle(.tertiary)
            appIcon
                .frame(width: 12, height: 12)
            Text(context?.appName ?? "Unknown app")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: 150, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Typing in \(context?.appName ?? "unknown app")")
    }

    @ViewBuilder
    private var appIcon: some View {
        if let image = AppIconCache.icon(forBundleID: context?.bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 10))
                .accessibilityHidden(true)
        }
    }
}

private struct CaretPreview: View {
    let text: String
    private static let previewLength = 40

    var body: some View {
        HStack(spacing: 1) {
            if preview.isEmpty {
                Text("Empty field")
                    .italic()
                    .foregroundStyle(.tertiary)
            } else {
                Text(preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            BlinkingCaret()
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preview.isEmpty ? "Empty text field" : "Text before cursor: \(preview)")
    }

    private var preview: String {
        let flat = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        let trimmedLeading = String(flat.drop(while: \.isWhitespace))
        guard trimmedLeading.count > Self.previewLength else { return trimmedLeading }
        let tail = trimmedLeading.suffix(Self.previewLength)
        let wordStart = tail.firstIndex(of: " ").map { tail.index(after: $0) } ?? tail.startIndex
        return "…" + tail[wordStart...]
    }
}

private struct BlinkingCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { timeline in
            let visible = Int(timeline.date.timeIntervalSinceReferenceDate / 0.53).isMultiple(of: 2)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 2, height: 15)
                .opacity(visible ? 1 : 0.15)
                .animation(.easeInOut(duration: 0.18), value: visible)
        }
        .accessibilityHidden(true)
    }
}

private struct SuggestionList: View {
    let words: [String]
    let columns: Int
    let selectedIndex: Int
    let showsMeaningHint: Bool
    let onHover: (Int) -> Void
    let onSelect: (String) -> Void
    let onOpenMeaning: (() -> Void)?
    @Namespace private var selection

    var body: some View {
        let perColumn = Int((Double(words.count) / Double(columns)).rounded(.up))
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<columns, id: \.self) { column in
                let start = column * perColumn
                let end = min(start + perColumn, words.count)
                VStack(spacing: 1) {
                    if start < end {
                        ForEach(start..<end, id: \.self) { index in
                            SuggestionRow(
                                index: index,
                                word: words[index],
                                isSelected: index == selectedIndex,
                                showsMeaningHint: showsMeaningHint,
                                selection: selection,
                                appearDelay: Double(index) * 0.022,
                                onOpenMeaning: onOpenMeaning
                            )
                            .onHover { if $0 { onHover(index) } }
                            .onTapGesture { onSelect(words[index]) }
                            .accessibilityAction { onSelect(words[index]) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: selectedIndex)
    }
}

private struct SuggestionRow: View {
    let index: Int
    let word: String
    let isSelected: Bool
    let showsMeaningHint: Bool
    let selection: Namespace.ID
    let appearDelay: Double
    let onOpenMeaning: (() -> Void)?
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            if let shortcut {
                KeyCap(label: shortcut, highlighted: isSelected)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            Text(word)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isSelected {
                trailingHint
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    }
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2).delay(appearDelay)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var trailingHint: some View {
        if showsMeaningHint {
            Button {
                onOpenMeaning?()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(onOpenMeaning != nil)
            .help("Show meaning (→)")
            .accessibilityHidden(true)
        } else {
            Image(systemName: "return")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityHintText: String {
        let insert = shortcut.map { "Press \($0) to insert" } ?? "Insert this word"
        return showsMeaningHint ? "\(insert). Press right arrow to see the meaning" : insert
    }

    private var shortcut: String? {
        guard index < SuggestionPanelView.maxShortcutRows else { return nil }
        return index == 9 ? "0" : String(index + 1)
    }
}

private struct LoadingContent: View {
    let rowCount: Int
    let columns: Int
    let engine: SuggestionEngine
    private static let widths: [CGFloat] = [92, 64, 118, 78, 104, 56, 88, 122, 70, 96]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: engine == .claude ? "sparkles" : engine.displaySymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse)
                Text(loadingTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 2)
            placeholders
                .shimmering()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loadingTitle)
    }

    private var loadingTitle: String {
        switch engine {
        case .onDevice: "Thinking on this Mac…"
        case .claude: "Asking Claude…"
        case .codex: "Asking Codex…"
        }
    }

    private var placeholders: some View {
        let count = max(rowCount, 1)
        let perColumn = Int((Double(count) / Double(columns)).rounded(.up))
        return HStack(alignment: .top, spacing: 4) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(spacing: 1) {
                    ForEach(0..<perColumn, id: \.self) { row in
                        let index = column * perColumn + row
                        if index < count {
                            PlaceholderRow(width: Self.widths[index % Self.widths.count])
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

private struct PlaceholderRow: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.09))
                .frame(width: width, height: 11)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }
}

private struct RewriteList: View {
    let rewrites: [Rewrite]
    let scope: RewriteScope
    let selectedIndex: Int
    let onHover: (Int) -> Void
    let onSelect: (Int) -> Void
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(scope == .selection ? "Replaces the selected text" : "Replaces the whole message")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 3)
            ForEach(rewrites.indices, id: \.self) { index in
                RewriteRow(
                    index: index,
                    rewrite: rewrites[index],
                    isSelected: index == selectedIndex,
                    selection: selection,
                    appearDelay: Double(index) * 0.04
                )
                .onHover { if $0 { onHover(index) } }
                .onTapGesture { onSelect(index) }
                .accessibilityAction { onSelect(index) }
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: selectedIndex)
    }
}

private struct RewriteRow: View {
    let index: Int
    let rewrite: Rewrite
    let isSelected: Bool
    let selection: Namespace.ID
    let appearDelay: Double
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KeyCap(label: String(index + 1), highlighted: isSelected)
            VStack(alignment: .leading, spacing: 3) {
                Text(rewrite.style.title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                Text(rewrite.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Image(systemName: "return")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    }
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2).delay(appearDelay)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rewrite.style.title): \(rewrite.text)")
        .accessibilityHint("Press \(index + 1) to replace the text")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct RewriteLoadingContent: View {
    let engine: SuggestionEngine
    private static let widths: [[CGFloat]] = [[300, 210], [250, 120], [290, 180]]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: engine == .claude ? "sparkles" : engine.displaySymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse)
                Text(loadingTitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                    .frame(width: 14, height: 14)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 4)
            VStack(spacing: 1) {
                ForEach(Self.widths.indices, id: \.self) { index in
                    placeholder(widths: Self.widths[index])
                }
            }
            .shimmering()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loadingTitle)
    }

    private var loadingTitle: String {
        switch engine {
        case .onDevice: "Rewriting on this Mac…"
        case .claude: "Asking Claude to rewrite…"
        case .codex: "Asking Codex to rewrite…"
        }
    }

    private func placeholder(widths: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 52, height: 7)
                ForEach(widths.indices, id: \.self) { line in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                        .frame(width: widths[line], height: 10)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

private struct MessageContent: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PillButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct PanelFooter: View {
    enum Mode: Equatable {
        case list(showsMeaning: Bool)
        case meaning(nativeLanguageName: String?)
        case rewrite(canReplace: Bool)
    }

    let mode: Mode
    let latency: TimeInterval?
    let onRefresh: () -> Void
    let onClose: () -> Void
    let onBack: () -> Void
    let onNative: () -> Void
    let onInsert: () -> Void
    let onRewrite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                hints(compact: false, refresh: true)
                hints(compact: false, refresh: false)
                hints(compact: true, refresh: false)
            }
            Spacer(minLength: 4)
            if let latency {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                    Text(Self.format(latency))
                        .monospacedDigit()
                }
                .foregroundStyle(.tertiary)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Answered in \(Self.format(latency))")
            }
        }
        .font(.system(size: 10))
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    @ViewBuilder
    private func hints(compact: Bool, refresh: Bool) -> some View {
        HStack(spacing: 10) {
            switch mode {
            case let .list(showsMeaning):
                FooterHint(keys: "↑↓", label: compact ? nil : "navigate")
                FooterHint(keys: "⏎", label: "insert")
                if showsMeaning {
                    FooterHint(keys: "→", label: "meaning")
                }
                Button(action: onRewrite) { FooterHint(keys: "⌘E", label: "rewrite") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rewrite the text")
                if !compact {
                    closeHint
                }
                if refresh {
                    Button(action: onRefresh) { FooterHint(keys: "⌘R", label: "refresh") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Refresh suggestions")
                }
            case let .meaning(nativeLanguageName):
                Button(action: onBack) { FooterHint(keys: "←", label: "back") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                if let nativeLanguageName {
                    Button(action: onNative) { FooterHint(keys: "→", label: nativeLanguageName) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show in \(nativeLanguageName)")
                }
                Button(action: onInsert) { FooterHint(keys: "⏎", label: "insert") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert this word")
                if !compact {
                    closeHint
                }
            case let .rewrite(canReplace):
                if canReplace {
                    FooterHint(keys: "↑↓", label: compact ? nil : "navigate")
                    Button(action: onInsert) { FooterHint(keys: "⏎", label: "replace") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Replace the text")
                }
                Button(action: onBack) { FooterHint(keys: "←", label: "back") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to words")
                if !compact {
                    closeHint
                }
                if refresh {
                    Button(action: onRefresh) { FooterHint(keys: "⌘R", label: "refresh") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Get new rewrites")
                }
            }
        }
        .fixedSize()
    }

    private var closeHint: some View {
        Button(action: onClose) { FooterHint(keys: "esc", label: "close") }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
    }

    private static func format(_ latency: TimeInterval) -> String {
        latency < 1 ? "\(Int(latency * 1000)) ms" : String(format: "%.1f s", latency)
    }
}

private struct FooterHint: View {
    let keys: String
    let label: String?

    var body: some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if let label {
                Text(label)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}
