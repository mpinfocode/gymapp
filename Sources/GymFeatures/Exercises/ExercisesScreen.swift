import SwiftUI
import GymCore
import GymUI

/// Tab **Esercizi**: ricerca, chip della zona colpita con i conteggi, lista con
/// thumbnail (SPEC §5.2).
///
/// Ricerca, chip e filtri vivono in ``ExerciseBrowser``, che è lo stesso
/// componente usato dal picker: qui si aggiungono solo il titolo e i link al
/// dettaglio (`AppRoute.exercise(id:)`, destinazione già installata da `RootView`).
public struct ExercisesScreen: View {

    @Environment(AppEnvironment.self) private var app

    @State private var model: ExerciseSearchModel
    @State private var isCreatingCustom = false
    @State private var prefilledName = ""

    public init() {
        _model = State(initialValue: ExerciseSearchModel())
    }

    /// Init con ricerca e filtri già impostati: la usano gli screenshot per
    /// fotografare la schermata in uno stato preciso.
    public init(preset: ExerciseSearchModel) {
        _model = State(initialValue: preset)
    }

    public var body: some View {
        ExerciseBrowser(
            model: $model,
            onCreateCustom: { name in
                prefilledName = name
                isCreatingCustom = true
            },
            header: { header },
            row: { exercise in
                NavigationLink(value: AppRoute.exercise(id: exercise.id)) {
                    ExerciseRowView(exercise: exercise) {
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        )
        .pageBackground()
        .sheet(isPresented: $isCreatingCustom) {
            CustomExerciseFormSheet(prefilledName: prefilledName) { created in
                model.query = created.displayName
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text("Esercizi")
                .greetingStyle()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Theme.Spacing.s)

            // Stesso trattamento del bottone filtri: cerchio `surface` da 44pt.
            // Creare un esercizio è un'azione rara, non merita una capsula ink.
            Button {
                prefilledName = ""
                isCreatingCustom = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Nuovo esercizio personalizzato"))
        }
    }
}
