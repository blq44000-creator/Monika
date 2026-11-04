import Foundation
import SwiftData

/// Auteur d'un message.
enum MessageRole: String, Codable {
    case user
    case assistant
}

/// Message du chat, sauvegardé sur le téléphone avec SwiftData.
@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var text: String
    var roleRaw: String
    var date: Date

    /// Métadonnées optionnelles de pièce jointe (migration légère automatique SwiftData).
    var attachmentName: String?
    @Attribute(.externalStorage) var attachmentImageData: Data?
    var attachmentExtractedText: String?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    var isFromUser: Bool { role == .user }

    init(
        id: UUID = UUID(),
        text: String,
        role: MessageRole,
        date: Date = .now,
        attachmentName: String? = nil,
        attachmentImageData: Data? = nil,
        attachmentExtractedText: String? = nil
    ) {
        self.id = id
        self.text = text
        self.roleRaw = role.rawValue
        self.date = date
        self.attachmentName = attachmentName
        self.attachmentImageData = attachmentImageData
        self.attachmentExtractedText = attachmentExtractedText
    }
}

// MARK: - Contenus par défaut

extension Message {
    /// Message d'accueil affiché quand l'historique est vide.
    static func welcome() -> Message {
        Message(
            text: "Bonjour ! 👋 Je suis Monika, ton assistante personnelle. Comment puis-je t'aider aujourd'hui ?",
            role: .assistant
        )
    }

    /// Réponse factice utilisée uniquement en DemoMode.
    static func mockReply(for prompt: String) -> String {
        let replies = [
            "Intéressant ! 🤔 Dès que je serai connectée à ton serveur, je pourrai vraiment te répondre.",
            "Bien reçu ✨ Pour l'instant je fonctionne avec des réponses factices.",
            "Je m'en occupe ! 💪 (réponse de démonstration)",
        ]
        let index = prompt.unicodeScalars.reduce(0) { $0 + Int($1.value) } % replies.count
        return replies[index]
    }
}
