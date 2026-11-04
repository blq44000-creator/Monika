import SwiftUI
import UIKit

/// Bulle de message en verre légèrement teinté.
/// Utilisateur : à droite, teinte accent (+ aperçu photo ou fichier joint). Monika : à gauche, verre neutre.
struct MessageBubble: View {
    let text: String
    let isFromUser: Bool
    let attachmentName: String?
    let attachmentImageData: Data?

    @Environment(\.colorScheme) private var colorScheme

    init(message: Message) {
        self.text = message.text
        self.isFromUser = message.isFromUser
        self.attachmentName = message.attachmentName
        self.attachmentImageData = message.attachmentImageData
    }

    init(
        text: String,
        isFromUser: Bool,
        attachmentName: String? = nil,
        attachmentImageData: Data? = nil
    ) {
        self.text = text
        self.isFromUser = isFromUser
        self.attachmentName = attachmentName
        self.attachmentImageData = attachmentImageData
    }

    private var hasAttachment: Bool {
        attachmentImageData != nil || attachmentName != nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromUser {
                Spacer(minLength: 56)
            } else {
                MonikaAvatar(size: 26)
            }

            if hasAttachment {
                VStack(alignment: .leading, spacing: 8) {
                    if let imageData = attachmentImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 210, maxHeight: 210)
                            .clipShape(.rect(cornerRadius: 14))
                    } else if let attachmentName {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isFromUser ? Color.white.opacity(0.92) : Theme.accent)
                            Text(attachmentName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(textColor)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color.white.opacity(isFromUser ? 0.16 : 0.25),
                            in: .capsule
                        )
                    }

                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text.keepingEmojisAttached)
                            .font(.body)
                            .foregroundStyle(textColor)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(glass, in: .rect(cornerRadius: 20))
            } else {
                Text(text.keepingEmojisAttached)
                    .font(.body)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(glass, in: .rect(cornerRadius: 20))
                    .textSelection(.enabled)
            }

            if !isFromUser {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isFromUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: Text {
        let prefix = isFromUser ? "Moi : " : "Monika : "
        if let attachmentName, text.isEmpty {
            return Text(prefix + attachmentName)
        }
        return Text(prefix) + Text(text)
    }

    private var glass: Glass {
        if isFromUser {
            return .regular.tint(Theme.accent.opacity(0.85))
        }
        // Mode clair : verre plus blanc pour un meilleur contraste du texte.
        return colorScheme == .dark
            ? .regular.tint(Color.white.opacity(0.10))
            : .regular.tint(Color.white.opacity(0.55))
    }

    private var textColor: Color {
        if isFromUser { return .white }
        return colorScheme == .dark ? .primary : Color(white: 0.06)
    }
}

/// Indicateur « Monika écrit… » (3 points animés en Liquid Glass).
struct TypingIndicator: View {
    var showAvatar: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showAvatar {
                MonikaAvatar(size: 26)
            } else {
                Color.clear
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                    .foregroundStyle(Theme.accent)

                Text("Monika écrit…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(colorScheme == .dark ? .secondary : Color(white: 0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(pillGlass, in: .capsule)

            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monika écrit")
        .accessibilityIdentifier("typingIndicator")
    }

    private var pillGlass: Glass {
        colorScheme == .dark
            ? .regular.tint(Color.white.opacity(0.10))
            : .regular.tint(Color.white.opacity(0.55))
    }
}

/// Petite bulle discrète en verre rouge pour les erreurs réseau ou de configuration.
struct ChatErrorBubble: View {
    let error: MonikaChatError
    var onRetry: () -> Void
    var onOpenSettings: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.top, 2)

                Text((error.errorDescription ?? "Une erreur est survenue.").keepingEmojisAttached)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(colorScheme == .dark ? Color.primary : Color(white: 0.10))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if error.opensSettings {
                    Button(action: onOpenSettings) {
                        Label("Réglages", systemImage: "gearshape")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.white : Color(white: 0.12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Réglages")
                    .accessibilityIdentifier("errorSettingsButton")
                }

                Button(action: onRetry) {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color(white: 0.12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("Réessayer")
                .accessibilityIdentifier("retryButton")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(errorGlass, in: .rect(cornerRadius: 18))
        .padding(.leading, 34)
        .padding(.trailing, 24)
    }

    private var errorGlass: Glass {
        colorScheme == .dark
            ? .regular.tint(Color.red.opacity(0.24))
            : .regular.tint(Color.red.opacity(0.18))
    }
}

#Preview {
    ZStack {
        AnimatedBackground()
        VStack(spacing: 10) {
            MessageBubble(message: .welcome())
            MessageBubble(message: Message(text: "Rappelle-moi d'acheter du pain ce soir en rentrant 🥖", role: .user))
            TypingIndicator()
            ChatErrorBubble(error: .unreachable, onRetry: {})
        }
        .padding()
    }
}
