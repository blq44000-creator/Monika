import SwiftUI

/// En-tête flottant en verre : accès à l'écran distant de Monika, identité centrée et réglages.
struct ChatHeader: View {
    var onOpenScreen: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassIconButton(
                    systemName: "desktopcomputer",
                    label: "Écran de Monika",
                    action: onOpenScreen
                )

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    MonikaAvatar(size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Monika")
                            .font(.headline)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("En ligne")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 16)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                GlassIconButton(
                    systemName: "gearshape",
                    label: "Ouvrir les réglages",
                    action: onSettings
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Bouton rond 44 pt en Liquid Glass interactif.
struct GlassIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// Avatar officiel de Monika : logo détouré en rond avec léger reflet glass et ombre douce.
struct MonikaAvatar: View {
    var size: CGFloat = 32

    var body: some View {
        Image("MonikaAvatar")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.68),
                                Color.white.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
            .shadow(color: Color.purple.opacity(0.28), radius: max(2, size * 0.14), x: 0, y: 2)
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack(alignment: .top) {
        AnimatedBackground()
        ChatHeader()
    }
}
