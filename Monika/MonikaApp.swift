import SwiftUI
import SwiftData

@main
struct MonikaApp: App {
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppAppearance.system.rawValue
    private let container: ModelContainer

    init() {
        NetworkMonitor.shared.start()
        container = Self.makeContainer()
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
    }

    @MainActor
    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Message.self)
        } catch {
            fatalError("Impossible d'ouvrir la base SwiftData : \(error)")
        }
    }
}

enum Theme {
    /// Couleur d'accent de Monika (bulles utilisateur, bouton envoyer).
    static let accent = Color.indigo
}
