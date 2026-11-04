import SwiftUI
import SwiftData

/// Écran principal du chat. L'historique est lu et sauvegardé avec SwiftData.
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Message.date) private var messages: [Message]

    @State private var draft = ""
    @State private var isTyping = false
    @State private var sendCount = 0
    @State private var showSettings = false
    @State private var confirmClear = false
    @FocusState private var composerFocused: Bool

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(daySections) { section in
                            DayLabel(text: DayLabel.title(for: section.day))

                            ForEach(section.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .bottom)
                                                .combined(with: .scale(scale: 0.85, anchor: message.isFromUser ? .bottomTrailing : .bottomLeading))
                                                .combined(with: .opacity),
                                            removal: .opacity
                                        )
                                    )
                            }
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
                    ChatHeader(
                        onClearHistory: { confirmClear = true },
                        onSettings: { showSettings = true }
                    )
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerBar(text: $draft, isFocused: $composerFocused, onSend: send)
                        .onSubmit(send)
                }
                .onAppear {
                    // Au lancement : se placer directement sur le dernier message.
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: isTyping) {
                    scrollToBottom(proxy)
                }
            }
        }
        .task { insertWelcomeIfNeeded() }
        .sensoryFeedback(.impact(weight: .medium), trigger: sendCount)
        .confirmationDialog(
            "Effacer l'historique ?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Effacer l'historique", role: .destructive, action: clearHistory)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les messages seront supprimés de cet iPhone. Cette action est irréversible.")
        }
        .sheet(isPresented: $showSettings) {
            SettingsPlaceholder()
                .presentationDetents([.medium])
        }
    }

    // MARK: - Regroupement par jour

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        var sections: [DaySection] = []
        for message in messages {
            let day = calendar.startOfDay(for: message.date)
            if let lastIndex = sections.indices.last, sections[lastIndex].day == day {
                sections[lastIndex].messages.append(message)
            } else {
                sections.append(DaySection(day: day, messages: [message]))
            }
        }
        return sections
    }

    // MARK: - Actions

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(spring) {
            if isTyping {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func insertWelcomeIfNeeded() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<Message>())) ?? 0
        guard count == 0 else { return }
        modelContext.insert(Message.welcome())
        try? modelContext.save()
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        withAnimation(spring) {
            modelContext.insert(Message(text: prompt, role: .user))
            draft = ""
        }
        try? modelContext.save()
        sendCount += 1

        // Réponse factice après 1 seconde (le vrai serveur arrive à l'étape 4).
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(spring) { isTyping = true }
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(spring) {
                isTyping = false
                modelContext.insert(Message(text: Message.mockReply(for: prompt), role: .assistant))
            }
            try? modelContext.save()
        }
    }

    private func clearHistory() {
        withAnimation(spring) {
            for message in messages {
                modelContext.delete(message)
            }
            isTyping = false
        }
        try? modelContext.save()
        insertWelcomeIfNeeded()
    }
}

/// Messages d'une même journée.
private struct DaySection: Identifiable {
    let day: Date
    var messages: [Message]
    var id: Date { day }
}

/// Séparateur de date centré, en verre : « Aujourd'hui », « Hier » ou la date.
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
            .accessibilityAddTraits(.isHeader)
    }

    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(day) { return "Hier" }

        let french = Locale(identifier: "fr_FR")
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        let text = sameYear
            ? day.formatted(Date.FormatStyle(locale: french).weekday(.wide).day().month(.wide))
            : day.formatted(Date.FormatStyle(locale: french).day().month(.wide).year())
        return text.prefix(1).uppercased() + text.dropFirst()
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
            Text("L'URL du serveur et le jeton d'accès seront configurables ici prochainement. 🔐".keepingEmojisAttached)
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
        .modelContainer(for: Message.self, inMemory: true)
}

#Preview("Sombre") {
    ChatView()
        .tint(Theme.accent)
        .modelContainer(for: Message.self, inMemory: true)
        .preferredColorScheme(.dark)
}
