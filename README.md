# Monika ✨

App iPhone native (SwiftUI) pour discuter avec mon assistant IA personnel, suivre sa conso et accéder à son écran distant, au design **Liquid Glass** (compatible Xcode 15.2 / iOS 17+ en local et API natives iOS 26 sous Xcode 26).

## Ouvrir et lancer dans Xcode (en local)

1. Ouvre **`Monika.xcodeproj`** dans Xcode (`/Users/blq/.gemini/antigravity/scratch/monika-app/Monika.xcodeproj`).
   - *Au tout premier lancement de Xcode, clique sur **Agree** / **Install** s'il demande d'installer les composants système requis (`CoreSimulator`), ou lance `sudo xcodebuild -runFirstLaunch` dans le Terminal.*
2. Dans le navigateur à gauche, clique sur le projet **Monika** → cible **Monika** → onglet **Signing & Capabilities** :
   - Coche **Automatically manage signing**.
   - Choisis ton compte Apple (**Personal Team**) dans **Team** (et change `Bundle Identifier` ex. `com.tonnom.monika` si Xcode le demande).
3. Branche ton iPhone (ou choisis un simulateur iPhone) et appuie sur **⌘R** (**Run**).

## Structure

```
Monika.xcodeproj               # Projet Xcode prêt à ouvrir en local (Xcode 15.2+)
project.yml                    # Définition XcodeGen (gardée synchronisée pour la CI)
monika-logo.png                # Logo source de Monika
Monika/
  MonikaApp.swift              # Point d'entrée, conteneur SwiftData, apparence, moniteur réseau
  Info.plist                   # Permissions iOS + exceptions ATS Tailscale
  Assets.xcassets/
    AppIcon.appiconset/        # Icône 1024×1024 sans transparence
    MonikaAvatar.imageset/     # Logo de Monika détouré en rond (@1x, @2x, @3x)
  Models/
    Message.swift              # Modèle SwiftData (texte, rôle, date, pièces jointes)
    Attachment.swift           # Redimensionnement photo (1024 px JPEG 0.7) + extraction PDF/texte
    AppSettings.swift          # Apparence, endpoints API OpenAI, noVNC et Conso Tailscale
  Services/
    MonikaAPI.swift            # Client SSE OpenAI multimodal (/v1/chat/completions + retry)
    UsageAPI.swift             # Client GET /usage via Tailscale (clé API lue depuis le Keychain)
    SpeechRecognizer.swift     # Dictée vocale en direct (SFSpeechRecognizer fr-FR + AVAudioEngine)
  Utilities/
    KeychainHelper.swift       # Stockage sécurisé (jeton API, clé Conso, mot de passe VNC) dans le Keychain
    LiquidGlassCompat.swift    # Compatibilité Liquid Glass pour iOS 17 / Xcode 15.2 (bascule auto vers iOS 26)
    NetworkMonitor.swift       # Surveillance réseau temps réel (NWPathMonitor)
    String+Emoji.swift         # Emojis jamais seuls en début de ligne
  Views/
    ChatView.swift             # Écran de chat, arrière-plan, pièces jointes, dictée
    ChatHeader.swift           # En-tête flottant en verre (écran VNC, identité Monika, Conso, réglages)
    MonikaScreenView.swift     # Vue plein écran noVNC (WKWebView, Tailscale, timeout 10 s)
    UsageView.swift            # Écran Conso Liquid Glass (jauge budget, OpenRouter, modèles, 10 s)
    MessageBubble.swift        # Bulles en verre teinté (texte, photos, documents) + erreurs
    ComposerBar.swift          # Barre de saisie flottante (+, aperçu, dictée pulsante, envoi/stop)
    SettingsView.swift         # Écran Réglages Liquid Glass (serveur, écran VNC, Conso, apparence)
    AnimatedBackground.swift   # Dégradé animé (MeshGradient iOS 18+ / dégradé auroral iOS 17)
```
