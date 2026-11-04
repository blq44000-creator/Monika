import SwiftUI

/// Écran Réglages en Liquid Glass : serveur, jeton Keychain, apparence et version.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppSettings.serverURLKey) private var storedServerURL = ""
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isTokenVisible = false
    @State private var isTesting = false
    @State private var connectionResult: ServerConnectionResult?
    @State private var saveError: String?
    @State private var testTask: Task<Void, Never>?

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

    private var labelColor: Color {
        colorScheme == .dark ? .primary : Color(white: 0.08)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "3"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    serverSection
                    appearanceSection
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
    }

    // MARK: - En-tête

    private var headerBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassIconButton(systemName: "xmark", label: "Fermer") {
                    dismiss()
                }
                .accessibilityIdentifier("closeSettingsButton")

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
                            .accessibilityIdentifier("serverURLField")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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
                                    .accessibilityIdentifier("tokenField")
                            } else {
                                SecureField("sk-…", text: $token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Jeton d'accès")
                                    .accessibilityIdentifier("tokenField")
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
                        .accessibilityIdentifier("toggleTokenVisibilityButton")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
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
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(isTesting)
            .glassEffect(cardGlass.interactive(), in: .capsule)
            .accessibilityIdentifier("testConnectionButton")

            if let result = connectionResult {
                Text(result.displayText.keepingEmojisAttached)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(statusGlass(isSuccess: result.isSuccess), in: .rect(cornerRadius: 16))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .accessibilityIdentifier("connectionStatusBanner")
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
                            .padding(.vertical, 12)
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
                        .accessibilityIdentifier(option.accessibilityID)
                    }
                }
            }
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
                    .accessibilityIdentifier("appVersionLabel")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
            .accessibilityIdentifier("saveSettingsButton")
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
        if DemoMode.isEnabled {
            serverURL = storedServerURL.isEmpty ? DemoMode.serverURL : storedServerURL
            token = KeychainHelper.read() ?? DemoMode.placeholderToken
        } else {
            serverURL = storedServerURL
            token = KeychainHelper.read() ?? ""
        }
    }

    private func clearTransientFeedback() {
        guard connectionResult != nil || saveError != nil else { return }
        withAnimation(spring) {
            connectionResult = nil
            saveError = nil
        }
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
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmedToken.isEmpty {
                KeychainHelper.delete()
            } else {
                try KeychainHelper.save(trimmedToken)
            }
            storedServerURL = trimmedURL
            saveError = nil
            successFeedback += 1
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
}

#Preview("Réglages — Sombre") {
    SettingsView()
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
