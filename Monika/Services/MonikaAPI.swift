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
    case connectionLost
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
        case .connectionLost:
            return "La connexion avec le serveur a été interrompue. Réessaie."
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

    // MARK: - Contenu texte et multimodal OpenAI

    struct ContentPart: Encodable, Sendable {
        struct ImageURL: Encodable, Sendable {
            let url: String
        }

        let type: String
        let text: String?
        let imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            if let text {
                try container.encode(text, forKey: .text)
            }
            if let imageURL {
                try container.encode(imageURL, forKey: .imageURL)
            }
        }

        static func textPart(_ value: String) -> ContentPart {
            ContentPart(type: "text", text: value, imageURL: nil)
        }

        static func jpegDataURL(_ data: Data) -> ContentPart {
            let base64 = data.base64EncodedString()
            return ContentPart(
                type: "image_url",
                text: nil,
                imageURL: ImageURL(url: "data:image/jpeg;base64,\(base64)")
            )
        }
    }

    enum MessageContent: Encodable, Sendable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .parts(let items):
                try container.encode(items)
            }
        }
    }

    struct PayloadMessage: Encodable, Sendable {
        let role: String
        let content: MessageContent

        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
        }

        init(role: String, parts: [ContentPart]) {
            self.role = role
            self.content = .parts(parts)
        }
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

    // MARK: - Gestion de l'URLSession (recréée proprement au retour en premier plan)

    private final class SessionPool: @unchecked Sendable {
        static let shared = SessionPool()

        private let lock = NSLock()
        private var currentSession: URLSession

        private init() {
            currentSession = Self.makeSession()
        }

        static func makeSession() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = MonikaAPI.timeoutSeconds
            configuration.timeoutIntervalForResource = 300
            return URLSession(configuration: configuration)
        }

        func session() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return currentSession
        }

        @discardableResult
        func reset(cancelActiveTasks: Bool) -> URLSession {
            lock.lock()
            let previous = currentSession
            let fresh = Self.makeSession()
            currentSession = fresh
            lock.unlock()

            if cancelActiveTasks {
                previous.invalidateAndCancel()
            } else {
                previous.finishTasksAndInvalidate()
            }
            return fresh
        }
    }

    /// Invalide l'URLSession actuelle et en recrée une neuve (`waitsForConnectivity = true`).
    static func resetSession(cancelActiveTasks: Bool = false) {
        _ = SessionPool.shared.reset(cancelActiveTasks: cancelActiveTasks)
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

    // MARK: - Exécution interne & retry silencieux

    private enum StreamAttemptOutcome {
        case success
        case retryable(Error)
        case fatal(Error)
    }

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

        // Retry automatique silencieux 1 fois après 0.5 s sur -1005, -1009, -1001
        for attempt in 0...1 {
            try Task.checkCancellation()

            if !NetworkMonitor.shared.isConnected {
                if attempt == 0 {
                    try await Task.sleep(for: .milliseconds(500))
                    continue
                }
                throw MonikaChatError.noInternet
            }

            let session = SessionPool.shared.session()
            let outcome = await executeSingleAttempt(
                request: request,
                session: session,
                continuation: continuation
            )

            switch outcome {
            case .success:
                return
            case .fatal(let error):
                throw error
            case .retryable(let transientError):
                if attempt == 0 && !Task.isCancelled {
                    _ = SessionPool.shared.reset(cancelActiveTasks: true)
                    try await Task.sleep(for: .milliseconds(500))
                    continue
                }
                throw mapError(transientError)
            }
        }
    }

    private static func executeSingleAttempt(
        request: URLRequest,
        session: URLSession,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async -> StreamAttemptOutcome {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            if isCancellation(error) {
                return .fatal(CancellationError())
            }
            if isRetryableNetworkError(error) {
                return .retryable(error)
            }
            return .fatal(mapError(error))
        }

        guard let http = response as? HTTPURLResponse else {
            return .fatal(MonikaChatError.unreachable)
        }

        guard (200...299).contains(http.statusCode) else {
            return .fatal(mapStatusCode(http.statusCode))
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
                if isCancellation(error) {
                    return .fatal(CancellationError())
                }
                if isRetryableNetworkError(error) {
                    return .retryable(error)
                }
                return .fatal(mapError(error))
            }
            if let singleText = decodeSingleContent(from: data), !singleText.isEmpty {
                continuation.yield(singleText)
                return .success
            }
            return .fatal(MonikaChatError.emptyResponse)
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
            if isCancellation(error) {
                return .fatal(CancellationError())
            }
            if !yieldedContent && isRetryableNetworkError(error) {
                return .retryable(error)
            }
            return .fatal(mapError(error))
        }

        if !sawSSELine,
           let singleText = decodeSingleContent(from: fallbackJSONData),
           !singleText.isEmpty {
            continuation.yield(singleText)
            yieldedContent = true
        }

        if !yieldedContent {
            return .fatal(MonikaChatError.emptyResponse)
        }

        return .success
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

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    private static func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost,     // -1005
             .notConnectedToInternet,    // -1009
             .timedOut:                  // -1001
            return true
        default:
            return false
        }
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
        if isCancellation(error) {
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
                return NetworkMonitor.shared.isConnected
                    ? MonikaChatError.connectionLost
                    : MonikaChatError.noInternet
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
