import SwiftUI
import SwiftData

/// Écran principal du chat. L'historique est lu et sauvegardé avec SwiftData,
/// et les réponses de Monika arrivent en streaming SSE (ou en mode factice sous DemoMode).
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Message.date) private var messages: [Message]

    @AppStorage(AppSettings.serverURLKey) private var storedServerURL = ""
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue

    @State private var draft = ""
    @State private var isGenerating = false
    @State private var streamingText = ""
    @State private var chatError: MonikaChatError?
    @State private var generationTask: Task<Void, Never>?
    @State private var activeGenerationID: UUID?

    @State private var sendHapticTrigger = 0
    @State private var replyHapticTrigger = 0
    @State private var errorHapticTrigger = 0

    @State private var showSettings = false
    @State private var confirmClear = false
    @FocusState private var composerFocused: Bool

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    init() {
        if DemoMode.showsTypingState {
            _isGenerating = State(initialValue: true)
        } else if DemoMode.showsNetworkError {
            _chatError = State(initialValue: .unreachable)
        }
    }

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

                        if !streamingText.isEmpty {
                            MessageBubble(text: streamingText, isFromUser: false)
                                .id("streamingBubble")
                                .transition(
                                    .scale(scale: 0.92, anchor: .bottomLeading)
                                        .combined(with: .opacity)
                                )
                        }

                        if isGenerating {
                            TypingIndicator(showAvatar: streamingText.isEmpty)
                                .id("typing")
                                .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                        }

                        if let chatError {
                            ChatErrorBubble(
                                error: chatError,
                                onRetry: retryLastMessage,
                                onOpenSettings: { showSettings = true }
                            )
                            .id("errorBubble")
                            .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
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
                    ComposerBar(
                        text: $draft,
                        isFocused: $composerFocused,
                        isGenerating: isGenerating,
                        onSend: send,
                        onStop: stopGeneration
                    )
                    .onSubmit(send)
                }
                .onAppear {
                    applyInitialDemoStateIfNeeded()
                    scrollToBottom(proxy, animated: false)
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(150))
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: isGenerating) {
                    scrollToBottom(proxy, animated: true)
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        scrollToBottom(proxy, animated: true)
                    }
                }
                .onChange(of: chatError) {
                    scrollToBottom(proxy, animated: true)
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        scrollToBottom(proxy, animated: true)
                    }
                }
                .onChange(of: streamingText) {
                    scrollToBottom(proxy, animated: false)
                }
            }
        }
        .task { insertWelcomeIfNeeded() }
        .onDisappear { generationTask?.cancel() }
        .sensoryFeedback(.impact(weight: .light), trigger: sendHapticTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: replyHapticTrigger)
        .sensoryFeedback(.warning, trigger: errorHapticTrigger)
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
            SettingsView()
                .tint(Theme.accent)
                .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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

    // MARK: - Défilement & initialisation

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            if isGenerating {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if chatError != nil {
                proxy.scrollTo("errorBubble", anchor: .bottom)
            } else if !streamingText.isEmpty {
                proxy.scrollTo("streamingBubble", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(spring, action)
        } else {
            action()
        }
    }

    private func applyInitialDemoStateIfNeeded() {
        guard DemoMode.isEnabled else { return }
        if DemoMode.showsTypingState {
            isGenerating = true
        } else if DemoMode.showsNetworkError {
            chatError = .unreachable
        }
    }

    private func insertWelcomeIfNeeded() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<Message>())) ?? 0
        guard count == 0 else { return }
        modelContext.insert(Message.welcome())
        try? modelContext.save()
    }

    // MARK: - Envoi, Streaming & Annulation

    private func send() {
        guard !isGenerating else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        withAnimation(spring) {
            modelContext.insert(Message(text: prompt, role: .user))
            draft = ""
            chatError = nil
        }
        try? modelContext.save()
        sendHapticTrigger += 1

        startAssistantGeneration(fallbackPrompt: prompt)
    }

    private func retryLastMessage() {
        guard !isGenerating else { return }
        let lastPrompt = messages.last(where: { $0.isFromUser })?.text ?? ""
        withAnimation(spring) {
            chatError = nil
        }
        startAssistantGeneration(fallbackPrompt: lastPrompt)
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil

        let partial = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(spring) {
            if !partial.isEmpty {
                modelContext.insert(Message(text: partial, role: .assistant))
            }
            streamingText = ""
            isGenerating = false
        }
        if !partial.isEmpty {
            try? modelContext.save()
        }
    }

    private func startAssistantGeneration(fallbackPrompt: String) {
        generationTask?.cancel()
        let generationID = UUID()
        activeGenerationID = generationID

        let contextPayload = recentContextMessages(limit: 30)
        let serverURLSnapshot = storedServerURL

        withAnimation(spring) {
            streamingText = ""
            chatError = nil
            isGenerating = true
        }

        generationTask = Task {
            if DemoMode.isEnabled {
                await runDemoGeneration(prompt: fallbackPrompt, generationID: generationID)
            } else {
                await runLiveGeneration(
                    serverURL: serverURLSnapshot,
                    messages: contextPayload,
                    generationID: generationID
                )
            }
        }
    }

    private func recentContextMessages(limit: Int) -> [MonikaAPI.PayloadMessage] {
        let descriptor = FetchDescriptor<Message>(sortBy: [SortDescriptor(\.date, order: .forward)])
        let persisted = (try? modelContext.fetch(descriptor)) ?? messages
        return persisted
            .suffix(limit)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { MonikaAPI.PayloadMessage(role: $0.role.rawValue, content: $0.text) }
    }

    private func runLiveGeneration(
        serverURL: String,
        messages: [MonikaAPI.PayloadMessage],
        generationID: UUID
    ) async {
        var accumulated = ""
        do {
            for try await chunk in MonikaAPI.streamChat(rawServerURL: serverURL, messages: messages) {
                guard activeGenerationID == generationID, !Task.isCancelled else { return }
                accumulated += chunk
                streamingText = accumulated
            }

            guard activeGenerationID == generationID, !Task.isCancelled else { return }
            let finalReply = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)

            withAnimation(spring) {
                if !finalReply.isEmpty {
                    modelContext.insert(Message(text: finalReply, role: .assistant))
                }
                streamingText = ""
                isGenerating = false
                activeGenerationID = nil
            }
            try? modelContext.save()
            if !finalReply.isEmpty {
                replyHapticTrigger += 1
            }
        } catch is CancellationError {
            guard activeGenerationID == generationID else { return }
            withAnimation(spring) {
                streamingText = ""
                isGenerating = false
                activeGenerationID = nil
            }
        } catch {
            guard activeGenerationID == generationID else { return }
            let mapped = (error as? MonikaChatError) ?? .unreachable
            withAnimation(spring) {
                streamingText = ""
                isGenerating = false
                chatError = mapped
                activeGenerationID = nil
            }
            errorHapticTrigger += 1
        }
    }

    private func runDemoGeneration(prompt: String, generationID: UUID) async {
        do {
            try await Task.sleep(for: .milliseconds(700))
            guard activeGenerationID == generationID, !Task.isCancelled else { return }

            let fullReply = Message.mockReply(for: prompt)
            let words = fullReply.split(separator: " ", omittingEmptySubsequences: false)
            var built = ""

            for (index, word) in words.enumerated() {
                try Task.checkCancellation()
                guard activeGenerationID == generationID else { return }
                built += (index == 0 ? "" : " ") + String(word)
                streamingText = built
                try await Task.sleep(for: .milliseconds(45))
            }

            guard activeGenerationID == generationID, !Task.isCancelled else { return }
            withAnimation(spring) {
                modelContext.insert(Message(text: fullReply, role: .assistant))
                streamingText = ""
                isGenerating = false
                activeGenerationID = nil
            }
            try? modelContext.save()
            replyHapticTrigger += 1
        } catch {
            guard activeGenerationID == generationID else { return }
            withAnimation(spring) {
                streamingText = ""
                isGenerating = false
                activeGenerationID = nil
            }
        }
    }

    private func clearHistory() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil

        withAnimation(spring) {
            for message in messages {
                modelContext.delete(message)
            }
            streamingText = ""
            isGenerating = false
            chatError = nil
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
