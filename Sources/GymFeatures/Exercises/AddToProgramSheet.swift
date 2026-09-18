import SwiftUI
import GymCore
import GymUI

/// "Aggiungi alla scheda": si sceglie solo il giorno della scheda attiva.
///
/// Serie, ripetizioni e recupero partono da un valore sensato (vedi ``PlanDefaults``)
/// e si correggono dall'editor della scheda: qui servirebbero solo a rallentare.
struct AddToProgramSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                if let program = app.store.activeProgram, !program.days.isEmpty {
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(program.days) { day in
                            dayRow(day, in: program)
                        }
                    }

                    Text(PlanDefaults.summary(for: exercise))
                        .captionStyle(color: Theme.textTertiary)
                } else {
                    Text("Nessuna scheda attiva.")
                        .captionStyle()
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button("Annulla") { dismiss() }
                .font(.bodyText)
                .foregroundStyle(Theme.textSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Aggiungi alla scheda")
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)
                Text(exercise.displayName)
                    .captionStyle()
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ day: ProgramDay, in program: Program) -> some View {
        let isPresent = day.items.contains { $0.exerciseID == exercise.id }
        PillRow(
            title: day.name,
            subtitle: itemsText(day.items.count),
            detail: isPresent ? "già presente" : nil,
            showsChevron: !isPresent,
            action: isPresent ? nil : { add(to: day, in: program) }
        )
        .opacity(isPresent ? 0.5 : 1)
    }

    private func itemsText(_ count: Int) -> String {
        count == 1 ? "1 esercizio" : "\(count) esercizi"
    }

    private func add(to day: ProgramDay, in program: Program) {
        let suggestion = PlanDefaults.suggestion(for: exercise)
        app.store.addItem(
            exerciseID: exercise.id,
            toDay: day.id,
            inProgram: program.id,
            targetSets: suggestion.sets,
            measure: suggestion.measure
        )
        Haptics.play(.success)
        dismiss()
    }
}
