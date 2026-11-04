import SwiftUI
import UIKit

/// Écran « Conso » en Liquid Glass : budget mensuel, crédit OpenRouter,
/// onglets Aujourd'hui / Mois par modèle et dernière requête.
/// Rafraîchit automatiquement toutes les 10 s tant que l'écran est visible au premier plan.
struct UsageView: View {
    var onOpenSettings: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppSettings.usageURLKey) private var storedUsageURL = AppSettings.defaultUsageURL

    @State private var snapshot: UsageSnapshot?
    @State private var fetchError: UsageFetchError?
    @State private var isInitialLoading = true
    @State private var isRefreshing = false
    @State private var selectedTab: UsagePeriodTab = .today
    @State private var manualRefreshFeedback = 0

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    private var labelColor: Color {
        colorScheme == .dark ? .primary : Color(white: 0.08)
    }

    private var cardGlass: Glass {
        colorScheme == .dark
            ? .regular.tint(Color.white.opacity(0.10))
            : .regular.tint(Color.white.opacity(0.56))
    }

    private var errorBannerGlass: Glass {
        colorScheme == .dark
            ? .regular.tint(Color.red.opacity(0.24))
            : .regular.tint(Color.red.opacity(0.16))
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            if let snapshot {
                dashboardScrollView(snapshot: snapshot)
                    .transition(.opacity)
            } else if isInitialLoading {
                loadingCard
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else if let fetchError {
                unreachableStateCard(error: fetchError)
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            headerBar
        }
        .animation(spring, value: snapshot)
        .animation(spring, value: selectedTab)
        .animation(spring, value: fetchError)
        .animation(spring, value: isInitialLoading)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .sensoryFeedback(.impact(weight: .light), trigger: manualRefreshFeedback)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refresh(manual: false)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    break
                }
                guard !Task.isCancelled, scenePhase == .active else { break }
                await refresh(manual: false)
            }
        }
    }

    // MARK: - En-tête flottant en Liquid Glass

    private var headerBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassIconButton(systemName: "xmark", label: "Fermer") {
                    dismiss()
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if isRefreshing && snapshot != nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    Text("Conso")
                        .font(.headline)
                        .foregroundStyle(labelColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                GlassIconButton(systemName: "arrow.clockwise", label: "Actualiser") {
                    manualRefreshFeedback += 1
                    Task {
                        await refresh(manual: true)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Contenu principal

    private func dashboardScrollView(snapshot: UsageSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let fetchError {
                    inlineErrorBanner(error: fetchError)
                }

                budgetSection(budget: snapshot.budget, fetchedAt: snapshot.fetchedAt)
                openRouterSection(openRouter: snapshot.openRouter)
                modelsSection(period: snapshot.period(for: selectedTab))
                lastRequestSection(lastRequest: snapshot.lastRequest)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .refreshable {
            await refresh(manual: true)
        }
    }

    // MARK: - Bandeau d'alerte discret (si rafraîchissement échoué après un premier chargement)

    private func inlineErrorBanner(error: UsageFetchError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)

            Text((error.errorDescription ?? "Serveur injoignable.").keepingEmojisAttached)
                .font(.footnote.weight(.medium))
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                manualRefreshFeedback += 1
                Task { await refresh(manual: true) }
            } label: {
                Text("Réessayer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(labelColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .glassEffect(cardGlass.interactive(), in: .capsule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(errorBannerGlass, in: .rect(cornerRadius: 18))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    // MARK: - 1. Jauge Budget (spent_usd / monthly_usd + pct)

    private func budgetSection(budget: BudgetUsage, fetchedAt: Date) -> some View {
        let pctValue = budget.displayPercent
        let progress = budget.clampedProgress
        let remaining = max(budget.monthlyUSD - budget.spentUSD, 0)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(gaugeAccentColor(for: pctValue))

                Text("Budget mensuel")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(UsageFormatting.percent(pctValue))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(gaugeAccentColor(for: pctValue))
                    .contentTransition(.numericText(value: pctValue))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(
                        .regular.tint(gaugeAccentColor(for: pctValue).opacity(colorScheme == .dark ? 0.22 : 0.15)),
                        in: .capsule
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(UsageFormatting.usd(budget.spentUSD, maxFractionDigits: 2))
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(labelColor)
                    .contentTransition(.numericText(value: budget.spentUSD))

                Text("/ \(UsageFormatting.usd(budget.monthlyUSD, maxFractionDigits: 2))")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: budget.monthlyUSD))

                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                let totalWidth = max(geo.size.width, 0)
                let filledWidth = progress > 0 ? max(totalWidth * progress, 10) : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
                        .frame(height: 12)

                    if filledWidth > 0 {
                        Capsule()
                            .fill(gaugeGradient(for: pctValue))
                            .frame(width: min(filledWidth, totalWidth), height: 12)
                            .shadow(color: gaugeAccentColor(for: pctValue).opacity(0.35), radius: 5, x: 0, y: 2)
                    }
                }
            }
            .frame(height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Jauge du budget mensuel")
            .accessibilityValue("\(UsageFormatting.usd(budget.spentUSD, maxFractionDigits: 2)) sur \(UsageFormatting.usd(budget.monthlyUSD, maxFractionDigits: 2)), soit \(UsageFormatting.percent(pctValue))")

            HStack {
                Label {
                    Text("Reste \(UsageFormatting.usd(remaining, maxFractionDigits: 2))")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .contentTransition(.numericText(value: remaining))
                } icon: {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                    Text(UsageFormatting.shortTime(fetchedAt))
                        .font(.caption.monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .glassEffect(cardGlass, in: .rect(cornerRadius: 24))
    }

    // MARK: - 2. Crédit OpenRouter (openrouter.limit_remaining)

    private func openRouterSection(openRouter: OpenRouterUsage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .glassEffect(.regular.tint(Theme.accent.opacity(colorScheme == .dark ? 0.24 : 0.14)), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenRouter")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(labelColor)

                Text("Crédit restant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let remaining = openRouter.limitRemaining {
                Text(UsageFormatting.usd(remaining, maxFractionDigits: 2))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(labelColor)
                    .contentTransition(.numericText(value: remaining))
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(cardGlass, in: .rect(cornerRadius: 22))
    }

    // MARK: - 3. Onglets Aujourd'hui / Mois & Modèles

    private func modelsSection(period: UsagePeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Modèles", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                HStack(spacing: 6) {
                    Text("\(UsageFormatting.integer(period.totalCalls)) appels")
                        .contentTransition(.numericText(value: Double(period.totalCalls)))
                    Text("•")
                    Text(UsageFormatting.modelCostUSD(period.totalCostUSD))
                        .contentTransition(.numericText(value: period.totalCostUSD))
                }
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(UsagePeriodTab.allCases) { tab in
                        let isSelected = selectedTab == tab
                        Button {
                            withAnimation(spring) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(tab.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(isSelected ? Color.white : labelColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(
                            isSelected
                                ? .regular.tint(Theme.accent.opacity(0.88)).interactive()
                                : cardGlass.interactive(),
                            in: .capsule
                        )
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(period.models) { entry in
                    modelCard(entry: entry)
                }
            }
        }
    }

    private func modelCard(entry: ModelUsageEntry) -> some View {
        let tint = modelColor(for: entry.key)

        return VStack(spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: entry.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.tint(tint.opacity(colorScheme == .dark ? 0.24 : 0.14)), in: .circle)

                Text(entry.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(labelColor)

                Spacer()

                Text(UsageFormatting.modelCostUSD(entry.costUSD))
                    .font(.callout.monospacedDigit().weight(.bold))
                    .foregroundStyle(entry.costUSD > 0 ? labelColor : .secondary)
                    .contentTransition(.numericText(value: entry.costUSD))
            }

            Divider()
                .overlay(Color.primary.opacity(0.10))

            HStack(spacing: 8) {
                metricColumn(
                    title: "Appels",
                    systemImage: "arrow.left.arrow.right",
                    valueText: UsageFormatting.integer(entry.calls),
                    numericValue: Double(entry.calls)
                )

                metricColumn(
                    title: "Input",
                    systemImage: "arrow.down.circle.fill",
                    valueText: UsageFormatting.integer(entry.input),
                    numericValue: Double(entry.input)
                )

                metricColumn(
                    title: "Output",
                    systemImage: "arrow.up.circle.fill",
                    valueText: UsageFormatting.integer(entry.output),
                    numericValue: Double(entry.output)
                )
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .glassEffect(cardGlass, in: .rect(cornerRadius: 20))
    }

    private func metricColumn(
        title: String,
        systemImage: String,
        valueText: String,
        numericValue: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(valueText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText(value: numericValue))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 4. Dernière requête (last_request : modèle, tâche, heure)

    private func lastRequestSection(lastRequest: LastRequestUsage?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dernière requête", systemImage: "clock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .accessibilityAddTraits(.isHeader)

            if let lastRequest {
                VStack(spacing: 0) {
                    lastRequestRow(
                        label: "Modèle",
                        systemImage: "cpu",
                        value: lastRequest.model,
                        monospaced: false
                    )

                    Divider()
                        .overlay(Color.primary.opacity(0.10))
                        .padding(.leading, 44)

                    lastRequestRow(
                        label: "Tâche",
                        systemImage: "tag.fill",
                        value: lastRequest.task,
                        monospaced: false
                    )

                    Divider()
                        .overlay(Color.primary.opacity(0.10))
                        .padding(.leading, 44)

                    lastRequestRow(
                        label: "Heure",
                        systemImage: "clock.fill",
                        value: lastRequest.formattedTime,
                        monospaced: true
                    )
                }
                .glassEffect(cardGlass, in: .rect(cornerRadius: 22))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Aucune requête enregistrée.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassEffect(cardGlass, in: .rect(cornerRadius: 20))
            }
        }
    }

    private func lastRequestRow(
        label: String,
        systemImage: String,
        value: String,
        monospaced: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(monospaced ? .subheadline.monospacedDigit().weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(labelColor)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - États Chargement & Serveur injoignable

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)

            Text("Chargement de la conso…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(labelColor)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .glassEffect(cardGlass, in: .rect(cornerRadius: 24))
    }

    private func unreachableStateCard(error: UsageFetchError) -> some View {
        let iconName: String = {
            if error.needsSettings { return "key.fill" }
            if error == .noInternet || error == .unreachable { return "wifi.exclamationmark" }
            return "exclamationmark.triangle.fill"
        }()

        return VStack(spacing: 18) {
            Image(systemName: iconName)
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)

            VStack(spacing: 6) {
                Text(error.needsSettings ? "Configuration requise" : "Serveur injoignable")
                    .font(.headline)
                    .foregroundStyle(labelColor)

                Text((error.errorDescription ?? "Le serveur Conso ne répond pas.").keepingEmojisAttached)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    manualRefreshFeedback += 1
                    Task { await refresh(manual: true) }
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                if error.suggestsTailscale {
                    Button(action: openTailscale) {
                        Label("Ouvrir Tailscale", systemImage: "network")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(labelColor)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(cardGlass.interactive(), in: .capsule)
                }

                if error.needsSettings, let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Label("Ouvrir les Réglages", systemImage: "gearshape")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(labelColor)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(cardGlass.interactive(), in: .capsule)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 380)
        .glassEffect(cardGlass, in: .rect(cornerRadius: 26))
    }

    // MARK: - Couleurs & Actions

    private func gaugeAccentColor(for percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return Theme.accent
    }

    private func gaugeGradient(for percent: Double) -> LinearGradient {
        let colors: [Color]
        if percent >= 90 {
            colors = [.orange, .red]
        } else if percent >= 75 {
            colors = [.yellow, .orange]
        } else {
            colors = [Theme.accent, .purple]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private func modelColor(for key: String) -> Color {
        switch key.lowercased() {
        case "grok": return .orange
        case "sonnet": return Theme.accent
        case "haiku": return .teal
        case "other": return .purple
        default: return .blue
        }
    }

    @MainActor
    private func refresh(manual: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        if manual && snapshot == nil {
            isInitialLoading = true
        }
        defer {
            isRefreshing = false
            isInitialLoading = false
        }

        do {
            let fresh = try await UsageAPI.fetchUsage(rawURL: storedUsageURL)
            guard !Task.isCancelled else { return }
            withAnimation(spring) {
                snapshot = fresh
                fetchError = nil
            }
        } catch is CancellationError {
            return
        } catch let error as UsageFetchError {
            guard !Task.isCancelled else { return }
            withAnimation(spring) {
                fetchError = error
            }
        } catch {
            guard !Task.isCancelled else { return }
            withAnimation(spring) {
                fetchError = .unreachable
            }
        }
    }

    private func openTailscale() {
        guard let tailscaleURL = URL(string: "tailscale://") else { return }
        UIApplication.shared.open(tailscaleURL, options: [:]) { opened in
            if !opened, let storeURL = URL(string: "https://apps.apple.com/app/tailscale/id1470499037") {
                UIApplication.shared.open(storeURL)
            }
        }
    }
}

// MARK: - Formatage des nombres (fr-FR, chiffres alignés)

private enum UsageFormatting {
    private static let frenchLocale = Locale(identifier: "fr_FR")

    static func usd(_ amount: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = frenchLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = max(2, maxFractionDigits)
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return "\(formatted)\u{00A0}$"
    }

    static func modelCostUSD(_ amount: Double) -> String {
        let maxDigits = (amount > 0 && amount < 1.0) ? 4 : 2
        return usd(amount, maxFractionDigits: maxDigits)
    }

    static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = frenchLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        return "\(formatted)\u{00A0}%"
    }

    static func integer(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = frenchLocale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(locale: frenchLocale)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }
}

#Preview("Conso — Clair") {
    UsageView()
        .tint(Theme.accent)
}

#Preview("Conso — Sombre") {
    UsageView()
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
}
