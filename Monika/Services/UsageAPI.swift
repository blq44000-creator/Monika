import Foundation

/// Onglet de période affiché dans l'écran Conso (`today` / `month`).
enum UsagePeriodTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Aujourd'hui"
        case .month: return "Mois"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .month: return "calendar"
        }
    }
}

/// Erreurs possibles lors de l'appel à l'endpoint `/usage`.
enum UsageFetchError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidURL
    case unauthorized
    case forbidden
    case noInternet
    case unreachable
    case serverError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Aucune clé API n'est enregistrée dans le Keychain. Ajoute ta clé serveur dans les Réglages."
        case .invalidURL:
            return "L'URL du serveur Conso est invalide. Vérifie-la dans les Réglages."
        case .unauthorized:
            return "Clé serveur refusée (401). Vérifie ta clé API dans les Réglages."
        case .forbidden:
            return "Accès refusé par le serveur Conso (403)."
        case .noInternet:
            return "Aucune connexion à Internet."
        case .unreachable:
            return "Le serveur Conso ne répond pas — vérifie que Tailscale est activé sur ton iPhone."
        case .serverError(let code):
            return "Le serveur Conso a renvoyé une erreur (\(code))."
        case .decodingFailed:
            return "La réponse reçue du serveur Conso est invalide."
        }
    }

    var needsSettings: Bool {
        switch self {
        case .missingAPIKey, .invalidURL, .unauthorized:
            return true
        default:
            return false
        }
    }

    var suggestsTailscale: Bool {
        switch self {
        case .unreachable:
            return true
        default:
            return false
        }
    }
}

// MARK: - Modèles de données `/usage`

struct BudgetUsage: Equatable, Sendable {
    let spentUSD: Double
    let monthlyUSD: Double
    let pct: Double

    /// Pourcentage affiché (0 à 100+), gérant automatiquement une éventuelle échelle 0..1 ou 0..100.
    var displayPercent: Double {
        if monthlyUSD > 0 {
            let computed = (spentUSD / monthlyUSD) * 100.0
            if pct <= 1.0 && computed > 1.5 && abs(pct * 100.0 - computed) < 1.0 {
                return pct * 100.0
            }
            if pct == 0 && spentUSD > 0 {
                return computed
            }
        }
        return pct
    }

    /// Progression bornée entre 0 et 1 pour le remplissage de la jauge.
    var clampedProgress: Double {
        if monthlyUSD > 0 {
            return min(max(spentUSD / monthlyUSD, 0.0), 1.0)
        }
        return min(max(displayPercent / 100.0, 0.0), 1.0)
    }
}

struct OpenRouterUsage: Equatable, Sendable {
    let limitRemaining: Double?
}

struct ModelUsageEntry: Identifiable, Equatable, Sendable {
    let key: String
    let calls: Int
    let input: Int
    let output: Int
    let costUSD: Double

    var id: String { key }

    var displayName: String {
        switch key.lowercased() {
        case "grok": return "Grok"
        case "sonnet": return "Sonnet"
        case "haiku": return "Haiku"
        case "other": return "Autres"
        default: return key.capitalized
        }
    }

    var symbolName: String {
        switch key.lowercased() {
        case "grok": return "bolt.fill"
        case "sonnet": return "sparkles"
        case "haiku": return "leaf.fill"
        case "other": return "square.stack.3d.up.fill"
        default: return "cpu"
        }
    }
}

struct UsagePeriod: Equatable, Sendable {
    let models: [ModelUsageEntry]
    let totalCalls: Int
    let totalInput: Int
    let totalOutput: Int
    let totalCostUSD: Double

    static let canonicalModelKeys = ["grok", "sonnet", "haiku", "other"]

    static var empty: UsagePeriod {
        let entries = canonicalModelKeys.map {
            ModelUsageEntry(key: $0, calls: 0, input: 0, output: 0, costUSD: 0)
        }
        return UsagePeriod(models: entries, totalCalls: 0, totalInput: 0, totalOutput: 0, totalCostUSD: 0)
    }
}

struct LastRequestUsage: Equatable, Sendable {
    let model: String
    let task: String
    let formattedTime: String

    var isEmpty: Bool {
        model == "—" && task == "—" && formattedTime == "—"
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let budget: BudgetUsage
    let openRouter: OpenRouterUsage
    let today: UsagePeriod
    let month: UsagePeriod
    let lastRequest: LastRequestUsage?
    let fetchedAt: Date

    func period(for tab: UsagePeriodTab) -> UsagePeriod {
        switch tab {
        case .today: return today
        case .month: return month
        }
    }
}

// MARK: - Décodage JSON tolérant

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    static func key(_ name: String) -> AnyCodingKey {
        AnyCodingKey(stringValue: name)!
    }
}

