import SwiftUI
import UIKit

/// Barre de saisie flottante en Liquid Glass :
/// menu `+` (photo/fichier), aperçu de pièce jointe, dictée vocale pulsante et envoi/stop.
struct ComposerBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var isGenerating: Bool = false
    var isRecordingDictation: Bool = false
    var pendingAttachment: PendingAttachment? = nil
    var onPickPhoto: () -> Void = {}
    var onPickFile: () -> Void = {}
    var onRemoveAttachment: () -> Void = {}
    var onToggleDictation: () -> Void = {}
    var onSend: () -> Void
    var onStop: () -> Void = {}

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingAttachment != nil
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                if let pendingAttachment {
                    AttachmentPreviewStrip(
                        attachment: pendingAttachment,
                        onRemove: onRemoveAttachment
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isRecordingDictation {
                    DictationStatusPill()
                        .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
                }

                HStack(alignment: .bottom, spacing: 10) {
                    Menu {
                        Button(action: onPickPhoto) {
                            Label("Photo", systemImage: "photo")
                        }

                        Button(action: onPickFile) {
                            Label("Fichier", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .glassEffect(.regular, in: .circle)
                    .accessibilityLabel("Ajouter une pièce jointe")
                    .accessibilityIdentifier("attachmentMenuButton")

                    HStack(alignment: .bottom, spacing: 4) {
                        TextField("Message à Monika…", text: $text, axis: .vertical)
                            .font(.body)
                            .lineLimit(1...6)
                            .focused(isFocused)
                            .submitLabel(.send)
                            .padding(.leading, 16)
                            .padding(.vertical, 11)
                            .accessibilityIdentifier("composerTextField")

                        if isGenerating {
                            Button(action: onStop) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.circle)
                            .padding(4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                            .accessibilityLabel("Arrêter la réponse")
                            .accessibilityIdentifier("stopGenerationButton")
                        } else {
                            DictationMicButton(
                                isRecording: isRecordingDictation,
                                action: onToggleDictation
                            )
                            .padding(.vertical, 4)
                            .padding(.trailing, (canSend && !isRecordingDictation) ? 0 : 4)

                            if canSend && !isRecordingDictation {
                                Button(action: onSend) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.circle)
                                .padding(.vertical, 4)
                                .padding(.trailing, 4)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                                .accessibilityLabel("Envoyer")
                                .accessibilityIdentifier("sendMessageButton")
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: canSend)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isGenerating)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isRecordingDictation)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: pendingAttachment)
    }
}

/// Bandeau d'aperçu de la pièce jointe sélectionnée, affiché au-dessus de la barre de saisie.
private struct AttachmentPreviewStrip: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            switch attachment.kind {
            case .image(_, let preview):
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 10))
            case .document:
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? .primary : Color(white: 0.08))
                    .lineLimit(1)

                Text(attachment.isImage ? "Photo prête à l'envoi" : "Document prêt à l'envoi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer la pièce jointe")
            .accessibilityIdentifier("removeAttachmentButton")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(
            colorScheme == .dark
                ? .regular.tint(Color.white.opacity(0.10))
                : .regular.tint(Color.white.opacity(0.55)),
            in: .rect(cornerRadius: 16)
        )
    }
}

/// Indicateur visuel en verre affiché pendant la dictée vocale en direct.
private struct DictationStatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var glowing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(glowing ? 1.25 : 0.85)
                .opacity(glowing ? 1.0 : 0.45)

            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            Text("Écoute en cours… Appuie sur le micro pour terminer")
                .font(.caption.weight(.medium))
                .foregroundStyle(colorScheme == .dark ? .primary : Color(white: 0.12))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(
            colorScheme == .dark
                ? .regular.tint(Color.red.opacity(0.20))
                : .regular.tint(Color.red.opacity(0.14)),
            in: .capsule
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Écoute vocale en cours")
    }
}

/// Bouton micro de l'application avec animation Liquid Glass pulsante pendant l'enregistrement.
private struct DictationMicButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Group {
            if isRecording {
                Button(action: action) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.32))
                            .frame(width: 36, height: 36)
                            .scaleEffect(pulse ? 1.28 : 0.92)
                            .opacity(pulse ? 0.20 : 0.70)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color.red.opacity(0.85)).interactive(), in: .circle)
                .accessibilityLabel("Arrêter la dictée")
                .accessibilityIdentifier("dictationButton")
            } else {
                Button(action: action) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dicter un message")
                .accessibilityIdentifier("dictationButton")
            }
        }
        .onChange(of: isRecording, initial: true) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    pulse = false
                }
            }
        }
    }
}
