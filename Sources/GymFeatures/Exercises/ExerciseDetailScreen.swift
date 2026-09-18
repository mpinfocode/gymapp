import SwiftUI
import GymCore
import GymUI

/// La voce della scheda da cui si è aperto il dettaglio: giorno e riga.
///
/// Serve al blocco "La tua scheda" in testa al dettaglio; senza contesto il
/// dettaglio è quello del catalogo e non mostra nessuna prescrizione.
public struct PlanItemContext: Hashable, Sendable, Identifiable {
    public let programID: UUID
    public let dayID: UUID
    public let itemID: UUID

    public var id: UUID { itemID }

    public init(programID: UUID, dayID: UUID, itemID: UUID) {
        self.programID = programID
        self.dayID = dayID
        self.itemID = itemID
    }
}

/// Da dove si è aperto il dettaglio: cambia soltanto la testa della pagina e il
/// bottone primario, il resto (GIF, muscoli, istruzioni) è sempre lo stesso.
public enum ExerciseDetailPurpose {
    /// Catalogo: bottone "Aggiungi alla scheda" con scelta del giorno.
    case catalog
    /// Aperto da un giorno della scheda: in testa la prescrizione, con il carico
    /// attuale ritoccabile. Nessun bottone primario.
    case plan(PlanItemContext)
    /// Aperto dentro il picker: si guarda la GIF e si conferma con un bottone.
    case picking(isAdded: Bool, add: () -> Void)
}

/// Dettaglio di un esercizio: GIF, zone colpite, attrezzo, preferito, istruzioni
/// (SPEC §5.2). Niente progressi né storico: l'app non registra più le sessioni.
///
/// Riceve solo l'id e lo risolve con `app.store.exercise(id:)`, che unisce libreria
/// ed esercizi personalizzati: così la schermata regge anche un id che arriva da una
/// scheda vecchia e non esiste più in libreria.
public struct ExerciseDetailScreen: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let exerciseID: String
    private let purpose: ExerciseDetailPurpose

    @State private var isAddingToProgram = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var keptInHistory = false

    public init(exerciseID: String) {
        self.init(exerciseID: exerciseID, purpose: .catalog)
    }

    public init(exerciseID: String, purpose: ExerciseDetailPurpose) {
        self.exerciseID = exerciseID
        self.purpose = purpose
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
        // "Recenti" si aggiorna a transizione finita, non durante il push: scrivere
        // nello store mentre la pagina sta entrando invalidava la radice della
        // libreria proprio mentre l'animazione era in corso, e lo scatto si vedeva.
        .task(id: exerciseID) { await markRecentAfterTransition() }
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
            Text("Se è già stato usato resta nelle schede, ma sparisce dalla ricerca.")
        }
    }

    /// Segna l'esercizio fra i recenti **dopo** la transizione di navigazione
    /// (~400 ms, poco più della push di sistema). Se si torna indietro prima, il
    /// task viene cancellato e non si scrive niente.
    private func markRecentAfterTransition() async {
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        app.store.markRecent(exerciseID)
    }

    // MARK: - Contenuto

    @ViewBuilder
    private func content(_ exercise: Exercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                if case .picking = purpose {
                    backBar
                }

                // Aperto da un giorno della scheda: la prescrizione sta in testa,
                // è la ragione per cui si è aperta la pagina in palestra.
                if case .plan(let context) = purpose {
                    PlanPrescriptionCard(context: context)
                }

                media(exercise)
                identity(exercise)

                if keptInHistory {
                    Text("Eliminato. Resta nelle schede che lo usano.")
                        .captionStyle(color: Theme.textTertiary)
                }

                primaryAction

                if !exercise.notes.isEmpty {
                    note(exercise.notes)
                }

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

    /// Nel picker il dettaglio è una sheet: serve una via d'uscita esplicita.
    private var backBar: some View {
        Button("Indietro") { dismiss() }
            .font(.bodyText)
            .foregroundStyle(Theme.textSecondary)
            .buttonStyle(.plain)
            .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)
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
                    accessibilityTitle: "Esecuzione di \(exercise.shortDisplayName)",
                    // La thumbnail della riga da cui si arriva è già decodificata in
                    // memoria: la tile si riempie subito invece di partire da un
                    // riquadro vuoto mentre la GIF si scarica.
                    posterURL: exercise.imageURL
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func initial(of exercise: Exercise) -> String {
        String(exercise.shortDisplayName.prefix(1)).uppercased()
    }

    // MARK: - Nome, muscoli, azioni

    private func identity(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(exercise.shortDisplayName)
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

    // MARK: - Azione principale

    @ViewBuilder
    private var primaryAction: some View {
        switch purpose {
        case .catalog:
            if canAddToProgram {
                PrimaryButton("Aggiungi alla scheda", systemImage: "plus") {
                    isAddingToProgram = true
                }
            }
        case .picking(let isAdded, let add):
            if isAdded {
                PrimaryButton("Già nella scheda") {}
                    .disabled(true)
                    .opacity(0.4)
            } else {
                PrimaryButton("Aggiungi alla scheda", systemImage: "plus") {
                    add()
                    dismiss()
                }
            }
        case .plan:
            EmptyView()
        }
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
