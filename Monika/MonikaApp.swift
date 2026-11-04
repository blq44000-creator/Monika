import SwiftUI

@main
struct MonikaApp: App {
    var body: some Scene {
        WindowGroup {
            ChatView()
                .tint(Theme.accent)
        }
    }
}

enum Theme {
    /// Couleur d'accent de Monika (bulles utilisateur, bouton envoyer).
    static let accent = Color.indigo
}
