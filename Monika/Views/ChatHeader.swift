import SwiftUI

/// En-tête flottant en verre : menu, identité de Monika, réglages.
struct ChatHeader: View {
    var onClearHistory: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Menu {
                    Button(action: onSettings) {
                        Label("Réglages", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("menuSettingsButton")

                    Divider()

                    Button(role: .destructive, action: onClearHistory) {
                        Label("Effacer l'historique", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Menu")
                .accessibilityIdentifier("menuButton")

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

                GlassIconButton(systemName: "gearshape", label: "Ouvrir les réglages", action: onSettings)
                    .accessibilityIdentifier("headerSettingsButton")
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

/// Avatar de Monika : pastille en dégradé + SF Symbol.
struct MonikaAvatar: View {
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.pink, .purple, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack(alignment: .top) {
        AnimatedBackground()
        ChatHeader()
    }
}
