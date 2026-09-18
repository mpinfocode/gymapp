import SwiftUI
import GymUI

/// La scelta che apre la creazione di una scheda: **Manuale** o **Con l'AI**.
///
/// Due sole opzioni, grandi, con una riga che dice cosa succede dopo. Niente
/// icone, niente badge "novità", nessuna delle due è marcata come "migliore":
/// ricopiare la scheda dell'istruttore resta un uso legittimo quanto l'altro.
///
/// L'unico tocco espressivo è il `BlobGradient` in testa, statico: è la firma
/// visiva dell'app e questa è l'unica schermata del flusso che se la può
/// permettere senza diventare rumore (DESIGN.md).
public struct ProgramCreationChoiceSheet: View {

    @Environment(\.dismiss) private var dismiss

    private let onManual: () -> Void
    private let onAssisted: () -> Void

    /// - Parameters:
    ///   - onManual: apre il form manuale.
    ///   - onAssisted: apre il wizard con l'AI.
    public init(onManual: @escaping () -> Void, onAssisted: @escaping () -> Void) {
        self.onManual = onManual
        self.onAssisted = onAssisted
    }

    public var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Nuova scheda", actionTitle: "Annulla") { dismiss() }
                .sheetHeaderMargins()

            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    banner

                    choice(
                        title: "Manuale",
                        detail: "Scrivi tu la scheda, esercizio per esercizio.",
                        action: onManual
                    )
                    choice(
                        title: "Con l'AI",
                        detail: "Rispondi a poche domande, la scheda viene proposta in automatico.",
                        action: onAssisted
                    )
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
        }
        .pageBackground()
    }

    /// Gradiente **statico**: nessuna animazione, nessun costo per fotogramma.
    private var banner: some View {
        BlobGradient(seed: 1, animated: false)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .padding(.bottom, Theme.Spacing.xs)
    }

    private func choice(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text(detail)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
    }
}
