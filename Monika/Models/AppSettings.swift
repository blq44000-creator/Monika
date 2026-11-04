import SwiftUI

/// Clés de réglages non sensibles stockées via @AppStorage.
/// Le jeton d'accès est stocké exclusivement dans le Keychain (KeychainHelper).
enum AppSettings {
    static let serverURLKey = "monika.serverURL"
    static let appearanceKey = "monika.appearance"
}

/// Mode d'apparence de l'application.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var accessibilityID: String {
        switch self {
        case .system: return "appearanceSystemButton"
        case .light: return "appearanceLightButton"
        case .dark: return "appearanceDarkButton"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Résultat du test de connexion au serveur.
enum ServerConnectionResult: Equatable {
    case connected
    case failed(String)

    var isSuccess: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .connected:
            return "✅ Connecté"
        case .failed(let message):
            return "❌ \(message)"
        }
    }
}

/// Construction des URL et test de connexion vers une API compatible OpenAI.
enum ServerEndpoint {
    static func normalizedBaseURL(from raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.lowercased().hasSuffix("/v1") {
            trimmed.removeLast(3)
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = components.host,
              !host.isEmpty,
              components.query == nil,
              components.fragment == nil
        else {
            return nil
        }

        return components.url
    }

    static func modelsURL(from raw: String) -> URL? {
        guard let base = normalizedBaseURL(from: raw) else { return nil }
        return base
            .appendingPathComponent("v1")
            .appendingPathComponent("models")
    }

    static func chatCompletionsURL(from raw: String) -> URL? {
        guard let base = normalizedBaseURL(from: raw) else { return nil }
        return base
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    /// Vérifie la connexion via GET {URL}/v1/models avec Authorization: Bearer {jeton} (timeout 10 s).
    static func testConnection(rawURL: String, token: String) async -> ServerConnectionResult {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            return .failed("Veuillez renseigner l'URL du serveur.")
        }
        guard let url = modelsURL(from: trimmedURL) else {
            return .failed("URL invalide. Exemple : https://exemple.com")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Réponse invalide reçue du serveur.")
            }
            switch http.statusCode {
            case 200...299:
                return .connected
            case 401:
                return .failed("Jeton d'accès invalide ou manquant (401).")
            case 403:
                return .failed("Accès refusé par le serveur (403).")
            case 404:
                return .failed("Point d'entrée /v1/models introuvable (404).")
            case 429:
                return .failed("Trop de requêtes, réessayez plus tard (429).")
            case 500...599:
                return .failed("Erreur interne du serveur (\(http.statusCode)).")
            default:
                return .failed("Réponse inattendue du serveur (\(http.statusCode)).")
            }
        } catch is CancellationError {
            return .failed("Test de connexion annulé.")
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                return .failed("Test de connexion annulé.")
            case .timedOut:
                return .failed("Délai d'attente dépassé (10 s). Serveur injoignable.")
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                if !NetworkMonitor.shared.isConnected {
                    return .failed("Aucune connexion à Internet.")
                }
                return .failed("Connexion interrompue avec le serveur. Réessayez.")
            case .cannotFindHost, .dnsLookupFailed:
                return .failed("Serveur introuvable. Vérifiez l'URL.")
            case .cannotConnectToHost:
                return .failed("Impossible de se connecter au serveur.")
            case .secureConnectionFailed,
                 .serverCertificateUntrusted,
                 .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid:
                return .failed("Connexion sécurisée (TLS/SSL) impossible.")
            case .appTransportSecurityRequiresSecureConnection:
                return .failed("Connexion non chiffrée refusée par iOS (utilisez https://).")
            case .badURL, .unsupportedURL:
                return .failed("URL du serveur invalide.")
            default:
                return .failed("Impossible de joindre le serveur.")
            }
        } catch {
            return .failed("Impossible de joindre le serveur.")
        }
    }
}
