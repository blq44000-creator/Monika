import Foundation

extension String {
    /// Remplace les espaces autour des emojis par des espaces insécables,
    /// pour qu'un emoji ne se retrouve jamais seul sur une nouvelle ligne.
    var keepingEmojisAttached: String {
        let characters = Array(self)
        var result = String()
        result.reserveCapacity(utf8.count)
        for (index, character) in characters.enumerated() {
            if character == " " {
                let previousIsEmoji = index > 0 && characters[index - 1].isEmoji
                let nextIsEmoji = index + 1 < characters.count && characters[index + 1].isEmoji
                if previousIsEmoji || nextIsEmoji {
                    result.append("\u{00A0}")
                    continue
                }
            }
            result.append(character)
        }
        return result
    }
}

extension Character {
    /// Vrai pour les emojis affichés en couleur (exclut les chiffres, #, *…).
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}
