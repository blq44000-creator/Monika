import Foundation

/// Message affiché dans le chat.
/// Étape 1 : simple struct en mémoire. Sera remplacé par un modèle SwiftData à l'étape 2.
struct ChatMessage: Identifiable, Hashable {
    enum Role: String, Hashable {
        case user
        case assistant
    }

    let id: UUID
    var role: Role
    var text: String
    var date: Date

    init(id: UUID = UUID(), role: Role, text: String, date: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

// MARK: - Données factices (étape 1)

extension ChatMessage {
    static let samples: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "Bonjour ! 👋 Je suis Monika, ton assistante personnelle. Comment puis-je t'aider aujourd'hui ?"),
        ChatMessage(role: .user, text: "Salut Monika ! Tu peux me résumer ma journée ?"),
        ChatMessage(role: .assistant, text: "Bien sûr ☀️\n\n• 10h00 — Réunion d'équipe\n• 12h30 — Déjeuner avec Léa\n• 16h00 — Point projet Monika 🚀\n\nTu as aussi 3 rappels en attente."),
        ChatMessage(role: .user, text: "Parfait, rappelle-moi d'acheter du pain ce soir 🥖"),
        ChatMessage(role: .assistant, text: "C'est noté ! Je te le rappellerai à 18h30. ✅"),
    ]

    static func mockReply(for prompt: String) -> String {
        let replies = [
            "Intéressant ! 🤔 Dès que je serai connectée à ton serveur, je pourrai vraiment te répondre.",
            "Bien reçu ✨ Pour l'instant je fonctionne avec des réponses factices.",
            "Je m'en occupe ! 💪 (réponse de démonstration)",
        ]
        return replies[abs(prompt.hashValue) % replies.count]
    }
}