private extension KeyedDecodingContainer where K == AnyCodingKey {
    func decodeLossyDouble(forKeys keys: [String]) -> Double? {
        for name in keys {
            let k = AnyCodingKey.key(name)
            guard contains(k) else { continue }
            if let value = try? decodeIfPresent(Double.self, forKey: k) {
                return value
            }
            if let intVal = try? decodeIfPresent(Int.self, forKey: k) {
                return Double(intVal)
            }
            if let text = try? decodeIfPresent(String.self, forKey: k) {
                let normalized = text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "%", with: "")
                if let parsed = Double(normalized) {
                    return parsed
                }
            }
        }
        return nil
    }

    func decodeLossyInt(forKeys keys: [String]) -> Int? {
        for name in keys {
            let k = AnyCodingKey.key(name)
            guard contains(k) else { continue }
            if let value = try? decodeIfPresent(Int.self, forKey: k) {
                return value
            }
            if let dbl = try? decodeIfPresent(Double.self, forKey: k) {
                return Int(dbl.rounded())
            }
            if let text = try? decodeIfPresent(String.self, forKey: k),
               let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }

    func decodeLossyString(forKeys keys: [String]) -> String? {
        for name in keys {
            let k = AnyCodingKey.key(name)
            guard contains(k) else { continue }
            if let value = try? decodeIfPresent(String.self, forKey: k) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}

extension BudgetUsage: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let spent = container.decodeLossyDouble(forKeys: ["spent_usd", "spent", "used_usd"]) ?? 0.0
        let monthly = container.decodeLossyDouble(forKeys: ["monthly_usd", "monthly", "limit_usd", "budget_usd"]) ?? 0.0
        let rawPct = container.decodeLossyDouble(forKeys: ["pct", "percent", "percentage"])
        let computedPct = monthly > 0 ? (spent / monthly) * 100.0 : 0.0
        self.init(spentUSD: spent, monthlyUSD: monthly, pct: rawPct ?? computedPct)
    }
}

extension OpenRouterUsage: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let remaining = container.decodeLossyDouble(forKeys: ["limit_remaining", "remaining_usd", "credits_remaining"])
        self.init(limitRemaining: remaining)
    }
}

private struct RawModelMetrics: Decodable {
    let name: String?
    let calls: Int
    let input: Int
    let output: Int
    let costUSD: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        self.name = container.decodeLossyString(forKeys: ["model", "name", "id"])
        self.calls = container.decodeLossyInt(forKeys: ["calls", "requests", "count"]) ?? 0
        self.input = container.decodeLossyInt(forKeys: ["input", "input_tokens", "prompt_tokens", "tokens_in"]) ?? 0
        self.output = container.decodeLossyInt(forKeys: ["output", "output_tokens", "completion_tokens", "tokens_out"]) ?? 0
        self.costUSD = container.decodeLossyDouble(forKeys: ["cost_usd", "cost", "spent_usd"]) ?? 0.0
    }
}

extension UsagePeriod: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var parsedByKey: [String: RawModelMetrics] = [:]

        let modelsKey = AnyCodingKey.key("models")
        if container.contains(modelsKey) {
            if let dict = try? container.decode([String: RawModelMetrics].self, forKey: modelsKey) {
                for (rawKey, metrics) in dict {
                    parsedByKey[rawKey.lowercased()] = metrics
                }
            } else if let list = try? container.decode([RawModelMetrics].self, forKey: modelsKey) {
                for item in list {
                    if let key = item.name?.lowercased(), !key.isEmpty {
                        parsedByKey[key] = item
                    }
                }
            }
        } else {
            for candidate in Self.canonicalModelKeys {
                let k = AnyCodingKey.key(candidate)
                if let metrics = try? container.decodeIfPresent(RawModelMetrics.self, forKey: k) {
                    parsedByKey[candidate] = metrics
                }
            }
        }

        var entries: [ModelUsageEntry] = []
        for canonical in Self.canonicalModelKeys {
            let m = parsedByKey[canonical]
            entries.append(
                ModelUsageEntry(
                    key: canonical,
                    calls: m?.calls ?? 0,
                    input: m?.input ?? 0,
                    output: m?.output ?? 0,
                    costUSD: m?.costUSD ?? 0.0
                )
            )
        }

        // Conserve d'éventuels modèles supplémentaires renvoyés par le serveur
        let extras = parsedByKey.keys
            .filter { !Self.canonicalModelKeys.contains($0) }
            .sorted()
        for extra in extras {
            if let m = parsedByKey[extra] {
                entries.append(
                    ModelUsageEntry(
                        key: extra,
                        calls: m.calls,
                        input: m.input,
                        output: m.output,
                        costUSD: m.costUSD
                    )
                )
            }
        }

        let sumCalls = entries.reduce(0) { $0 + $1.calls }
        let sumInput = entries.reduce(0) { $0 + $1.input }
        let sumOutput = entries.reduce(0) { $0 + $1.output }
        let sumCost = entries.reduce(0.0) { $0 + $1.costUSD }

        self.models = entries
        self.totalCalls = container.decodeLossyInt(forKeys: ["calls", "total_calls"]) ?? sumCalls
        self.totalInput = container.decodeLossyInt(forKeys: ["input", "total_input"]) ?? sumInput
        self.totalOutput = container.decodeLossyInt(forKeys: ["output", "total_output"]) ?? sumOutput
        self.totalCostUSD = container.decodeLossyDouble(forKeys: ["cost_usd", "total_cost_usd"]) ?? sumCost
    }
}

