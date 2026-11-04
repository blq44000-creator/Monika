import Foundation
import SwiftData

/// Mode démo, activé par l'argument de lancement `-MonikaDemo YES`
/// (utilisé par le workflow GitHub pour les captures d'écran).
/// Les données sont alors gardées en mémoire uniquement : le vrai historique n'est jamais touché.
enum DemoMode {
    static let serverURL = "https://exemple.com"
    static let placeholderToken = "sk-monika-demo-1234567890"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-MonikaDemo")
    }

    /// Affiche l'indicateur « Monika écrit… » et le bouton stop (capture 07).
    static var showsTypingState: Bool {
        let args = ProcessInfo.processInfo.arguments
        return isEnabled && (args.contains("-demoTyping") || args.contains("-MonikaDemoTyping"))
    }

    /// Affiche une bulle d'erreur réseau simulée (capture 08).
    static var showsNetworkError: Bool {
        let args = ProcessInfo.processInfo.arguments
        return isEnabled && (args.contains("-demoError") || args.contains("-MonikaDemoError"))
    }

    static func configureSettings() {
        UserDefaults.standard.set(AppAppearance.system.rawValue, forKey: AppSettings.appearanceKey)
        UserDefaults.standard.set(serverURL, forKey: AppSettings.serverURLKey)
    }

    @MainActor
    static func seed(_ context: ModelContext) {
        let now = Date.now
        let day: TimeInterval = 86_400
        let samples: [(TimeInterval, MessageRole, String)] = [
            (-3 * day - 3_600, .assistant, "Bonjour ! 👋 Je suis Monika, ton assistante personnelle. Comment puis-je t'aider aujourd'hui ?"),
            (-3 * day - 3_500, .user, "Trouve-moi une idée de dîner rapide 🍝"),
            (-3 * day - 3_450, .assistant, "Que dirais-tu de pâtes au citron et parmesan ? Prêtes en 15 minutes, et franchement délicieuses 🍋"),
            (-day - 7_200, .user, "Rappelle-moi d'appeler maman demain matin"),
            (-day - 7_150, .assistant, "C'est noté, je te le rappellerai demain à 9h00 ☎️"),
            (-1_800, .user, "Salut Monika ! Tu peux me résumer ma journée ?"),
            (-1_750, .assistant, "Bien sûr ☀️\n\n• 10h00 — Réunion d'équipe\n• 12h30 — Déjeuner avec Léa\n• 16h00 — Point projet Monika 🚀\n\nEt n'oublie pas d'appeler ta maman ce matin 💛"),
            (-120, .user, "Parfait, et rappelle-moi d'acheter du pain ce soir en rentrant 🥖"),
            (-90, .assistant, "C'est noté ! Je te le rappellerai à 18h30, juste avant que tu partes du bureau ✅"),
        ]
        for (offset, role, text) in samples {
            context.insert(Message(text: text, role: role, date: now.addingTimeInterval(offset)))
        }
        if showsTypingState || showsNetworkError {
            context.insert(
                Message(
                    text: "Tu peux me préparer une idée de menu pour ce week-end ? 🥗",
                    role: .user,
                    date: now
                )
            )
        }
        try? context.save()
    }
}
