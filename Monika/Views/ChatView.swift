import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Écran principal du chat. L'historique est lu et sauvegardé avec SwiftData,
/// et les réponses de Monika arrivent en streaming SSE.
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Message.date) private var messages: [Message]

    @AppStorage(AppSettings.serverURLKey) private var storedServerURL = ""
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue

    @State private var draft = ""
    @State private var isGenerating = false
    @State private var streamingText = ""
    @State private var chatError: MonikaChatError?
    @State private var generationTask: Task<Void, Never>?
    @State private var activeGenerationID: UUID?

    // Protection contre la réinjection tardive de la dictée du clavier iOS
    @State private var lastSentRawText = ""
    @State private var lastSentTrimmedText = ""
    @State private var suppressReinjectionUntil: Date = .distantPast
    @State private var lastFocusLossDate: Date = .distantPast

    // Gestion du cycle arrière-plan / premier plan
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var needsResumeOnActive = false
    @State private var interruptedPartialMessage: Message?
    @State private var fallbackPartialText = ""

    // Pièces jointes (PhotosPicker + Fichiers)
    @State private var pendingAttachment: PendingAttachment?
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var infoAlertMessage: String?

    // Dictée vocale interne (Speech + AVAudioEngine)
    @State private var speechRecognizer = SpeechRecognizer()

    @State private var sendHapticTrigger = 0
    @State private var replyHapticTrigger = 0
    @State private var errorHapticTrigger = 0

    @State private var showSettings = false
    @State private var showUsage = false
    @State private var showMonikaScreen = false
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
                                onOpenSettings: openSettings
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
                        onOpenScreen: openMonikaScreen,
                        onOpenUsage: openUsage,
                        onSettings: openSettings
                    )
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerBar(
                        text: $draft,
                        isFocused: $composerFocused,
                        isGenerating: isGenerating,
                        isRecordingDictation: speechRecognizer.isRecording,
                        pendingAttachment: pendingAttachment,
                        onPickPhoto: { showPhotoPicker = true },
                        onPickFile: { showFileImporter = true },
                        onRemoveAttachment: removePendingAttachment,
                        onToggleDictation: toggleVoiceDictation,
                        onSend: send,
                        onStop: stopGeneration
                    )
                    .onSubmit(send)
                }
                .onAppear {
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
        .onDisappear {
            generationTask?.cancel()
            speechRecognizer.stopRecording()
            endStreamingBackgroundTask()
        }
        .onChange(of: composerFocused) { _, focused in
            if !focused {
                lastFocusLossDate = Date.now
            }
        }
        .onChange(of: draft) { _, newValue in
            guard Date.now < suppressReinjectionUntil else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if trimmed == lastSentTrimmedText || newValue == lastSentRawText {
                draft = ""
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            loadSelectedPhoto(newItem)
        }
        .onChange(of: speechRecognizer.errorMessage) { _, newError in
            if let newError {
                infoAlertMessage = newError
                speechRecognizer.errorMessage = nil
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .utf8PlainText, .text, .sourceCode, .json, .image],
            allowsMultipleSelection: false,
            onCompletion: handleImportedFiles
        )
        .sensoryFeedback(.impact(weight: .light), trigger: sendHapticTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: replyHapticTrigger)
        .sensoryFeedback(.warning, trigger: errorHapticTrigger)
        .alert(
            "Autorisation requise",
            isPresented: Binding(
                get: { speechRecognizer.permissionDeniedMessage != nil },
                set: { if !$0 { speechRecognizer.permissionDeniedMessage = nil } }
            )
        ) {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                speechRecognizer.permissionDeniedMessage = nil
            }
            Button("Annuler", role: .cancel) {
                speechRecognizer.permissionDeniedMessage = nil
            }
        } message: {
            Text(speechRecognizer.permissionDeniedMessage ?? "")
        }
        .alert(
            "Information",
            isPresented: Binding(
                get: { infoAlertMessage != nil },
                set: { if !$0 { infoAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                infoAlertMessage = nil
            }
        } message: {
            Text(infoAlertMessage ?? "")
        }
        .fullScreenCover(isPresented: $showMonikaScreen) {
            MonikaScreenView()
                .tint(Theme.accent)
                .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
        }
        .sheet(isPresented: $showUsage) {
            UsageView(
                onOpenSettings: {
                    showUsage = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showSettings = true
                    }
                }
            )
            .tint(Theme.accent)
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onClearHistory: clearHistory)
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

    private func insertWelcomeIfNeeded() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<Message>())) ?? 0
        guard count == 0 else { return }
        modelContext.insert(Message.welcome())
        try? modelContext.save()
    }

    private func openMonikaScreen() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        composerFocused = false
        showMonikaScreen = true
    }

    private func openUsage() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        composerFocused = false
        showUsage = true
    }

    private func openSettings() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        composerFocused = false
        showSettings = true
    }

    // MARK: - Pièces jointes & Dictée vocale

    private func removePendingAttachment() {
        withAnimation(spring) {
            pendingAttachment = nil
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { selectedPhotoItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    infoAlertMessage = AttachmentError.unreadableImage.localizedDescription
                    return
                }
                let processed = try AttachmentProcessor.processImageData(data, fileName: "Photo.jpg")
                withAnimation(spring) {
                    pendingAttachment = processed
                }
            } catch {
                infoAlertMessage = AttachmentError.unreadableImage.localizedDescription
            }
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            return
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let processed = try AttachmentProcessor.processImportedFile(at: url)
                withAnimation(spring) {
                    pendingAttachment = processed
                }
            } catch {
                infoAlertMessage = error.localizedDescription
            }
        }
    }

    private func toggleVoiceDictation() {
        let startingText = draft
        Task {
            await speechRecognizer.toggleRecording(currentText: startingText) { liveTranscript in
                suppressReinjectionUntil = .distantPast
                draft = liveTranscript
            }
        }
    }

    // MARK: - Envoi, Streaming & Annulation

    private func send() {
        guard !isGenerating else { return }

        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }

        // 1. Copie locale du texte et de la pièce jointe avant de modifier le focus
        let rawDraft = draft
        let trimmedPrompt = rawDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachment = pendingAttachment
        guard !trimmedPrompt.isEmpty || attachment != nil else { return }

        // 2. Mémorise l'état du clavier et arme le filtre anti-réinjection de la dictée iOS
        let keepKeyboardOpen = composerFocused || Date.now.timeIntervalSince(lastFocusLossDate) < 0.25
        lastSentRawText = rawDraft
        lastSentTrimmedText = trimmedPrompt
        suppressReinjectionUntil = Date.now.addingTimeInterval(0.8)

        // 3. Retire immédiatement le focus (termine la dictée du clavier iOS)
        composerFocused = false

        // 4. Vide le champ et insère le message utilisateur
        let message = buildUserMessage(prompt: trimmedPrompt, attachment: attachment)
        withAnimation(spring) {
            modelContext.insert(message)
            draft = ""
            pendingAttachment = nil
            chatError = nil
        }
        try? modelContext.save()
        sendHapticTrigger += 1

        // 5. Revide une seconde fois après ~0.15 s puis remet le focus pour garder le clavier ouvert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            draft = ""
            if keepKeyboardOpen {
                composerFocused = true
            }
        }

        startAssistantGeneration()
    }

    private func buildUserMessage(prompt: String, attachment: PendingAttachment?) -> Message {
        guard let attachment else {
            return Message(text: prompt, role: .user)
        }
        switch attachment.kind {
        case .image(let jpegData, _):
            return Message(
                text: prompt,
                role: .user,
                attachmentName: attachment.fileName,
                attachmentImageData: jpegData,
                attachmentExtractedText: nil
            )
        case .document(let extractedText):
            return Message(
                text: prompt,
                role: .user,
                attachmentName: attachment.fileName,
                attachmentImageData: nil,
                attachmentExtractedText: extractedText
            )
        }
    }

    private func retryLastMessage() {
        guard !isGenerating else { return }
        withAnimation(spring) {
            chatError = nil
        }
        startAssistantGeneration()
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        needsResumeOnActive = false
        interruptedPartialMessage = nil
        fallbackPartialText = ""
        endStreamingBackgroundTask()

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

    private func startAssistantGeneration() {
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
            await runLiveGeneration(
                serverURL: serverURLSnapshot,
                messages: contextPayload,
                generationID: generationID
            )
        }
    }

    private func recentContextMessages(limit: Int) -> [MonikaAPI.PayloadMessage] {
        let descriptor = FetchDescriptor<Message>(sortBy: [SortDescriptor(\.date, order: .forward)])
        let persisted = (try? modelContext.fetch(descriptor)) ?? messages
        let slice = Array(persisted.suffix(limit))

        // Conserve les images base64 sur les messages récents (jusqu'aux 6 dernières images)
        let recentImageIDs = Set(
            slice
                .filter { $0.attachmentImageData != nil }
                .suffix(6)
                .map(\.id)
        )

        return slice.compactMap { message in
            payloadMessage(from: message, includeImageData: recentImageIDs.contains(message.id))
        }
    }

    private func payloadMessage(from message: Message, includeImageData: Bool) -> MonikaAPI.PayloadMessage? {
        let cleanText = message.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if message.isFromUser, let imageData = message.attachmentImageData {
            if includeImageData {
                let promptText = cleanText.isEmpty ? "Voici une image." : cleanText
                return MonikaAPI.PayloadMessage(
                    role: message.role.rawValue,
                    parts: [
                        .textPart(promptText),
                        .jpegDataURL(imageData),
                    ]
                )
            } else {
                let label = message.attachmentName ?? "Photo.jpg"
                let fallback = cleanText.isEmpty ? "[Image jointe : \(label)]" : "\(cleanText)\n[Image jointe : \(label)]"
                return MonikaAPI.PayloadMessage(role: message.role.rawValue, content: fallback)
            }
        }

        if message.isFromUser,
           let extracted = message.attachmentExtractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extracted.isEmpty {
            let fileName = message.attachmentName ?? "Fichier"
            let combined = cleanText.isEmpty
                ? "Voici le contenu du fichier « \(fileName) » :\n\n\(extracted)"
                : "\(cleanText)\n\n---\nContenu du fichier « \(fileName) » :\n\(extracted)"
            return MonikaAPI.PayloadMessage(role: message.role.rawValue, content: combined)
        }

        guard !cleanText.isEmpty else { return nil }
        return MonikaAPI.PayloadMessage(role: message.role.rawValue, content: message.text)
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
            interruptedPartialMessage = nil
            fallbackPartialText = ""
            needsResumeOnActive = false
            endStreamingBackgroundTask()
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
            endStreamingBackgroundTask()
        } catch {
            guard activeGenerationID == generationID else { return }

            // Si iOS coupe la socket pendant que l'app est en arrière-plan, on sauvegarde le partiel et on relancera au retour
            if scenePhase == .background {
                interruptStreamingForBackground(partialOverride: accumulated)
                return
            }

            let mapped = (error as? MonikaChatError) ?? .unreachable
            let recoveredPartial = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedBeforeRetry = fallbackPartialText

            withAnimation(spring) {
                if !recoveredPartial.isEmpty {
                    modelContext.insert(Message(text: recoveredPartial, role: .assistant))
                } else if !savedBeforeRetry.isEmpty {
                    modelContext.insert(Message(text: savedBeforeRetry, role: .assistant))
                }
                streamingText = ""
                isGenerating = false
                chatError = mapped
                activeGenerationID = nil
            }
            fallbackPartialText = ""
            endStreamingBackgroundTask()
            try? modelContext.save()
            errorHapticTrigger += 1
        }
    }

    // MARK: - Cycle arrière-plan / premier plan

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            if speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
            }
            if isGenerating {
                beginStreamingBackgroundTaskIfNeeded()
            }

        case .active:
            endStreamingBackgroundTask()
            MonikaAPI.resetSession(cancelActiveTasks: !isGenerating)

            if needsResumeOnActive && !isGenerating {
                needsResumeOnActive = false
                if let savedPartial = interruptedPartialMessage {
                    modelContext.delete(savedPartial)
                    try? modelContext.save()
                    interruptedPartialMessage = nil
                }
                startAssistantGeneration()
            }

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    private func beginStreamingBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MonikaStreamCompletion") {
            Task { @MainActor in
                interruptStreamingForBackground()
            }
        }
    }

    private func endStreamingBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        let taskToEnd = backgroundTaskID
        backgroundTaskID = .invalid
        UIApplication.shared.endBackgroundTask(taskToEnd)
    }

    private func interruptStreamingForBackground(partialOverride: String? = nil) {
        guard isGenerating || activeGenerationID != nil else {
            endStreamingBackgroundTask()
            return
        }

        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil

        let rawPartial = partialOverride ?? streamingText
        let partial = rawPartial.trimmingCharacters(in: .whitespacesAndNewlines)

        if !partial.isEmpty {
            let saved = Message(text: partial, role: .assistant)
            modelContext.insert(saved)
            try? modelContext.save()
            interruptedPartialMessage = saved
            fallbackPartialText = partial
        }

        streamingText = ""
        isGenerating = false
        chatError = nil
        needsResumeOnActive = true
        endStreamingBackgroundTask()
    }

    // MARK: - Effacement de l'historique

    private func clearHistory() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        needsResumeOnActive = false
        interruptedPartialMessage = nil
        fallbackPartialText = ""
        endStreamingBackgroundTask()

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
