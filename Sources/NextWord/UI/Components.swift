import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

struct KeyCap: View {
    let label: String
    var highlighted = false
    var size: CGFloat = 18

    var body: some View {
        Text(label)
            .font(.system(size: size * 0.58, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(highlighted ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, size * 0.28)
            .frame(minWidth: size, minHeight: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)))
                    .shadow(color: .black.opacity(highlighted ? 0.18 : 0.10), radius: 0, x: 0, y: 0.75)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(Color.primary.opacity(highlighted ? 0 : 0.12), lineWidth: 0.5)
            }
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let detail {
                Text(detail.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

struct StatusDot: View {
    let isOn: Bool
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(isOn ? Color.green : Color.orange)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

extension SuggestionEngine {
    @MainActor private static var symbolCache: [String: Bool] = [:]

    @MainActor
    var displaySymbol: String {
        let exists = Self.symbolCache[symbol] ?? {
            let found = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
            Self.symbolCache[symbol] = found
            return found
        }()
        if exists { return symbol }
        switch self {
        case .onDevice: return "cpu"
        case .claude: return "sparkles"
        case .codex: return "terminal"
        }
    }
}

struct Shimmer: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            TimelineView(.animation) { timeline in
                let period = 1.5
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                GeometryReader { geometry in
                    let band = geometry.size.width * 0.45
                    LinearGradient(
                        colors: [.clear, highlight, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: -band + (geometry.size.width + band) * phase)
                }
            }
            .mask(content)
            .allowsHitTesting(false)
        }
    }

    private var highlight: Color {
        colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.75)
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
    }
}

struct StatusPill: View {
    let isReady: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(isReady ? "Ready" : "Needs setup")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isReady ? "Status: ready" : "Status: needs setup")
    }

    private var tint: Color { isReady ? .green : .orange }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)))
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct HoverRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(isPressed: configuration.isPressed) {
            configuration.label
        }
    }

    private struct HoverRow<Label: View>: View {
        let isPressed: Bool
        @ViewBuilder var label: Label
        @State private var isHovered = false

        var body: some View {
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isPressed ? 0.12 : (isHovered ? 0.07 : 0)))
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

enum AppIconCache {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

struct IBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let midX = rect.midX
        let serif = w * 0.5
        var path = Path()
        path.move(to: CGPoint(x: midX - serif, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: midX, y: rect.minY + h * 0.09),
            control1: CGPoint(x: midX - serif * 0.35, y: rect.minY),
            control2: CGPoint(x: midX, y: rect.minY + h * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: midX + serif, y: rect.minY),
            control1: CGPoint(x: midX, y: rect.minY + h * 0.02),
            control2: CGPoint(x: midX + serif * 0.35, y: rect.minY)
        )
        path.move(to: CGPoint(x: midX, y: rect.minY + h * 0.09))
        path.addLine(to: CGPoint(x: midX, y: rect.maxY - h * 0.09))
        path.move(to: CGPoint(x: midX - serif, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: midX, y: rect.maxY - h * 0.09),
            control1: CGPoint(x: midX - serif * 0.35, y: rect.maxY),
            control2: CGPoint(x: midX, y: rect.maxY - h * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: midX + serif, y: rect.maxY),
            control1: CGPoint(x: midX, y: rect.maxY - h * 0.02),
            control2: CGPoint(x: midX + serif * 0.35, y: rect.maxY)
        )
        return path
    }
}

struct SparkleShape: Shape {
    var innerRatio: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let tips = [
            CGPoint(x: center.x, y: center.y - outer),
            CGPoint(x: center.x + outer, y: center.y),
            CGPoint(x: center.x, y: center.y + outer),
            CGPoint(x: center.x - outer, y: center.y),
        ]
        var path = Path()
        path.move(to: tips[0])
        for index in tips.indices {
            let from = tips[index]
            let to = tips[(index + 1) % tips.count]
            let control = CGPoint(
                x: center.x + (from.x + to.x - 2 * center.x) * inner / outer,
                y: center.y + (from.y + to.y - 2 * center.y) * inner / outer
            )
            path.addQuadCurve(to: to, control: control)
        }
        path.closeSubpath()
        return path
    }
}

struct AppIconView: View {
    var size: CGFloat = 64

    var body: some View {
        let corner = size * 0.225
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.11, blue: 0.45),
                            Color(red: 0.45, green: 0.24, blue: 0.90),
                            Color(red: 1.00, green: 0.48, blue: 0.42),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.28), .clear],
                        center: UnitPoint(x: 0.3, y: 0.0),
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
            VStack(alignment: .leading, spacing: size * 0.07) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.30 - Double(index) * 0.08))
                        .frame(width: size * [0.30, 0.23, 0.17][index], height: size * 0.075)
                }
            }
            .offset(x: size * 0.17, y: size * 0.08)
            IBeamShape()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.2, height: size * 0.56)
                .shadow(color: .white.opacity(0.55), radius: size * 0.05)
                .offset(x: -size * 0.15)
            SparkleShape()
                .fill(.white)
                .frame(width: size * 0.22, height: size * 0.22)
                .shadow(color: .white.opacity(0.6), radius: size * 0.04)
                .offset(x: size * 0.17, y: -size * 0.2)
            SparkleShape()
                .fill(.white.opacity(0.85))
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: size * 0.31, y: -size * 0.3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
