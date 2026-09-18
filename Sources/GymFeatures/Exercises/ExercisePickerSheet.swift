import SwiftUI
import GymCore
import GymUI

/// Picker esercizi riusabile: lo aprono l'editor della scheda (aggiunta multipla)
/// e la sessione attiva (aggiungi / sostituisci esercizio).
///
/// Ricerca, chip e filtri sono **gli stessi** del catalogo (``ExerciseBrowser``).
/// Chi lo apre resta responsabile della chiusura: `onPick` viene chiamato con gli
/// esercizi scelti (uno solo se `allowsMultipleSelection` è `false`); se l'utente
/// annulla, `onPick` non viene chiamato.
public struct ExercisePickerSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let title: String
    private let allowsMultipleSelection: Bool
    private let excludedIDs: Set<String>
    private let onPick: ([Exercise]) -> Void

    @State private var model = ExerciseSearchModel()
    /// Id scelti, nell'ordine di selezione (è l'ordine promesso a chi apre il picker).
    @State private var selection: [String] = []
    @State private var preview: PreviewTarget?
    @State private var isCreatingCustom = false
    @State private var prefilledName = ""

    /// - Parameters:
    ///   - title: titolo della sheet ("Aggiungi esercizi", "Sostituisci").
    ///   - allowsMultipleSelection: selezione multipla con conferma, invece del tocco singolo.
    ///   - excludedIDs: esercizi già presenti nel giorno o nella sessione.
    ///   - onPick: esercizi scelti, nell'ordine di selezione.
    public init(
        title: String,
        allowsMultipleSelection: Bool,
        excludedIDs: Set<String>,
        onPick: @escaping ([Exercise]) -> Void
    ) {
        self.title = title
        self.allowsMultipleSelection = allowsMultipleSelection
        self.excludedIDs = excludedIDs
        self.onPick = onPick
    }

    public var body: some View {
        ExerciseBrowser(
            model: $model,
            onCreateCustom: { name in
                prefilledName = name
                isCreatingCustom = true
            },
            header: { header },
            row: { row($0) }
        )
        .pageBackground()
        .safeAreaInset(edge: .bottom) { confirmBar }
        .sheet(item: $preview) { target in
            NavigationStack {
                ExerciseDetailScreen(exerciseID: target.id)
            }
        }
        .sheet(isPresented: $isCreatingCustom) {
            CustomExerciseFormSheet(prefilledName: prefilledName) { created in
                pick([created])
            }
        }
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Button("Annulla") { dismiss() }
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)

                Spacer(minLength: Theme.Spacing.s)

                Button {
                    prefilledName = model.trimmedQuery
                    isCreatingCustom = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Crea esercizio personalizzato"))
            }

            Text(title)
                .sectionTitleStyle()
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Riga

    @ViewBuilder
    private func row(_ exercise: Exercise) -> some View {
        if excludedIDs.contains(exercise.id) {
            ExerciseRowView(exercise: exercise) {
                Text("già presente")
                    .captionStyle(color: Theme.textTertiary)
            }
            .opacity(0.45)
            .accessibilityValue(Text("già presente"))
        } else {
            Button {
                toggle(exercise)
            } label: {
                ExerciseRowView(exercise: exercise) {
                    if allowsMultipleSelection {
                        Image(systemName: isSelected(exercise) ? "checkmark.circle.fill" : "circle")
                            .font(.system(.title3, weight: .regular))
                            .foregroundStyle(isSelected(exercise) ? Theme.accent.deep : Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Anteprima") { preview = PreviewTarget(id: exercise.id) }
            }
            .accessibilityAddTraits(isSelected(exercise) ? [.isButton, .isSelected] : .isButton)
        }
    }

    private func isSelected(_ exercise: Exercise) -> Bool {
        selection.contains(exercise.id)
    }

    private func toggle(_ exercise: Exercise) {
        guard allowsMultipleSelection else {
            pick([exercise])
            return
        }
        if let index = selection.firstIndex(of: exercise.id) {
            selection.remove(at: index)
        } else {
            selection.append(exercise.id)
        }
        Haptics.play(.selection)
    }

    // MARK: - Conferma

    @ViewBuilder
    private var confirmBar: some View {
        if allowsMultipleSelection, !selection.isEmpty {
            PrimaryButton("Aggiungi (\(selection.count))") {
                pick(selection.compactMap { app.store.exercise(id: $0) })
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.m)
            .background(Theme.background)
        }
    }

    private func pick(_ exercises: [Exercise]) {
        guard !exercises.isEmpty else { return }
        for exercise in exercises {
            app.store.markRecent(exercise.id)
        }
        Haptics.play(.success)
        onPick(exercises)
    }
}

/// Esercizio di cui mostrare l'anteprima senza uscire dal picker.
private struct PreviewTarget: Identifiable, Hashable {
    let id: String
}
