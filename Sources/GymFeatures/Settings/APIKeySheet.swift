import SwiftUI
import GymUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Inserimento della chiave OpenRouter: un campo mascherato, "Incolla", "Salva".
///
/// La chiave si scrive una volta e non si rilegge mai più: questa sheet **non**
/// mostra il valore già salvato, nemmeno per modificarlo. Sostituirla vuol dire
/// incollarne una nuova. È la regola della SPEC ("mai mostrata in chiaro dopo il
/// salvataggio") e toglie anche il rischio di fotografarla per sbaglio.
struct APIKeySheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// `true` quando una chiave c'è già: cambia solo il titolo.
    let isReplacing: Bool
    /// Chiamata dopo un salvataggio andato a buon fine.
    var onSaved: (() -> Void)?

    @State private var key = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isReplacing ? "Sostituisci la chiave" : "Inserisci la chiave",
                actionTitle: "Annulla"
            ) {
                dismiss()
            }
            .sheetHeaderMargins()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    field

                    if let problem {
                        Text(problem)
                            .font(.captionText)
                            .foregroundStyle(Theme.Metric.arancio.deep)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("La chiave resta solo su questo iPhone. Crea la chiave su openrouter.ai e imposta un limite di spesa.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrimaryButton("Salva", isEnabled: !trimmedKey.isEmpty, action: save)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.background.ignoresSafeArea(edges: .bottom))
        }
        .pageBackground()
        .keyboardDismissOnTap()
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: Theme.Spacing.s) {
            SecureField("sk-or-v1-…", text: $key)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
                .accessibilityLabel(Text("Chiave OpenRouter"))

            PasteKeyButton { pasted in
                key = pasted
                problem = nil
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: 52)
        .background(Theme.surface, in: Capsule(style: .continuous))
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        focused = false
        guard !trimmedKey.isEmpty else {
            problem = "Incolla la chiave prima di salvare."
            return
        }
        if let message = app.ai.saveKey(trimmedKey) {
            problem = message
            return
        }
        // Il valore sparisce dalla memoria della schermata appena salvato.
        key = ""
        Haptics.play(.success)
        onSaved?()
        dismiss()
    }
}

/// "Incolla": esiste solo dove esiste una clipboard leggibile.
///
/// Su iOS legge `UIPasteboard`, su macOS `NSPasteboard`; il ramo iOS non viene
/// type-checkato in locale, quindi è tenuto banale di proposito.
private struct PasteKeyButton: View {

    let onPaste: (String) -> Void

    var body: some View {
        Button {
            guard let text = Self.clipboardText() else { return }
            onPaste(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } label: {
            Text("Incolla")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Incolla la chiave"))
    }

    private static func clipboardText() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}
