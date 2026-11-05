import SwiftUI

#if compiler(<6.2)

/// Compatibilité Liquid Glass pour iOS 17 / iOS 18 (Xcode 15 / 16).
/// Sous Xcode 26 (iOS 26 SDK), les API natives de SwiftUI prennent automatiquement le relais.
struct Glass: Equatable, Sendable {
    var tintColor: Color?
    var isInteractive: Bool

    init(tintColor: Color? = nil, isInteractive: Bool = false) {
        self.tintColor = tintColor
        self.isInteractive = isInteractive
    }

    static let regular = Glass()

    func tint(_ color: Color?) -> Glass {
        var copy = self
        copy.tintColor = color
        return copy
    }

    func interactive(_ isInteractive: Bool = true) -> Glass {
        var copy = self
        copy.isInteractive = isInteractive
        return copy
    }
}

/// Conteneur regroupant des éléments en verre translucide.
struct GlassEffectContainer<Content: View>: View {
    var spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
    }
}

/// Style de bord de défilement compatible iOS 17+.
enum ScrollEdgeEffectStyleCompat: Sendable {
    case automatic
    case soft
    case hard
}

private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let glass: Glass
    let shape: S

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    if let tintColor = glass.tintColor {
                        Rectangle()
                            .fill(tintColor)
                    }
                }
                .clipShape(shape)
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.34 : 0.72),
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

/// Style de bouton principal lumineux compatible avec `.buttonBorderShape` et `.controlSize`.
struct GlassProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.borderedProminent)
            .shadow(color: Theme.accent.opacity(0.30), radius: 8, x: 0, y: 3)
    }
}

extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    static var glassProminent: GlassProminentButtonStyle {
        GlassProminentButtonStyle()
    }
}

extension View {
    func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        modifier(LiquidGlassModifier(glass: glass, shape: shape))
    }

    func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyleCompat?, for edges: Edge.Set = .all) -> some View {
        self
    }
}

#endif
