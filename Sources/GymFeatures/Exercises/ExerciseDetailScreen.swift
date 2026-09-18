import SwiftUI
import GymCore
import GymUI

/// Dettaglio di un esercizio: movimento, muscoli, istruzioni, progressi personali
/// e "Aggiungi alla scheda" (SPEC §5.2).
///
/// Riceve solo l'id e lo risolve con `app.store.exercise(id:)`, che unisce libreria
/// ed esercizi personalizzati: così la schermata regge anche un id che arriva dallo
/// storico e non esiste più in libreria.
public struct ExerciseDetailScreen: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let exerciseID: String

    @State private var isAddingToProgram = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var keptInHistory = false

    public init(exerciseID: String) {
        self.exerciseID = exerciseID
    }

    public var body: some View {
        Group {
            if let exercise = app.store.exercise(id: exerciseID) {
                content(exercise)
            } else {
                EmptyStateView(
                    systemImage: "figure.strengthtraining.traditional",
                    title: "Esercizio non disponibile",
                    message: "Questo esercizio non è più in libreria."
                )
                .frame(maxHeight: .infinity)
            }
        }
        .pageBackground()
        .onAppear { app.store.markRecent(exerciseID) }
        .sheet(isPresented: $isAddingToProgram) {
            if let exercise = app.store.exercise(id: exerciseID) {
                AddToProgramSheet(exercise: exercise)
            }
        }
        .sheet(isPresented: $isEditing) {
            CustomExerciseFormSheet(editing: app.store.customExercise(id: exerciseID))
        }
        .alert("Eliminare l'esercizio?", isPresented: $isConfirmingDelete) {
            Button("Elimina", role: .destructive, action: delete)
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Se è già stato usato resta nello storico e nelle schede, ma sparisce dalla ricerca.")
        }
    }

    // MARK: - Contenuto

    @ViewBuilder
    private func content(_ exercise: Exercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                media(exercise)
                identity(exercise)

                if keptInHistory {
                    Text("Eliminato. Resta nello storico e nelle schede che lo usano.")
                        .captionStyle(color: Theme.textTertiary)
                }

                if canAddToProgram {
                    PrimaryButton("Aggiungi alla scheda", systemImage: "plus") {
                        isAddingToProgram = true
                    }
                }

                if !exercise.notes.isEmpty {
                    note(exercise.notes)
                }

                ExerciseProgressSection(exerciseID: exercise.id)

                if !exercise.steps.isEmpty {
                    steps(exercise.steps)
                }

                if !exercise.isCustom {
                    Text(Exercise.displayAttribution)
                        .captionStyle(color: Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
    }

    // MARK: - Movimento

    @ViewBuilder
    private func media(_ exercise: Exercise) -> some View {
        HStack {
            Spacer(minLength: 0)
            if exercise.isCustom {
                MediaTile(cornerRadius: Theme.Radius.medium, inset: Theme.Spacing.s) {
                    Text(initial(of: exercise))
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(Theme.onPastel.opacity(0.28))
                        .frame(
                            width: Theme.Size.maxMediaSide - Theme.Spacing.s * 2,
                            height: Theme.Size.maxMediaSide - Theme.Spacing.s * 2
                        )
                        .accessibilityHidden(true)
                }
                .frame(width: Theme.Size.maxMediaSide, height: Theme.Size.maxMediaSide)
            } else {
                AnimatedGIFView(
                    url: exercise.gifURL,
                    side: Theme.Size.maxMediaSide,
                    accessibilityTitle: "Esecuzione di \(exercise.displayName)"
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func initial(of exercise: Exercise) -> String {
        String(exercise.displayName.prefix(1)).uppercased()
    }

    // MARK: - Nome, muscoli, azioni

    private func identity(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(exercise.displayName)
                        .sectionTitleStyle()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(ExerciseRowView<EmptyView>.defaultSubtitle(for: exercise))
                        .font(.bodyText)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.s)

                favoriteButton
                if exercise.isCustom {
                    customMenu
                }
            }

            let secondary = exercise.localizedSecondaryMuscles
            if !secondary.isEmpty {
                Text("Secondari: \(secondary.joined(separator: ", "))")
                    .captionStyle(color: Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var favoriteButton: some View {
        let isFavorite = app.store.isFavorite(exerciseID)
        return Button {
            _ = app.store.toggleFavorite(exerciseID)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isFavorite ? Theme.Metric.rosa.deep : Theme.textSecondary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .haptic(.light, trigger: isFavorite)
        .accessibilityLabel(Text("Preferito"))
        .accessibilityAddTraits(isFavorite ? [.isButton, .isSelected] : .isButton)
    }

    private var customMenu: some View {
        Menu {
            Button("Modifica") { isEditing = true }
            Button("Elimina", role: .destructive) { isConfirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Azioni sull'esercizio"))
    }

    // MARK: - Nota e istruzioni

    private func note(_ text: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Nota")
                    .overlineStyle()
                Text(text)
                    .font(.bodyText)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func steps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Esecuzione")
                .overlineStyle()

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                    Text("\(index + 1)")
                        .font(.system(.footnote, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 18, alignment: .trailing)

                    Text(step)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Azioni

    private var canAddToProgram: Bool {
        guard let program = app.store.activeProgram else { return false }
        return !program.days.isEmpty
    }

    private func delete() {
        let outcome = app.store.deleteCustomExercise(id: exerciseID)
        switch outcome {
        case .archived:
            keptInHistory = true
        case .removed, .notFound:
            dismiss()
        }
    }
}
