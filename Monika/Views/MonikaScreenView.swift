import SwiftUI
import WebKit
import UIKit

/// Vue plein écran affichant le bureau distant noVNC de Monika via Tailscale.
/// Le mot de passe VNC est lu exclusivement dans le Keychain et n'est jamais journalisé.
struct MonikaScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppSettings.vncURLKey) private var storedVNCURL = AppSettings.defaultVNCURL

    @State private var isLoading = true
    @State private var hasFailed = false
    @State private var reloadToken = UUID()

    private let spring = Animation.spring(response: 0.40, dampingFraction: 0.82)

    private var labelColor: Color {
        colorScheme == .dark ? .primary : Color(white: 0.08)
    }

    private var cardGlass: Glass {
        colorScheme == .dark
            ? .regular.tint(Color.white.opacity(0.12))
            : .regular.tint(Color.white.opacity(0.60))
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            VNCWebViewRepresentable(
                rawURL: storedVNCURL,
                reloadToken: reloadToken,
                isLoading: $isLoading,
                hasFailed: $hasFailed
            )
            .opacity(hasFailed ? 0 : 1)
            .allowsHitTesting(!hasFailed)
            .ignoresSafeArea(edges: .bottom)

            if hasFailed {
                unreachableCard
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topFloatingBar
        }
        .animation(spring, value: hasFailed)
        .animation(spring, value: isLoading)
    }

    // MARK: - Barre flottante supérieure en Liquid Glass

    private var topFloatingBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassIconButton(systemName: "xmark", label: "Fermer") {
                    dismiss()
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    Text("Écran de Monika")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(labelColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)

                GlassIconButton(systemName: "arrow.clockwise", label: "Recharger", action: reload)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - Message d'erreur Tailscale en Liquid Glass

    private var unreachableCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)

            Text("Écran injoignable — vérifie que Tailscale est activé sur ton iPhone".keepingEmojisAttached)
                .font(.body.weight(.medium))
                .foregroundStyle(labelColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button(action: openTailscale) {
                    Label("Ouvrir Tailscale", systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Button(action: reload) {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(labelColor)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(cardGlass.interactive(), in: .capsule)
            }
        }
        .padding(24)
        .frame(maxWidth: 380)
        .glassEffect(cardGlass, in: .rect(cornerRadius: 26))
    }

    // MARK: - Actions

    private func reload() {
        hasFailed = false
        isLoading = true
        reloadToken = UUID()
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

// MARK: - Pont UIKit WKWebView (zoom, scroll, tactile et clavier iOS)

private struct VNCWebViewRepresentable: UIViewRepresentable {
    let rawURL: String
    let reloadToken: UUID
    @Binding var isLoading: Bool
    @Binding var hasFailed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.ignoresViewportScaleLimits = true

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.scrollView.bouncesZoom = true
        webView.scrollView.minimumZoomScale = 0.5
        webView.scrollView.maximumZoomScale = 4.0
        webView.scrollView.keyboardDismissMode = .interactive

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.load(rawURL: rawURL, in: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelTimeout()
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: VNCWebViewRepresentable
        var lastReloadToken: UUID?
        private var timeoutTask: Task<Void, Never>?
        private var activeNavigationID: UUID?
        private var timedOutNavigationID: UUID?

        init(parent: VNCWebViewRepresentable) {
            self.parent = parent
        }

        func load(rawURL: String, in webView: WKWebView) {
            cancelTimeout()
            webView.stopLoading()

            let password = KeychainHelper.read(account: KeychainHelper.vncPasswordAccount)
            guard let targetURL = VNCEndpoint.targetURL(rawURL: rawURL, password: password) else {
                Task { @MainActor [weak self] in
                    self?.parent.isLoading = false
                    self?.parent.hasFailed = true
                }
                return
            }

            let navID = UUID()
            activeNavigationID = navID
            timedOutNavigationID = nil

            Task { @MainActor [weak self] in
                self?.parent.isLoading = true
                self?.parent.hasFailed = false
            }

            timeoutTask = Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, self.activeNavigationID == navID else { return }
                self.timedOutNavigationID = navID
                webView?.stopLoading()
                self.parent.isLoading = false
                self.parent.hasFailed = true
            }

            var request = URLRequest(
                url: targetURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 10
            )
            request.httpShouldHandleCookies = true
            webView.load(request)
        }

        func cancelTimeout() {
            timeoutTask?.cancel()
            timeoutTask = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            cancelTimeout()
            parent.isLoading = false
            parent.hasFailed = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleNavigationError(error)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            handleNavigationError(error)
        }

        private func handleNavigationError(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorCancelled,
               timedOutNavigationID != activeNavigationID {
                return
            }
            cancelTimeout()
            parent.isLoading = false
            parent.hasFailed = true
        }
    }
}

#Preview {
    MonikaScreenView()
        .tint(Theme.accent)
}
