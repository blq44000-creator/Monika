import SwiftUI

/// Bulle de message en verre légèrement teinté.
/// Utilisateur : à droite, teinte accent. Monika : à gauche, verre neutre.
struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 56)
            } else {
                MonikaAvatar(size: 26)
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(isUser ? Color.white : Color.primary)
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
        isUser
            ? .regular.tint(Theme.accent.opacity(0.85))
            : .regular.tint(Color.white.opacity(0.10))
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
            ForEach(ChatMessage.samples) { MessageBubble(message: $0) }
            TypingIndicator()
        }
        .padding()
    }
}
