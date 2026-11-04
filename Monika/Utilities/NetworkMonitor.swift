import Foundation
import Network

/// Surveillance en temps réel de l'état réel du réseau via `NWPathMonitor`.
/// Permet de distinguer une vraie absence d'Internet d'une simple connexion HTTP expirée au retour d'arrière-plan.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.blq.monika.networkMonitor", qos: .utility)
    private let lock = NSLock()
    private var _isConnected = true
    private var isStarted = false

    private init() {}

    /// Indique si une interface réseau valide est disponible sur l'iPhone.
    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status != .unsatisfied
            self.lock.lock()
            self._isConnected = connected
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
