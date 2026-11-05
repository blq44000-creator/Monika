import SwiftUI

/// Fond animé doux mettant en valeur l'effet Liquid Glass.
/// Utilise `MeshGradient` sur iOS 18+ / Xcode 16+ et un dégradé auroral fluide sur iOS 17 / Xcode 15.
/// S'adapte au mode clair / sombre et se fige si « Réduire les animations » est activé.
struct AnimatedBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            backgroundLayer(at: t)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func backgroundLayer(at t: Double) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: t),
                colors: colorScheme == .dark ? Self.darkColors : Self.lightColors,
                smoothsColors: true
            )
        } else {
            auroraFallback(at: t)
        }
        #else
        auroraFallback(at: t)
        #endif
    }

    private func auroraFallback(at t: Double) -> some View {
        let palette = colorScheme == .dark ? Self.darkColors : Self.lightColors
        let dx1 = 0.25 + 0.18 * sin(t * 0.33)
        let dy1 = 0.22 + 0.16 * cos(t * 0.27)
        let dx2 = 0.76 + 0.17 * cos(t * 0.29 + 1.1)
        let dy2 = 0.35 + 0.18 * sin(t * 0.23 + 0.6)
        let dx3 = 0.45 + 0.20 * sin(t * 0.21 + 2.2)
        let dy3 = 0.78 + 0.15 * cos(t * 0.31 + 1.7)

        return ZStack {
            LinearGradient(
                colors: [palette[0], palette[4], palette[8]],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [palette[1].opacity(0.85), .clear],
                center: UnitPoint(x: dx1, y: dy1),
                startRadius: 20,
                endRadius: 360
            )

            RadialGradient(
                colors: [palette[5].opacity(0.80), .clear],
                center: UnitPoint(x: dx2, y: dy2),
                startRadius: 20,
                endRadius: 380
            )

            RadialGradient(
                colors: [palette[3].opacity(0.75), .clear],
                center: UnitPoint(x: dx3, y: dy3),
                startRadius: 20,
                endRadius: 360
            )
        }
    }

    #if compiler(>=6.0)
    private static func points(at t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.35)) * 0.18
        let b = Float(cos(t * 0.27)) * 0.18
        let c = Float(sin(t * 0.21 + 1.3)) * 0.12
        return [
            SIMD2(0.0, 0.0), SIMD2(0.5 + c, 0.0), SIMD2(1.0, 0.0),
            SIMD2(0.0, 0.5 + a), SIMD2(0.5 + b, 0.5 - a), SIMD2(1.0, 0.5 + c),
            SIMD2(0.0, 1.0), SIMD2(0.5 - b, 1.0), SIMD2(1.0, 1.0),
        ]
    }
    #endif

    private static let lightColors: [Color] = [
        Color(red: 0.98, green: 0.85, blue: 0.90), Color(red: 0.86, green: 0.84, blue: 1.00), Color(red: 0.80, green: 0.90, blue: 1.00),
        Color(red: 1.00, green: 0.91, blue: 0.82), Color(red: 0.93, green: 0.88, blue: 1.00), Color(red: 0.78, green: 0.95, blue: 0.95),
        Color(red: 0.90, green: 0.86, blue: 1.00), Color(red: 0.82, green: 0.92, blue: 1.00), Color(red: 0.98, green: 0.88, blue: 0.95),
    ]

    private static let darkColors: [Color] = [
        Color(red: 0.10, green: 0.07, blue: 0.22), Color(red: 0.20, green: 0.10, blue: 0.35), Color(red: 0.05, green: 0.12, blue: 0.28),
        Color(red: 0.28, green: 0.08, blue: 0.30), Color(red: 0.12, green: 0.10, blue: 0.30), Color(red: 0.03, green: 0.22, blue: 0.30),
        Color(red: 0.06, green: 0.06, blue: 0.16), Color(red: 0.16, green: 0.08, blue: 0.28), Color(red: 0.08, green: 0.05, blue: 0.18),
    ]
}

#Preview {
    AnimatedBackground()
}
