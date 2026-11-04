# Monika ✨

App iPhone native (SwiftUI, iOS 26) pour discuter avec mon assistant IA personnel, au design **Liquid Glass**.

## Structure

```
project.yml                    # Définition du projet (XcodeGen)
Monika/
  MonikaApp.swift              # Point d'entrée, conteneur SwiftData, apparence, moniteur réseau
  Models/
    Message.swift              # Modèle SwiftData (texte, rôle, date, pièces jointes)
    Attachment.swift           # Redimensionnement photo (1024 px JPEG 0.7) + extraction PDF/texte
    AppSettings.swift          # Apparence (@AppStorage) + test /v1/models
    DemoMode.swift             # Données de démo (-MonikaDemo YES), en mémoire
  Services/
    MonikaAPI.swift            # Client SSE OpenAI multimodal (/v1/chat/completions + retry)
    SpeechRecognizer.swift     # Dictée vocale en direct (SFSpeechRecognizer fr-FR + AVAudioEngine)
  Utilities/
    KeychainHelper.swift       # Stockage du jeton dans le Keychain iOS
    NetworkMonitor.swift       # Surveillance réseau temps réel (NWPathMonitor)
    String+Emoji.swift         # Emojis jamais seuls en début de ligne
  Views/
    ChatView.swift             # Écran de chat, arrière-plan, pièces jointes, dictée
    ChatHeader.swift           # En-tête flottant centré en verre + accès Réglages
    MessageBubble.swift        # Bulles en verre teinté (texte, photos, documents) + erreurs
    ComposerBar.swift          # Barre de saisie flottante (+, aperçu, dictée pulsante, envoi/stop)
    SettingsView.swift         # Écran Réglages Liquid Glass (serveur, apparence, conversation)
    AnimatedBackground.swift   # Dégradé maillé animé (clair / sombre)
MonikaUITests/                 # Tests UI servant aux captures (03 à 10)
.github/workflows/build.yml    # CI : Xcode 26 → IPA non signée + captures simulateur
```

## Compilation

Aucune compilation locale : tout passe par **GitHub Actions** (`macos-latest`, Xcode 26).
À chaque push, l'onglet **Actions** produit :

- `Monika-ipa` → `Monika.ipa` non signée (à signer/installer avec Sideloadly)
- `Monika-screenshots` → captures du simulateur iPhone (iOS 26) : historique clair/sombre, réglages conversation, confirmation d'effacement, réglages clair/sombre, Monika écrit, erreur réseau, menu pièce jointe, dictée vocale
- `build-logs` → journaux `xcodebuild`

## Feuille de route

- [x] Étape 1 — Structure, CI, écran de chat Liquid Glass (messages factices)
- [x] Étape 2 — Historique SwiftData, séparateurs de date, effacement
- [x] Étape 3 — Réglages (URL + jeton dans le Keychain)
- [x] Étape 4 — API compatible OpenAI (streaming) + gestion des erreurs
- [x] Étape 5 — Correctifs saisie/arrière-plan, pièces jointes multimodales, dictée vocale, en-tête centré
