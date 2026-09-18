import SwiftUI
import GymUI

/// Stepper della sezione Scheda: due cerchi grandi "meno" e "più" con il valore in
/// mezzo, nello stesso stile di quello di Impostazioni.
///
/// Sostituisce lo `Stepper` di sistema, che su iOS è un controllino grigio piccolo
/// per il pollice e fuori tono rispetto al resto dell'app. Il tocco dà un feedback
/// aptico leggero.
struct ProgramStepper: View {

    /// Valore già formattato ("4", "6").
    let value: String
    /// Unità mostrata in piccolo accanto al numero ("settimane", "giorni").
    var unit: String?
    let canDecrease: Bool
    let canIncrease: Bool
    /// Nome del valore per VoiceOver ("Serie").
    let title: String
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgramStepperButton(
                systemImage: "minus",
                label: "Riduci: \(title)",
                isEnabled: canDecrease,
                action: onDecrease
            )

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs + 2) {
                Text(value)
                    .bigNumberStyle()
                if let unit {
                    Text(unit)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(minWidth: 56)
            .accessibilityHidden(true)

            ProgramStepperButton(
                systemImage: "plus",
                label: "Aumenta: \(title)",
                isEnabled: canIncrease,
                action: onIncrease
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text([value, unit].compactMap { $0 }.joined(separator: " ")))
    }
}

/// Il cerchietto "meno" / "più" dello stepper, da solo.
///
/// Sta qui perché lo usa anche il campo "carico previsto" dell'editor, che ha un
/// campo di testo al posto del numero: i due controlli devono avere esattamente
/// lo stesso peso visivo e la stessa area di tocco.
struct ProgramStepperButton: View {

    let systemImage: String
    /// Etichetta VoiceOver completa ("Riduci: carico previsto").
    let label: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 38, height: 38)
                .background(Theme.surface, in: Circle())
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
    }
}

extension ProgramStepper {

    /// Variante per un valore intero in un intervallo chiuso.
    init(
        title: String,
        value: Int,
        unit: String? = nil,
        range: ClosedRange<Int>,
        set: @escaping (Int) -> Void
    ) {
        self.init(
            value: "\(value)",
            unit: unit,
            canDecrease: value > range.lowerBound,
            canIncrease: value < range.upperBound,
            title: title,
            onDecrease: { set(max(range.lowerBound, value - 1)) },
            onIncrease: { set(min(range.upperBound, value + 1)) }
        )
    }
}
