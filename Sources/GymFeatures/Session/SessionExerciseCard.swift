import SwiftUI
import GymCore
import GymUI

/// Un esercizio della sessione.
///
/// Fisarmonica: chiuso è una riga compatta (nome e serie fatte), aperto mostra
/// GIF, obiettivo della scheda, nota, hint di progressione e tabella serie.
/// Un solo esercizio è aperto alla volta: è quello "in primo piano".
@MainActor
struct SessionExerciseCard: View {

    @Environment(AppEnvironment.self) private var app

    let entry: SessionEntry
    let isExpanded: Bool
    let onExpand: () -> Void
    let onComplete: (UUID) -> Void
    let onAction: (SessionEntryAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header
            if isExpanded {
                details
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isExpanded ? Theme.surfaceElevated : Theme.surface.opacity(0.55))
        )
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            if !isExpanded {
                RemoteImage(
                    url: exercise?.imageURL,
                    side: 44,
                    cornerRadius: Theme.Radius.small,
                    inset: 3,
                    showsBorder: false
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(isExpanded ? .sectionTitle : .bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(isExpanded ? targetLine : setsSummary)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                menu
            } else if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.accent.deep)
                    .accessibilityLabel(Text("Completato"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isExpanded { onExpand() } }
        .accessibilityElement(children: .contain)
    }

    private var menu: some View {
        Menu {
            Button("Nota esercizio") { onAction(.note(entry.id)) }
            Button("Aggiungi serie") { onAction(.addSet(entry.id)) }
            Button("Sostituisci esercizio") { onAction(.replace(entry.id)) }
            Button("Sposta su") { onAction(.moveUp(entry.id)) }
            Button("Sposta giù") { onAction(.moveDown(entry.id)) }
            Button("Rimuovi esercizio", role: .destructive) { onAction(.remove(entry.id)) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Altre opzioni per \(name)"))
    }

    // MARK: - Contenuto aperto

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                Button {
                    onAction(.instructions(entry.exerciseID))
                } label: {
                    AnimatedGIFView(
                        url: exercise?.gifURL,
                        side: 120,
                        cornerRadius: Theme.Radius.medium,
                        showsBorder: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Istruzioni di \(name)"))

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if entry.note.isEmpty {
                        Text(secondaryLine)
                            .font(.captionText)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(entry.note)
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let hint {
                Text(hint)
                    .font(.captionText)
                    .foregroundStyle(Theme.accent.deep)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SetTableHeader(measureKind: entry.measureKind)

            VStack(spacing: 2) {
                ForEach(entry.sets) { set in
                    SetRowView(
                        entryID: entry.id,
                        setID: set.id,
                        measureKind: entry.measureKind,
                        label: labels[set.id] ?? "",
                        previous: previousText(for: set),
                        isActive: set.id == activeSetID,
                        onComplete: { onComplete(entry.id) },
                        onOptions: { onAction(.setOptions(entry.id, set.id)) }
                    )
                }
            }

            Button {
                onAction(.addSet(entry.id))
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Aggiungi serie")
                        .font(.captionText)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Theme.Size.minTapTarget)
                .padding(.horizontal, Theme.Spacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Dati derivati

    private var exercise: Exercise? { app.store.exercise(id: entry.exerciseID) }

    private var name: String { app.store.exerciseDisplayName(id: entry.exerciseID) }

    private var planItem: PlanItem? {
        guard let itemID = entry.planItemID,
              let programID = app.store.activeSession?.programID,
              let program = app.store.program(id: programID) else { return nil }
        return program.item(id: itemID)
    }

    private var targetLine: String {
        SessionPresentation.targetLine(entry: entry, item: planItem, unit: app.unit)
    }

    private var secondaryLine: String {
        guard let exercise else { return targetLine }
        return [exercise.localizedTarget, exercise.localizedEquipment]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var setsSummary: String {
        let done = entry.completedSets
        return "\(done) di \(entry.sets.count) serie"
    }

    private var isDone: Bool {
        !entry.sets.isEmpty && entry.sets.allSatisfy(\.isCompleted)
    }

    private var labels: [UUID: String] {
        SessionPresentation.setLabels(for: entry)
    }

    private var activeSetID: UUID? {
        entry.sets.first { !$0.isCompleted }?.id
    }

    private var previous: Stats.PreviousPerformance? {
        app.store.previousPerformance(for: entry.exerciseID)
    }

    private func previousText(for set: SetLog) -> String {
        // Sulle serie di riscaldamento la colonna resta vuota: il "precedente"
        // registrato riguarda solo le serie di lavoro.
        guard set.kind.countsTowardVolume else { return Formatters.missing }
        return SessionPresentation.previousText(
            previous,
            position: SessionPresentation.workingPosition(of: set.id, in: entry),
            kind: entry.measureKind,
            unit: app.unit
        )
    }

    /// Hint di progressione: una riga discreta, solo se lo store lo propone.
    ///
    /// Il testo viene riscritto qui perché `reason` di GymCore usa il punto
    /// decimale, mentre la UI vuole la virgola italiana.
    private var hint: String? {
        guard let planItem,
              let suggestion = app.store.progressionSuggestion(for: planItem) else { return nil }
        // Due decimali: gli incrementi da 1,25 kg dei manubri devono restare esatti.
        let value = Formatters.decimal(app.unit.value(fromKilograms: suggestion.suggestedWeightKg), fractionDigits: 2)
        return "Ultima volta hai chiuso tutte le serie: prova \(value) \(app.unit.symbol)."
    }
}

/// Azioni avanzate su un esercizio della sessione, risolte dalla schermata.
enum SessionEntryAction {
    case instructions(String)
    case note(UUID)
    case addSet(UUID)
    case replace(UUID)
    case remove(UUID)
    case moveUp(UUID)
    case moveDown(UUID)
    case setOptions(UUID, UUID)
}
