import SwiftUI

/// Écran principal du chat (étape 1 : messages factices).
struct ChatView: View {
    @State private var messages: [ChatMessage] = ChatMessage.samples
    @State private var draft = ""
    @State private var isTyping = false
    @State private var sendCount = 0
    @State private var showSettings = false
    @FocusState private var composerFocused: Bool

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        DayLabel(text: "Aujourd'hui")

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .bottom)
                                            .combined(with: .scale(scale: 0.85, anchor: message.role == .user ? .bottomTrailing : .bottomLeading))
                                            .combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                        }

                        if isTyping {
                            TypingIndicator()
                                .id("typing")
                                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .safeAreaInset(edge: .top, spacing: 0) {
                    ChatHeader(onSettings: { showSettings = true })
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerBar(text: $draft, isFocused: $composerFocused, onSend: send)
                        .onSubmit(send)
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: isTyping) {
                    scrollToBottom(proxy)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sendCount)
        .sheet(isPresented: $showSettings) {
            SettingsPlaceholder()
                .presentationDetents([.medium])
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(spring) {
            if isTyping {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        withAnimation(spring) {
            messages.append(ChatMessage(role: .user, text: prompt))
            draft = ""
        }
        sendCount += 1

        // Réponse factice (le vrai réseau arrive à l'étape 4).
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(spring) { isTyping = true }
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(spring) {
                isTyping = false
                messages.append(ChatMessage(role: .assistant, text: ChatMessage.mockReply(for: prompt)))
            }
        }
    }
}

/// Petite étiquette de date centrée, en verre.
private struct DayLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .padding(.vertical, 6)
    }
}

/// Écran temporaire — les vrais réglages arrivent à l'étape 3.
private struct SettingsPlaceholder: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text("Réglages")
                .font(.title2.bold())
            Text("L'URL du serveur et le jeton d'accès seront configurables ici prochainement. 🔐")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

#Preview("Clair") {
    ChatView()
        .tint(Theme.accent)
}

#Preview("Sombre") {
    ChatView()
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
