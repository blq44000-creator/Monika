# Monika ✨

App iPhone native (SwiftUI, iOS 26) pour discuter avec mon assistant IA personnel, au design **Liquid Glass**.

## Structure

```
project.yml                  # Définition du projet (XcodeGen)
Monika/
  MonikaApp.swift            # Point d'entrée + thème
  Models/ChatMessage.swift   # Modèle de message (+ données factices)
  Views/
    ChatView.swift           # Écran de chat
    ChatHeader.swift         # En-tête flottant en verre
    MessageBubble.swift      # Bulles en verre teinté + indicateur de saisie
    ComposerBar.swift        # Barre de saisie flottante en verre
    AnimatedBackground.swift # Dégradé maillé animé (clair / sombre)
.github/workflows/build.yml  # CI : Xcode 26 → IPA non signée + captures simulateur
```

## Compilation

Aucune compilation locale : tout passe par **GitHub Actions** (`macos-latest`, Xcode 26).
À chaque push, l'onglet **Actions** produit :

- `Monika-ipa` → `Monika.ipa` non signée (à signer/installer avec Sideloadly)
- `Monika-screenshots` → captures du simulateur iPhone (iOS 26), mode clair et sombre
- `build-logs` → journaux `xcodebuild`

## Feuille de route

- [x] Étape 1 — Structure, CI, écran de chat Liquid Glass (messages factices)
- [ ] Étape 2 — Historique SwiftData
- [ ] Étape 3 — Réglages (URL + jeton dans le Keychain)
- [ ] Étape 4 — API compatible OpenAI (streaming)
- [ ] Étape 5 — Gestion des erreurs
