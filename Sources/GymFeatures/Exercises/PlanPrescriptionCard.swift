import SwiftUI
import GymCore
import GymUI

/// Blocco "La tua scheda" in testa al dettaglio, quando l'esercizio è stato aperto
/// da un giorno della scheda (SPEC §0, "Schermata del giorno").
///
/// Dice la prescrizione dell'istruttore in una riga e lascia ritoccare **solo** il
/// carico attuale: −/+ al passo dell'attrezzo (``WeightStep``) oppure digitando. Si
/// salva subito, non c'è nessuno storico dei carichi.
struct PlanPrescriptionCard: View {

    @Environment(AppEnvironment.self) private var app

    let context: PlanItemContext

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("La tua scheda").overlineStyle()

                Text(prescription(item))
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                weightRow(item)

                if !item.note.isEmpty {
                    Text(item.note)
                        .captionStyle(color: Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Theme.separator)
            }
        }
    }

    // MARK: - Prescrizione

    /// "4 × 6-8 · recupero 2:30".
    private func prescription(_ item: PlanItem) -> String {
        var parts = ["\(item.targetSets) × \(ProgramPresentation.measureText(item.measure))"]
        if item.restSeconds > 0 {
            parts.append("recupero " + ProgramPresentation.seconds(item.restSeconds))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Carico attuale

    private func weightRow(_ item: PlanItem) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Carico")
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: Theme.Spacing.s)

            ProgramStepperButton(
                systemImage: "minus",
                label: "Riduci: carico",
                isEnabled: previousWeight(item) != nil
            ) {
                guard let value = previousWeight(item) else { return }
                update { $0.targetWeightKg = value }
            }

            NumberCapsuleField(
                value: Binding(
                    get: { item.targetWeightKg.map { app.unit.value(fromKilograms: $0) } },
                    set: { newValue in
                        update { $0.targetWeightKg = newValue.map { app.unit.kilograms(from: $0) } }
                    }
                ),
                placeholder: Formatters.missing,
                accessibilityTitle: "Carico attuale"
            )
            .frame(width: 96)

            Text(app.unit.symbol)
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)

            ProgramStepperButton(
                systemImage: "plus",
                label: "Aumenta: carico",
                isEnabled: nextWeight(item) != nil
            ) {
                guard let value = nextWeight(item) else { return }
                update { $0.targetWeightKg = value }
            }
        }
        .frame(minHeight: Theme.Size.minTapTarget)
    }

    /// Attrezzo dell'esercizio, per il passo di carico (manubri +2, bilanciere +2,5,
    /// macchine +5). Sconosciuto → passo generico di 2,5 kg.
    private func equipment(of item: PlanItem) -> String {
        app.store.exercise(id: item.exerciseID)?.equipment ?? ""
    }

    private func nextWeight(_ item: PlanItem) -> Double? {
        WeightStep.next(after: item.targetWeightKg ?? 0, forEquipment: equipment(of: item))
    }

    private func previousWeight(_ item: PlanItem) -> Double? {
        guard let current = item.targetWeightKg else { return nil }
        return WeightStep.previous(before: current, forEquipment: equipment(of: item))
    }

    // MARK: - Stato

    private var item: PlanItem? {
        app.store.program(id: context.programID)?
            .day(id: context.dayID)?
            .items.first { $0.id == context.itemID }
    }

    private func update(_ change: (inout PlanItem) -> Void) {
        guard var updated = item else { return }
        change(&updated)
        app.store.updateItem(updated, inDay: context.dayID, inProgram: context.programID)
    }
}
