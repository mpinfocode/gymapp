import SwiftUI
import GymCore
import GymUI

/// L'anteprima della bozza: il nome, i giorni con i loro esercizi, la
/// ripartizione dei muscoli colpiti, e le tre azioni.
///
/// La bozza **non è ancora salvata**: il ``Program`` si costruisce qui solo per
/// poterlo leggere (la distribuzione muscolare lavora su un `Program`, non su
/// una bozza) e finisce nello store soltanto con "Usa questa scheda".
struct GeneratorPreviewPage: View {

    @Environment(AppEnvironment.self) private var app

    @Bindable var model: GeneratorFlowModel
    let result: ProgramGenerationResult

    let onCancel: () -> Void
    let onRegenerate: () -> Void
    let onUse: () -> Void

    /// Ripartizione della bozza: calcolata in `.task`, mai nel `body`.
    @State private var distribution: Stats.MuscleDistribution?
    @State private var openedExerciseID: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "La tua scheda", actionTitle: "Annulla", action: onCancel)
                .sheetHeaderMargins()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    origin
                    nameField
                    days
                    muscles
                    repairsNote
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            actions
        }
        .pageBackground()
        .keyboardDismissOnTap()
        .task(id: result.draft) { build() }
        .sheet(item: Binding(
            get: { openedExerciseID.map(OpenedExercise.init(id:)) },
            set: { openedExerciseID = $0?.id }
        )) { opened in
            ExerciseDetailScreen(exerciseID: opened.id, purpose: .reference)
                .environment(app)
        }
    }

    // MARK: - Provenienza

    /// Etichetta discreta: da dove viene questa bozza.
    private var origin: some View {
        Text(result.source.displayName)
            .font(.overline)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textTertiary)
    }

    // MARK: - Nome

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Nome").overlineStyle()

            TextField("Scheda", text: $model.draftName)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .padding(.horizontal, Theme.Spacing.l)
                .frame(height: 52)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: Capsule(style: .continuous))
                .accessibilityLabel(Text("Nome della scheda"))
        }
    }

    // MARK: - Giorni

    private var days: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ForEach(Array(result.draft.days.enumerated()), id: \.offset) { _, day in
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(day.name)
                            .font(.bodyEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.Spacing.s)
                        Text(ProgramPresentation.exerciseCount(day.items.count))
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(spacing: Theme.Spacing.m) {
                        ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                            row(item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: GeneratedProgramDraft.Item) -> some View {
        if let exercise = app.store.exercise(id: item.id) {
            Button {
                openedExerciseID = item.id
            } label: {
                ExerciseRowView(
                    presentation: app.rowPresentation(for: exercise),
                    imageURL: exercise.imageURL,
                    subtitle: subtitle(item)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Apre il dettaglio dell'esercizio"))
        }
    }

    /// "3 × 8-12 · 1:30", con la nota del modello sotto se c'è.
    private func subtitle(_ item: GeneratedProgramDraft.Item) -> String {
        var parts = ["\(item.sets) × \(ProgramPresentation.measureText(item.measure))"]
        if item.rest > 0 { parts.append(ProgramPresentation.seconds(item.rest)) }
        let summary = parts.joined(separator: " · ")
        guard let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return summary
        }
        return summary + " · " + note
    }

    // MARK: - Muscoli colpiti

    @ViewBuilder
    private var muscles: some View {
        if let distribution {
            MuscleDistributionSummary(distribution: distribution)
        }
    }

    // MARK: - Riparazioni

    /// Avviso discreto: una riga, non un elenco di rimproveri al modello.
    @ViewBuilder
    private var repairsNote: some View {
        if !result.repairs.isEmpty {
            Text(Self.repairsText(result.repairs.count))
                .font(.captionText)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func repairsText(_ count: Int) -> String {
        count == 1
            ? "Un dettaglio è stato sistemato in automatico."
            : "\(count) dettagli sono stati sistemati in automatico."
    }

    // MARK: - Azioni

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            PrimaryButton("Usa questa scheda") {
                nameFocused = false
                onUse()
            }
            PillButton("Rigenera", systemImage: "arrow.clockwise") {
                nameFocused = false
                onRegenerate()
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.m)
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Calcolo fuori dal body

    /// La ripartizione si calcola sul ``Program`` in bozza, **senza salvarlo**:
    /// ``Stats`` lavora sulle voci di scheda, non sul JSON del modello.
    private func build() {
        distribution = app.store.muscleDistribution(for: result.program(now: app.now))
    }
}

/// Esercizio aperto in consultazione dall'anteprima.
private struct OpenedExercise: Identifiable, Hashable {
    let id: String
}
