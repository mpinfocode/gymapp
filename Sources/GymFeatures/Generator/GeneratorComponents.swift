import SwiftUI
import GymUI

/// Una risposta del wizard: riga grande con titolo e una riga che dice **cosa
/// comporta** la scelta.
///
/// Alta almeno 64 punti (la SPEC ne chiede 56): si tocca con le mani sudate e si
/// legge senza avvicinare il telefono. Selezionata, si riempie di accento
/// pastello con il contenuto scuro sopra, come vuole DESIGN.md; non selezionata
/// resta una superficie grigia senza bordo né ombra.
struct GeneratorOptionRow: View {

    let title: String
    var detail: String?
    let isSelected: Bool
    /// Cerchio invece di spunta: le domande a scelta multipla.
    var isMultipleChoice = false
    /// Riga toccabile ma spenta (si è già al massimo di scelte).
    var isDimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bodyEmphasis)
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.captionText)
                            .foregroundStyle(detailColor)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                mark
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.l)
            .frame(minHeight: 64, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isDimmed && !isSelected ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var mark: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Theme.onPastel)
                .accessibilityHidden(true)
        } else if isMultipleChoice {
            Image(systemName: "circle")
                .font(.system(.body, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
    }

    private var background: Color {
        isSelected ? Theme.accent.fill : Theme.surface
    }

    private var titleColor: Color {
        isSelected ? Theme.onPastel : Theme.textPrimary
    }

    private var detailColor: Color {
        isSelected ? Theme.onPastel.opacity(0.72) : Theme.textSecondary
    }
}

/// Avanzamento del wizard: "3 di 10" e una barra sottile.
///
/// Discreto per davvero: 12 punti di testo secondario e una barra alta 3. Non è
/// il contenuto della schermata, è solo la conferma che il flusso ha una fine.
struct GeneratorProgressBar: View {

    let index: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("\(index) di \(total)")
                .font(.overline)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)

            ThickProgressBar(
                value: Double(index),
                total: Double(total),
                height: 3,
                tint: Theme.ink,
                accessibilityTitle: "Avanzamento delle domande"
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Domanda \(index) di \(total)"))
    }
}

/// Azione secondaria testuale sotto un bottone primario ("Salta", "Annulla").
struct GeneratorTextAction: View {

    private let title: String
    private let tint: Color
    private let action: () -> Void

    init(_ title: String, tint: Color = Theme.textSecondary, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

extension View {

    /// Sheet a tutta altezza: il wizard non è un foglio a mezza pagina.
    /// I detent esistono solo su iOS; su macOS (screenshot e anteprima) la sheet
    /// è già grande quanto la finestra.
    @ViewBuilder
    func fullHeightSheet() -> some View {
        #if os(iOS)
        self.presentationDetents([.large])
        #else
        self
        #endif
    }
}
