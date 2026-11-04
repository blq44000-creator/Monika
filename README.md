# Monika ✨

App iPhone native (SwiftUI, iOS 26) pour discuter avec mon assistant IA personnel et accéder à son écran distant, au design **Liquid Glass**.

## Structure

```
project.yml                    # Définition du projet (XcodeGen + Info.plist + ATS ts.net)
monika-logo.png                # Logo source de Monika
Monika/
  MonikaApp.swift              # Point d'entrée, conteneur SwiftData, apparence, moniteur réseau
  Assets.xcassets/
    AppIcon.appiconset/        # Icône iOS 26 (1024×1024 sans transparence)
    MonikaAvatar.imageset/     # Logo de Monika détouré en rond (@1x, @2x, @3x)
  Models/
    Message.swift              # Modèle SwiftData (texte, rôle, date, pièces jointes)
    Attachment.swift           # Redimensionnement photo (1024 px JPEG 0.7) + extraction PDF/texte
    AppSettings.swift          # Apparence, endpoints API OpenAI et URL noVNC Tailscale
  Services/
    MonikaAPI.swift            # Client SSE OpenAI multimodal (/v1/chat/completions + retry)
    SpeechRecognizer.swift     # Dictée vocale en direct (SFSpeechRecognizer fr-FR + AVAudioEngine)
  Utilities/
    KeychainHelper.swift       # Stockage sécurisé (jeton API et mot de passe VNC) dans le Keychain
    NetworkMonitor.swift       # Surveillance réseau temps réel (NWPathMonitor)
    String+Emoji.swift         # Emojis jamais seuls en début de ligne
  Views/
    ChatView.swift             # Écran de chat, arrière-plan, pièces jointes, dictée
    ChatHeader.swift           # En-tête flottant en verre (écran VNC, identité Monika, réglages)
    MonikaScreenView.swift     # Vue plein écran noVNC (WKWebView, Tailscale, timeout 10 s)
    MessageBubble.swift        # Bulles en verre teinté (texte, photos, documents) + erreurs
    ComposerBar.swift          # Barre de saisie flottante (+, aperçu, dictée pulsante, envoi/stop)
    SettingsView.swift         # Écran Réglages Liquid Glass (serveur, écran VNC, apparence, conversation)
    AnimatedBackground.swift   # Dégradé maillé animé (clair / sombre)
.github/workflows/build.yml    # CI rapide : Xcode 26 + cache DerivedData → Monika.ipa non signée
```

## Compilation

Aucune compilation locale : tout passe par **GitHub Actions** (`macos-latest`, Xcode 26).
À chaque push, l'onglet **Actions** produit :

- `Monika-ipa` → `Monika.ipa` non signée (à signer/installer sur iPhone avec Sideloadly)
- `build-logs` → journaux `xcodebuild` (publiés uniquement en cas d'échec)

## Feuille de route

- [x] Étape 1 — Structure, CI, écran de chat Liquid Glass
- [x] Étape 2 — Historique SwiftData, séparateurs de date, effacement
- [x] Étape 3 — Réglages (URL + jeton dans le Keychain)
- [x] Étape 4 — API compatible OpenAI (streaming) + gestion des erreurs
- [x] Étape 5 — Correctifs saisie/arrière-plan, pièces jointes multimodales, dictée vocale
- [x] Étape 6 — Écran VNC (noVNC / Tailscale), logo officiel Monika, build CI accéléré
