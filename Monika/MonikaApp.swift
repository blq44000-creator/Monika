import SwiftUI
import SwiftData

@main
struct MonikaApp: App {
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }

    @MainActor
    private static func makeContainer() -> ModelContainer {
        let demo = DemoMode.isEnabled
        let configuration = ModelConfiguration(isStoredInMemoryOnly: demo)
        do {
            let container = try ModelContainer(for: Message.self, configurations: configuration)
            if demo {
                DemoMode.seed(container.mainContext)
            }
            return container
        } catch {
            fatalError("Impossible d'ouvrir la base SwiftData : \(error)")
        }
    }
}

enum Theme {
    /// Couleur d'accent de Monika (bulles utilisateur, bouton envoyer).
    static let accent = Color.indigo
}
