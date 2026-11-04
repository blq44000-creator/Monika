import Foundation

/// Erreurs possibles lors d'une requête de chat vers Monika.
enum MonikaChatError: LocalizedError, Equatable {
    case missingServer
    case invalidServerURL
    case unauthorized
    case forbidden
    case endpointNotFound
    case rateLimited
    case serverError(Int)
    case unreachable
    case timedOut
    case noInternet
    case tlsError
    case atsBlocked
    case emptyResponse
    case streamError

    var errorDescription: String? {
        switch self {
        case .missingServer:
            return "Aucun serveur configuré. Ajoute l'URL de ton serveur dans les réglages."
        case .invalidServerURL:
            return "L'URL du serveur est invalide. Vérifie-la dans les réglages."
        case .unauthorized:
            return "Jeton d'accès refusé (401). Vérifie ton jeton dans les réglages."
        case .forbidden:
            return "Accès refusé par le serveur (403)."
        case .endpointNotFound:
            return "Route /v1/chat/completions introuvable sur ce serveur (404)."
        case .rateLimited:
            return "Trop de requêtes envoyées, réessaie dans un instant (429)."
        case .serverError(let code):
            return "Erreur interne du serveur (\(code))."
        case .unreachable:
            return "Serveur injoignable. Vérifie l'adresse ou l'état du serveur."
        case .timedOut:
            return "Délai d'attente dépassé (120 s). Le serveur met trop de temps à répondre."
        case .noInternet:
            return "Aucune connexion à Internet."
        case .tlsError:
            return "Connexion sécurisée (TLS/SSL) impossible avec ce serveur."
        case .atsBlocked:
            return "Connexion non chiffrée bloquée par iOS (utilise https://)."
        case .emptyResponse:
            return "Le serveur a renvoyé une réponse vide."
        case .streamError:
            return "Le serveur a interrompu la réponse avec une erreur."
        }
    }

    /// Affiche un bouton menant directement aux Réglages lorsque le serveur n'est pas configuré.
    var opensSettings: Bool {
        switch self {
        case .missingServer, .invalidServerURL:
            return true
        default:
            return false
        }
    }
}

/// Client HTTP/SSE pour une API compatible OpenAI (`/v1/chat/completions`).
/// Le jeton d'accès est lu uniquement depuis le Keychain et n'est jamais journalisé.
enum MonikaAPI {
    static let defaultModel = "hermes-agent"
    static let timeoutSeconds: TimeInterval = 120

    struct PayloadMessage: Encodable, Sendable {
        let role: String
        let content: String
    }

    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [PayloadMessage]
        let stream: Bool
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta?
            let message: Delta?
        }
        struct APIErrorPayload: Decodable {
            let message: String?
        }
        let choices: [Choice]?
        let error: APIErrorPayload?
    }

    /// Envoie l'historique récent et diffuse les fragments de texte au fil de l'eau (SSE).
    static func streamChat(
        rawServerURL: String,
        messages: [PayloadMessage],
        model: String = defaultModel
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performStream(
                        rawServerURL: rawServerURL,
                        messages: messages,
                        model: model,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Exécution interne

    private static func performStream(
        rawServerURL: String,
        messages: [PayloadMessage],
        model: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let trimmedURL = rawServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw MonikaChatError.missingServer
        }
        guard let endpointURL = ServerEndpoint.chatCompletionsURL(from: trimmedURL) else {
            throw MonikaChatError.invalidServerURL
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let rawToken = KeychainHelper.read() {
            let trimmedToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedToken.isEmpty {
                request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
            }
        }

        let body = ChatCompletionRequest(model: model, messages: messages, stream: true)
        request.httpBody = try JSONEncoder().encode(body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw mapError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MonikaChatError.unreachable
        }

        guard (200...299).contains(http.statusCode) else {
            throw mapStatusCode(http.statusCode)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/json") {
            var data = Data()
            do {
                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                }
            } catch {
                throw mapError(error)
            }
            if let singleText = decodeSingleContent(from: data), !singleText.isEmpty {
                continuation.yield(singleText)
                return
            }
            throw MonikaChatError.emptyResponse
        }

        var lineBuffer = Data()
        var fallbackJSONData = Data()
        var sawSSELine = false
        var yieldedContent = false

        do {
            for try await byte in bytes {
                try Task.checkCancellation()

                if !sawSSELine && fallbackJSONData.count < 131_072 {
                    fallbackJSONData.append(byte)
                }

                if byte == 0x0A {
                    let reachedDone = try processLine(
                        lineBuffer,
                        sawSSELine: &sawSSELine,
                        yieldedContent: &yieldedContent,
                        continuation: continuation
                    )
                    lineBuffer.removeAll(keepingCapacity: true)
                    if reachedDone {
                        break
                    }
                } else if byte != 0x0D {
                    lineBuffer.append(byte)
                }
            }

            if !lineBuffer.isEmpty {
                _ = try processLine(
                    lineBuffer,
                    sawSSELine: &sawSSELine,
                    yieldedContent: &yieldedContent,
                    continuation: continuation
                )
            }
        } catch {
            throw mapError(error)
        }

        if !sawSSELine,
           let singleText = decodeSingleContent(from: fallbackJSONData),
           !singleText.isEmpty {
            continuation.yield(singleText)
            yieldedContent = true
        }

        if !yieldedContent {
            throw MonikaChatError.emptyResponse
        }
    }

    private static func processLine(
        _ lineData: Data,
        sawSSELine: inout Bool,
        yieldedContent: inout Bool,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws -> Bool {
        let line = String(decoding: lineData, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)

        if line.isEmpty || line.hasPrefix(":") {
            return false
        }

        guard line.hasPrefix("data:") else {
            return false
        }

        sawSSELine = true
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty {
            return false
        }
        if payload == "[DONE]" {
            return true
        }

        guard let jsonData = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData)
        else {
            return false
        }

        if chunk.error != nil {
            throw MonikaChatError.streamError
        }

        if let text = chunk.choices?.first?.delta?.content ?? chunk.choices?.first?.message?.content,
           !text.isEmpty {
            yieldedContent = true
            continuation.yield(text)
        }

        return false
    }

    private static func decodeSingleContent(from data: Data) -> String? {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode(StreamChunk.self, from: data)
        else {
            return nil
        }
        return decoded.choices?.first?.message?.content
            ?? decoded.choices?.first?.delta?.content
    }

    private static func mapStatusCode(_ statusCode: Int) -> MonikaChatError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .endpointNotFound
        case 408, 504:
            return .timedOut
        case 429:
            return .rateLimited
        case 500...599:
            return .serverError(statusCode)
        default:
            return .serverError(statusCode)
        }
    }

    private static func mapError(_ error: Error) -> Error {
        if error is CancellationError {
            return CancellationError()
        }
        if let chatError = error as? MonikaChatError {
            return chatError
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return CancellationError()
            case .timedOut:
                return MonikaChatError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return MonikaChatError.noInternet
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
                return MonikaChatError.unreachable
            case .secureConnectionFailed,
                 .serverCertificateUntrusted,
                 .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid:
                return MonikaChatError.tlsError
            case .appTransportSecurityRequiresSecureConnection:
                return MonikaChatError.atsBlocked
            case .badURL, .unsupportedURL:
                return MonikaChatError.invalidServerURL
            default:
                return MonikaChatError.unreachable
            }
        }
        return MonikaChatError.unreachable
    }
}