extension LastRequestUsage: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        let model = container.decodeLossyString(forKeys: ["model", "modele", "provider", "name"]) ?? "—"
        let task = container.decodeLossyString(forKeys: ["task", "tache", "type", "route", "action", "reason", "category"]) ?? "—"

        let timeKeys = ["time", "heure", "at", "timestamp", "ts", "created_at", "date", "datetime"]
        var formatted = "—"
        if let rawTimeString = container.decodeLossyString(forKeys: timeKeys) {
            formatted = Self.formatTimestampString(rawTimeString)
        } else if let epoch = container.decodeLossyDouble(forKeys: timeKeys) {
            let seconds = epoch > 10_000_000_000 ? epoch / 1000.0 : epoch
            formatted = Self.formatDate(Date(timeIntervalSince1970: seconds))
        }

        self.init(model: model, task: task, formattedTime: formatted)
    }

    private static func formatTimestampString(_ raw: String) -> String {
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: raw) {
            return formatDate(date)
        }

        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]
        if let date = isoStandard.date(from: raw) {
            return formatDate(date)
        }

        let sqlFormatter = DateFormatter()
        sqlFormatter.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            sqlFormatter.dateFormat = pattern
            if let date = sqlFormatter.date(from: raw) {
                return formatDate(date)
            }
        }

        return raw
    }

    private static func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let french = Locale(identifier: "fr_FR")
        if calendar.isDateInToday(date) {
            return date.formatted(
                Date.FormatStyle(locale: french)
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits)
                    .second(.twoDigits)
            )
        }
        if calendar.isDateInYesterday(date) {
            let hm = date.formatted(
                Date.FormatStyle(locale: french)
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits)
            )
            return "Hier \(hm)"
        }
        return date.formatted(
            Date.FormatStyle(locale: french)
                .day(.twoDigits)
                .month(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}

extension UsageSnapshot: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        let budget = (try? container.decodeIfPresent(BudgetUsage.self, forKey: .key("budget")))
            ?? BudgetUsage(spentUSD: 0, monthlyUSD: 0, pct: 0)
        let openRouter = (try? container.decodeIfPresent(OpenRouterUsage.self, forKey: .key("openrouter")))
            ?? OpenRouterUsage(limitRemaining: nil)
        let today = (try? container.decodeIfPresent(UsagePeriod.self, forKey: .key("today")))
            ?? .empty
        let month = (try? container.decodeIfPresent(UsagePeriod.self, forKey: .key("month")))
            ?? .empty
        let rawLastRequest = try? container.decodeIfPresent(LastRequestUsage.self, forKey: .key("last_request"))
        let lastRequest = (rawLastRequest?.isEmpty == true) ? nil : rawLastRequest

        self.init(
            budget: budget,
            openRouter: openRouter,
            today: today,
            month: month,
            lastRequest: lastRequest,
            fetchedAt: .now
        )
    }
}

// MARK: - Client HTTP `/usage`

/// Client pour `GET http://100.66.0.111:8787/usage` (via Tailscale).
/// La clé `API_SERVER_KEY` est lue exclusivement depuis le Keychain et n'est jamais écrite en dur ni journalisée.
enum UsageAPI {
    static let timeoutSeconds: TimeInterval = 8

    static func resolvedURL(from rawURL: String) -> URL? {
        var trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = AppSettings.defaultUsageURL
        }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }
        return components.url
    }

    /// Lit la clé `API_SERVER_KEY` depuis le Keychain (clé dédiée Conso, ou jeton Serveur si la clé dédiée est vide).
    private static func readServerKeyFromKeychain() -> String? {
        if let dedicated = KeychainHelper.read(account: KeychainHelper.usageAPIKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !dedicated.isEmpty {
            return dedicated
        }
        if let serverToken = KeychainHelper.read(account: KeychainHelper.apiTokenAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !serverToken.isEmpty {
            return serverToken
        }
        return nil
    }

    static func fetchUsage(rawURL: String) async throws -> UsageSnapshot {
        guard let url = resolvedURL(from: rawURL) else {
            throw UsageFetchError.invalidURL
        }
        guard let apiKey = readServerKeyFromKeychain() else {
            throw UsageFetchError.missingAPIKey
        }
        if !NetworkMonitor.shared.isConnected {
            throw UsageFetchError.noInternet
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw NetworkMonitor.shared.isConnected
                    ? UsageFetchError.unreachable
                    : UsageFetchError.noInternet
            case .badURL, .unsupportedURL:
                throw UsageFetchError.invalidURL
            default:
                throw UsageFetchError.unreachable
            }
        } catch {
            throw UsageFetchError.unreachable
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageFetchError.unreachable
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw UsageFetchError.unauthorized
        case 403:
            throw UsageFetchError.forbidden
        default:
            throw UsageFetchError.serverError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageSnapshot.self, from: data)
        } catch {
            throw UsageFetchError.decodingFailed
        }
    }
}
