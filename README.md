# Monika ✨

App iPhone native (SwiftUI, iOS 26) pour discuter avec mon assistant IA personnel, au design **Liquid Glass**.

## Structure

```
project.yml                  # Définition du projet (XcodeGen)
Monika/
  MonikaApp.swift              # Point d'entrée, conteneur SwiftData, apparence
  Models/
    Message.swift              # Modèle SwiftData (texte, rôle, date)
    AppSettings.swift          # Apparence (@AppStorage) + test /v1/models
    DemoMode.swift             # Données de démo (-MonikaDemo YES), en mémoire
  Utilities/
    KeychainHelper.swift       # Stockage du jeton dans le Keychain iOS
    String+Emoji.swift         # Emojis jamais seuls en début de ligne
  Views/
    ChatView.swift             # Écran de chat, séparateurs de date, effacement
    ChatHeader.swift           # En-tête flottant en verre + menu ☰
    MessageBubble.swift        # Bulles en verre teinté + indicateur de saisie
    ComposerBar.swift          # Barre de saisie flottante en verre
    SettingsView.swift         # Écran Réglages Liquid Glass
    AnimatedBackground.swift   # Dégradé maillé animé (clair / sombre)
MonikaUITests/                 # Tests UI servant aux captures (menu, réglages)
.github/workflows/build.yml  # CI : Xcode 26 → IPA non signée + captures simulateur
```

## Compilation

Aucune compilation locale : tout passe par **GitHub Actions** (`macos-latest`, Xcode 26).
À chaque push, l'onglet **Actions** produit :

- `Monika-ipa` → `Monika.ipa` non signée (à signer/installer avec Sideloadly)
- `Monika-screenshots` → captures du simulateur iPhone (iOS 26) : historique clair/sombre, menu ouvert, confirmation, réglages clair/sombre
- `build-logs` → journaux `xcodebuild`

## Feuille de route

- [x] Étape 1 — Structure, CI, écran de chat Liquid Glass (messages factices)
- [x] Étape 2 — Historique SwiftData, séparateurs de date, effacement
- [x] Étape 3 — Réglages (URL + jeton dans le Keychain)
- [ ] Étape 4 — API compatible OpenAI (streaming)
- [ ] Étape 5 — Gestion des erreurs
