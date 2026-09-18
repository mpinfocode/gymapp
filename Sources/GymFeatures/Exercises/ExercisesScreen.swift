import SwiftUI
import GymCore
import GymUI

/// Tab **Esercizi**: la radice è la ricerca più l'elenco delle zone colpite, non una
/// lista da 1.324 righe (SPEC §0, "Esercizi senza lista infinita").
///
/// Ricerca e zone vivono in ``ExerciseLibraryRoot``, lo stesso componente usato dal
/// picker della scheda: qui si aggiungono solo il titolo, il link al dettaglio
/// (`AppRoute.exercise(id:)`, destinazione installata da `RootView`) e la pagina
/// della zona.
public struct ExercisesScreen: View {

    @Environment(AppEnvironment.self) private var app

    @State private var model: ExerciseSearchModel
    @State private var isCreatingCustom = false
    @State private var prefilledName = ""

    public init() {
        _model = State(initialValue: ExerciseSearchModel())
    }

    /// Init con ricerca già impostata: la usano gli screenshot per fotografare la
    /// schermata in uno stato preciso.
    public init(preset: ExerciseSearchModel) {
        _model = State(initialValue: preset)
    }

    public var body: some View {
        ExerciseLibraryRoot(
            model: $model,
            scrollTopTab: .exercises,
            // La pagina della zona è una rotta condivisa, non una
            // `navigationDestination(item:)` locale: così il ritocco dell'icona
            // "Esercizi" (che svuota il path del tab) la chiude davvero.
            onOpen: { app.router.push(.exerciseGroup($0)) },
            onCreateCustom: { name in
                prefilledName = name
                isCreatingCustom = true
            },
            header: { header },
            row: { exercise in
                NavigationLink(value: AppRoute.exercise(id: exercise.id)) {
                    ExerciseRowView(
                        presentation: app.rowPresentation(for: exercise),
                        imageURL: exercise.imageURL
                    ) {
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

            // Stesso trattamento del resto della testata: cerchio `surface` da 44pt.
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

/// Gli esercizi di una zona colpita (o dei preferiti, o i propri), con i chip per
/// attrezzo. Ci si arriva dalla radice di Esercizi.
public struct ExerciseGroupScreen: View {

    @Environment(AppEnvironment.self) private var app

    private let section: ExerciseSection

    @State private var equipment: Set<String> = []

    public init(section: ExerciseSection) {
        self.section = section
    }

    public var body: some View {
        ExerciseGroupList(
            section: section,
            equipment: $equipment,
            header: {
                Text(section.title)
                    .greetingStyle()
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            row: { exercise in
                NavigationLink(value: AppRoute.exercise(id: exercise.id)) {
                    ExerciseRowView(
                        presentation: app.rowPresentation(for: exercise),
                        imageURL: exercise.imageURL
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        )
        .pageBackground()
        .navigationBarTitleDisplayModeInline()
    }
}
