import SwiftUI

/// Bulle de message en verre légèrement teinté.
/// Utilisateur : à droite, teinte accent. Monika : à gauche, verre neutre.
struct MessageBubble: View {
    let message: Message

    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool { message.isFromUser }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 56)
            } else {
                MonikaAvatar(size: 26)
            }

            Text(message.text.keepingEmojisAttached)
                .font(.body)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(glass, in: .rect(cornerRadius: 20))
                .textSelection(.enabled)

            if !isUser {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isUser ? "Moi : " : "Monika : ") + Text(message.text))
    }

    private var glass: Glass {
        if isUser {
            return .regular.tint(Theme.accent.opacity(0.85))
        }
        // Mode clair : verre plus blanc pour un meilleur contraste du texte.
        return colorScheme == .dark
            ? .regular.tint(Color.white.opacity(0.10))
            : .regular.tint(Color.white.opacity(0.55))
    }

    private var textColor: Color {
        if isUser { return .white }
        return colorScheme == .dark ? .primary : Color(white: 0.06)
    }
}

/// Indicateur « Monika écrit… ».
struct TypingIndicator: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MonikaAvatar(size: 26)
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 38)
                .glassEffect(.regular, in: .capsule)
            Spacer()
        }
        .accessibilityLabel("Monika est en train d'écrire")
    }
}

#Preview {
    ZStack {
        AnimatedBackground()
        VStack(spacing: 10) {
            MessageBubble(message: .welcome())
            MessageBubble(message: Message(text: "Rappelle-moi d'acheter du pain ce soir en rentrant 🥖", role: .user))
            TypingIndicator()
        }
        .padding()
    }
}
