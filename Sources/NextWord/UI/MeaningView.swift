import SwiftUI

struct MeaningCard: View {
    let phase: MeaningPhase
    let language: MeaningLanguage
    let nativeLanguageName: String
    var position: (index: Int, count: Int)?
    var onSelectLanguage: (MeaningLanguage) -> Void = { _ in }
    var onBack: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topBar
            titleRow
            ZStack(alignment: .topLeading) {
                bodyContent
                    .id(bodyKey)
                    .transition(.blurReplace)
            }
            .animation(.snappy(duration: 0.22), value: language)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                onBack?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to suggestions (←)")
            .accessibilityLabel("Back to suggestions")
            if let position, position.count > 1 {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(position.index) of \(position.count)")
                        .monospacedDigit()
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Word \(position.index) of \(position.count)")
            }
            Spacer(minLength: 8)
            MeaningLanguageSwitch(
                selection: language,
                nativeLanguageName: nativeLanguageName,
                onSelect: onSelectLanguage
            )
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(word)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            partOfSpeechView
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var partOfSpeechView: some View {
        switch phase {
        case .loading:
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 44, height: 15)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .shimmering()
        case let .loaded(meaning):
            if let partOfSpeech = meaning.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines), !partOfSpeech.isEmpty {
                Text(partOfSpeech.lowercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
        case .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch phase {
        case .loading:
            MeaningPlaceholder(language: language)
        case let .loaded(meaning):
            switch language {
            case .original:
                OriginalMeaning(meaning: meaning)
            case .native:
                NativeMeaning(meaning: meaning)
            }
        case let .failed(_, message):
            MeaningFailure(message: message)
        }
    }

    private var bodyKey: String {
        switch phase {
        case .loading: "loading-\(language)"
        case .loaded: "loaded-\(language)"
        case .failed: "failed"
        }
    }

    private var word: String {
        switch phase {
        case let .loading(word): word
        case let .loaded(meaning): meaning.word
        case let .failed(word, _): word
        }
    }
}

private struct OriginalMeaning: View {
    let meaning: WordMeaning

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(meaning.definition)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            if let example = meaning.example?.trimmingCharacters(in: .whitespacesAndNewlines), !example.isEmpty {
                ExampleQuote(text: example)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeMeaning: View {
    let meaning: WordMeaning

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meaning.nativeTranslation)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .fixedSize(horizontal: false, vertical: true)
            if !meaning.nativeDefinition.isEmpty {
                Text(meaning.nativeDefinition)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExampleQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 2)
            Text("“\(text)”")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: \(text)")
    }
}

private struct MeaningFailure: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Couldn’t load the meaning")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct MeaningPlaceholder: View {
    let language: MeaningLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if language == .native {
                bar(height: 14)
                    .frame(width: 120)
                    .padding(.bottom, 3)
            }
            bar(height: 10)
            bar(height: 10)
                .padding(.trailing, 28)
            bar(height: 10)
                .padding(.trailing, 110)
            if language == .original {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 2, height: 14)
                    bar(height: 9)
                        .padding(.trailing, 70)
                }
                .padding(.top, 4)
            }
        }
        .shimmering()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading the meaning")
    }

    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2.5, style: .continuous)
            .fill(Color.primary.opacity(0.09))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

struct MeaningLanguageSwitch: View {
    let selection: MeaningLanguage
    let nativeLanguageName: String
    let onSelect: (MeaningLanguage) -> Void
    @Namespace private var highlight
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            segment(.original, title: "Original")
            segment(.native, title: nativeLanguageName.isEmpty ? "My language" : nativeLanguageName)
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .animation(.snappy(duration: 0.22), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meaning language")
    }

    private func segment(_ language: MeaningLanguage, title: String) -> some View {
        let isSelected = selection == language
        return Button {
            onSelect(language)
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.12), radius: 1, y: 0.5)
                            .matchedGeometryEffect(id: "segment", in: highlight)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

enum MeaningSample {
    static let word = "smoothly"

    static func meaning(languageCode: String, languageName: String, includeExample: Bool) -> WordMeaning {
        let native = translations[languageCode]
        return WordMeaning(
            word: word,
            partOfSpeech: "adverb",
            definition: "In a way that moves or happens without sudden changes, stops, or problems.",
            example: includeExample ? "The meeting went smoothly, and we finished early." : nil,
            nativeLanguage: languageName,
            nativeTranslation: native?.translation ?? "“\(word)” in \(languageName)",
            nativeDefinition: native?.definition ?? "The definition appears here, written in \(languageName)."
        )
    }

    private static let translations: [String: (translation: String, definition: String)] = [
        "pt": ("suavemente, sem problemas", "De forma contínua, sem paragens bruscas nem dificuldades."),
        "it": ("senza intoppi, agevolmente", "In modo continuo, senza interruzioni improvvise né problemi."),
        "es": ("sin problemas, con fluidez", "De manera continua, sin cambios bruscos ni dificultades."),
        "fr": ("en douceur, sans accroc", "D’une manière continue, sans arrêt brusque ni difficulté."),
        "de": ("reibungslos, glatt", "Ohne plötzliche Unterbrechungen oder Probleme."),
        "nl": ("soepel, vlot", "Zonder plotselinge onderbrekingen of problemen."),
        "en": ("smoothly", "Without sudden changes, stops, or problems."),
    ]
}
