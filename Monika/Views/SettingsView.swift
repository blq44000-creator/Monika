import SwiftUI
import SwiftData

/// Écran Réglages en Liquid Glass : serveur API, écran VNC, suivi Conso, apparence, conversation et version.
struct SettingsView: View {
    var onClearHistory: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppSettings.serverURLKey) private var storedServerURL = ""
    @AppStorage(AppSettings.vncURLKey) private var storedVNCURL = AppSettings.defaultVNCURL
    @AppStorage(AppSettings.usageURLKey) private var storedUsageURL = AppSettings.defaultUsageURL
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isTokenVisible = false

    @State private var vncURL = ""
    @State private var vncPassword = ""
    @State private var isVNCPasswordVisible = false

    @State private var usageURL = ""
    @State private var usageAPIKey = ""
    @State private var isUsageKeyVisible = false

    @State private var isTesting = false
    @State private var connectionResult: ServerConnectionResult?
    @State private var saveError: String?
    @State private var testTask: Task<Void, Never>?
    @State private var confirmClearHistory = false

    @State private var successFeedback = 0
    @State private var errorFeedback = 0

    private let spring = Animation.spring(response: 0.40, dampingFraction: 0.80)

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var cardGlass: Glass {
        colorScheme == .dark
            ? .regular.tint(Color.white.opacity(0.10))
            : .regular.tint(Color.white.opacity(0.55))
    }

    private var destructiveGlass: Glass {
        colorScheme == .dark
            ? .regular.tint(Color.red.opacity(0.22))
            : .regular.tint(Color.red.opacity(0.14))
    }

    private var labelColor: Color {
        colorScheme == .dark ? .primary : Color(white: 0.08)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.7.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "7"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    serverSection
                    screenSection
                    usageSection
                    appearanceSection
                    conversationSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            .safeAreaInset(edge: .top, spacing: 0) {
                headerBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
            }
        }
        .onAppear(perform: loadInitialValues)
        .onDisappear { testTask?.cancel() }
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .sensoryFeedback(.selection, trigger: appearanceRaw)
        .confirmationDialog(
            "Effacer l'historique ?",
            isPresented: $confirmClearHistory,
            titleVisibility: .visible
        ) {
            Button("Effacer l'historique", role: .destructive, action: performClearHistory)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les messages seront supprimés de cet iPhone. Cette action est irréversible.")
        }
    }

    // MARK: - En-tête

    private var headerBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassIconButton(systemName: "xmark", label: "Fermer") {
                    dismiss()
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Réglages")
                        .font(.headline)
                        .foregroundStyle(labelColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Section Serveur

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Serveur", systemImage: "server.rack")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("URL du serveur")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)

                        TextField("https://exemple.com", text: $serverURL)
                            .font(.body)
                            .foregroundStyle(labelColor)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .accessibilityLabel("URL du serveur")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider()
                    .overlay(Color.primary.opacity(0.12))
                    .padding(.leading, 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Jeton d'accès")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)

                        Group {
                            if isTokenVisible {
                                TextField("sk-…", text: $token)
                                    .keyboardType(.asciiCapable)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Jeton d'accès")
                            } else {
                                SecureField("sk-…", text: $token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Jeton d'accès")
                            }
                        }
                        .font(.body)
                        .foregroundStyle(labelColor)

                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                isTokenVisible.toggle()
                            }
                        } label: {
                            Image(systemName: isTokenVisible ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isTokenVisible ? "Masquer le jeton" : "Afficher le jeton")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 11)
                .padding(.bottom, 9)
            }
            .glassEffect(cardGlass, in: .rect(cornerRadius: 22))

            Button(action: runConnectionTest) {
                HStack(spacing: 10) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    Text(isTesting ? "Test en cours…" : "Tester la connexion")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(labelColor)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(isTesting)
            .glassEffect(cardGlass.interactive(), in: .capsule)

            if let result = connectionResult {
                Text(result.displayText.keepingEmojisAttached)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(statusGlass(isSuccess: result.isSuccess), in: .rect(cornerRadius: 16))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            if let saveError {
                Text("❌ \(saveError)".keepingEmojisAttached)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(statusGlass(isSuccess: false), in: .rect(cornerRadius: 16))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .onChange(of: serverURL) {
            clearTransientFeedback()
        }
        .onChange(of: token) {
            clearTransientFeedback()
        }
    }

    // MARK: - Section Écran (noVNC / Tailscale)

    private var screenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Écran", systemImage: "desktopcomputer")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("URL noVNC (Tailscale)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "display")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)

                        TextField(AppSettings.defaultVNCURL, text: $vncURL)
                            .font(.body)
                            .foregroundStyle(labelColor)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .accessibilityLabel("URL de l'écran noVNC")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider()
                    .overlay(Color.primary.opacity(0.12))
                    .padding(.leading, 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Mot de passe VNC")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)

                        Group {
                            if isVNCPasswordVisible {
                                TextField("Optionnel", text: $vncPassword)
                                    .keyboardType(.asciiCapable)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Mot de passe VNC")
                            } else {
                                SecureField("Optionnel", text: $vncPassword)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Mot de passe VNC")
                            }
                        }
                        .font(.body)
                        .foregroundStyle(labelColor)

                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                isVNCPasswordVisible.toggle()
                            }
                        } label: {
                            Image(systemName: isVNCPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isVNCPasswordVisible ? "Masquer le mot de passe VNC" : "Afficher le mot de passe VNC")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 11)
                .padding(.bottom, 9)
            }
            .glassEffect(cardGlass, in: .rect(cornerRadius: 22))
        }
        .onChange(of: vncURL) {
            clearTransientFeedback()
        }
        .onChange(of: vncPassword) {
            clearTransientFeedback()
        }
    }

    // MARK: - Section Conso (Tailscale + Keychain)

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Conso", systemImage: "chart.bar.xaxis")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("URL Conso (Tailscale)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "network")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)

                        TextField(AppSettings.defaultUsageURL, text: $usageURL)
                            .font(.body)
                            .foregroundStyle(labelColor)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .accessibilityLabel("URL du serveur Conso")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                Divider()
                    .overlay(Color.primary.opacity(0.12))
                    .padding(.leading, 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Clé serveur (Keychain)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "key.horizontal.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)

                        Group {
                            if isUsageKeyVisible {
                                TextField("Utilise le jeton Serveur si vide", text: $usageAPIKey)
                                    .keyboardType(.asciiCapable)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Clé API du serveur Conso")
                            } else {
                                SecureField("Utilise le jeton Serveur si vide", text: $usageAPIKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Clé API du serveur Conso")
                            }
                        }
                        .font(.body)
                        .foregroundStyle(labelColor)

                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                isUsageKeyVisible.toggle()
                            }
                        } label: {
                            Image(systemName: isUsageKeyVisible ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isUsageKeyVisible ? "Masquer la clé serveur" : "Afficher la clé serveur")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 11)
                .padding(.bottom, 9)
            }
            .glassEffect(cardGlass, in: .rect(cornerRadius: 22))
        }
        .onChange(of: usageURL) {
            clearTransientFeedback()
        }
        .onChange(of: usageAPIKey) {
            clearTransientFeedback()
        }
    }

    // MARK: - Section Apparence

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Apparence", systemImage: "circle.lefthalf.filled")

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(AppAppearance.allCases) { option in
                        let isSelected = selectedAppearance == option
                        Button {
                            withAnimation(spring) {
                                appearanceRaw = option.rawValue
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(isSelected ? Color.white : labelColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .contentShape(.rect(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            isSelected
                                ? .regular.tint(Theme.accent.opacity(0.88)).interactive()
                                : cardGlass.interactive(),
                            in: .rect(cornerRadius: 18)
                        )
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: - Section Conversation

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Conversation", systemImage: "bubble.left.and.bubble.right")

            Button {
                confirmClearHistory = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)

                    Text("Effacer l'historique")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(.rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .glassEffect(destructiveGlass.interactive(), in: .rect(cornerRadius: 20))
            .accessibilityLabel("Effacer l'historique")
        }
    }

    // MARK: - Section À propos

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "À propos", systemImage: "info.circle")

            HStack(spacing: 12) {
                MonikaAvatar(size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Monika")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(labelColor)
                    Text("Version de l'application")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(appVersion)
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .glassEffect(cardGlass, in: .rect(cornerRadius: 20))
        }
    }

    // MARK: - Barre inférieure Enregistrer

    private var saveBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button(action: saveSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                    Text("Enregistrer")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - Helpers & Actions

    private func statusGlass(isSuccess: Bool) -> Glass {
        let baseTint: Color = isSuccess ? .green : .red
        let opacity = colorScheme == .dark ? 0.25 : 0.22
        return .regular.tint(baseTint.opacity(opacity))
    }

    private func loadInitialValues() {
        serverURL = storedServerURL
        token = KeychainHelper.read(account: KeychainHelper.apiTokenAccount) ?? ""
        vncURL = storedVNCURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultVNCURL
            : storedVNCURL
        vncPassword = KeychainHelper.read(account: KeychainHelper.vncPasswordAccount) ?? ""
        usageURL = storedUsageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppSettings.defaultUsageURL
            : storedUsageURL
        usageAPIKey = KeychainHelper.read(account: KeychainHelper.usageAPIKeyAccount) ?? ""
    }

    private func clearTransientFeedback() {
        guard connectionResult != nil || saveError != nil else { return }
        withAnimation(spring) {
            connectionResult = nil
            saveError = nil
        }
    }

    private func performClearHistory() {
        if let onClearHistory {
            onClearHistory()
        } else {
            let descriptor = FetchDescriptor<Message>()
            if let existing = try? modelContext.fetch(descriptor) {
                for message in existing {
                    modelContext.delete(message)
                }
            }
            modelContext.insert(Message.welcome())
            try? modelContext.save()
        }
        successFeedback += 1
        dismiss()
    }

    private func runConnectionTest() {
        testTask?.cancel()
        withAnimation(spring) {
            isTesting = true
            connectionResult = nil
            saveError = nil
        }

        let currentURL = serverURL
        let currentToken = token

        testTask = Task {
            let result = await ServerEndpoint.testConnection(rawURL: currentURL, token: currentToken)
            guard !Task.isCancelled else { return }
            withAnimation(spring) {
                isTesting = false
                connectionResult = result
            }
            if result.isSuccess {
                successFeedback += 1
            } else {
                errorFeedback += 1
            }
        }
    }

    private func saveSettings() {
        let trimmedServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVNCURL = vncURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVNCPassword = vncPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsageURL = usageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsageKey = usageAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmedToken.isEmpty {
                KeychainHelper.delete(account: KeychainHelper.apiTokenAccount)
            } else {
                try KeychainHelper.save(trimmedToken, account: KeychainHelper.apiTokenAccount)
            }

            if trimmedVNCPassword.isEmpty {
                KeychainHelper.delete(account: KeychainHelper.vncPasswordAccount)
            } else {
                try KeychainHelper.save(trimmedVNCPassword, account: KeychainHelper.vncPasswordAccount)
            }

            if trimmedUsageKey.isEmpty {
                KeychainHelper.delete(account: KeychainHelper.usageAPIKeyAccount)
            } else {
                try KeychainHelper.save(trimmedUsageKey, account: KeychainHelper.usageAPIKeyAccount)
            }

            storedServerURL = trimmedServerURL
            storedVNCURL = trimmedVNCURL.isEmpty ? AppSettings.defaultVNCURL : trimmedVNCURL
            storedUsageURL = trimmedUsageURL.isEmpty ? AppSettings.defaultUsageURL : trimmedUsageURL
            saveError = nil
            successFeedback += 1
            MonikaAPI.resetSession(cancelActiveTasks: false)
            dismiss()
        } catch {
            withAnimation(spring) {
                saveError = error.localizedDescription
            }
            errorFeedback += 1
        }
    }
}

/// En-tête discret d'une section de réglages.
private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Réglages — Clair") {
    SettingsView()
        .tint(Theme.accent)
        .modelContainer(for: Message.self, inMemory: true)
}

#Preview("Réglages — Sombre") {
    SettingsView()
        .tint(Theme.accent)
        .modelContainer(for: Message.self, inMemory: true)
        .preferredColorScheme(.dark)
}
