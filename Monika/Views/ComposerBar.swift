import SwiftUI

/// Barre de saisie flottante en Liquid Glass.
struct ComposerBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                GlassIconButton(systemName: "plus", label: "Ajouter", action: {})

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Message à Monika…", text: $text, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...6)
                        .focused(isFocused)
                        .submitLabel(.send)
                        .padding(.leading, 16)
                        .padding(.vertical, 11)

                    if canSend {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .padding(4)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .accessibilityLabel("Envoyer")
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .padding(4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: canSend)
    }
}
