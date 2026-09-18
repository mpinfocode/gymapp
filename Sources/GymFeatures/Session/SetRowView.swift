import SwiftUI
import GymCore
import GymUI

/// Una riga della tabella serie: SERIE · PRECEDENTE · KG · REPS (o TEMPO) · ✓.
///
/// I valori arrivano già precompilati dallo store: il percorso base è toccare ✓.
/// Il long-press apre le opzioni avanzate (tipo serie, RPE, rimuovi).
@MainActor
struct SetRowView: View {

    @Environment(AppEnvironment.self) private var app

    let entryID: UUID
    let setID: UUID
    let measureKind: MeasureKind
    let label: String
    let previous: String
    let isActive: Bool
    let onComplete: () -> Void
    let onOptions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.s) {
                Text(label)
                    .font(.system(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isCompleted ? Theme.accent.deep : Theme.textSecondary)
                    .frame(width: SetTableHeader.setColumnWidth, alignment: .leading)

                Text(previous)
                    .font(.captionText)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .frame(width: SetTableHeader.previousColumnWidth, alignment: .leading)

                cells

                SetCheckButton(
                    isCompleted: completedBinding,
                    accessibilityTitle: "Serie \(label)"
                )
            }

            if !metaText.isEmpty {
                Text(metaText)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(Theme.accent.deep)
                    .padding(.leading, SetTableHeader.setColumnWidth + Theme.Spacing.s)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onLongPressGesture(perform: onOptions)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Celle

    @ViewBuilder
    private var cells: some View {
        switch measureKind {
        case .reps:
            NumberCapsuleField(
                value: weightBinding,
                placeholder: Formatters.missing,
                isCompleted: isCompleted,
                accessibilityTitle: "Carico, serie \(label)"
            )
            NumberCapsuleField(
                value: repsBinding,
                placeholder: Formatters.missing,
                isCompleted: isCompleted,
                accessibilityTitle: "Ripetizioni, serie \(label)"
            )
        case .duration:
            durationCell
        }
    }

    @ViewBuilder
    private var durationCell: some View {
        let stopwatch = SessionSetStopwatch.shared
        let running = stopwatch.isRunning(setID)

        HStack(spacing: Theme.Spacing.s) {
            if running {
                TimelineView(.periodic(from: app.now, by: 0.5)) { _ in
                    Text(Formatters.clock(seconds: stopwatch.elapsed(asOf: app.now)))
                        .font(.cellNumber)
                        .foregroundStyle(Theme.accent.onFill)
                        .frame(minWidth: 64)
                        .frame(height: Theme.Size.minTapTarget)
                        .background(Theme.accent.fill, in: Capsule(style: .continuous))
                }
                .accessibilityLabel(Text("Cronometro in corso, serie \(label)"))
            } else {
                NumberCapsuleField(
                    value: durationBinding,
                    placeholder: Formatters.missing,
                    isCompleted: isCompleted,
                    accessibilityTitle: "Secondi, serie \(label)"
                )
            }

            Button {
                toggleStopwatch(running: running)
            } label: {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text(running ? "Ferma il cronometro" : "Avvia il cronometro"))
        }
    }

    private func toggleStopwatch(running: Bool) {
        let stopwatch = SessionSetStopwatch.shared
        if running {
            let seconds = stopwatch.stop(asOf: app.now)
            app.store.updateSet(id: setID, inEntry: entryID) { $0.durationSec = seconds }
            Haptics.play(.light)
        } else {
            stopwatch.start(setID: setID, now: app.now)
            Haptics.play(.light)
        }
    }

    // MARK: - Stato

    private var currentSet: SetLog? {
        app.store.activeSession?
            .entries.first { $0.id == entryID }?
            .sets.first { $0.id == setID }
    }

    private var isCompleted: Bool { currentSet?.isCompleted ?? false }

    private var metaText: String {
        var parts: [String] = []
        if let kinds = app.store.liveRecords[setID], !kinds.isEmpty { parts.append("Record") }
        if let rpe = currentSet?.rpe { parts.append("RPE \(ItalianNumberFormat.number(rpe))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        if isCompleted {
            shape.fill(Theme.accent.fill.opacity(0.16))
        } else if isActive {
            shape.fill(Theme.background.opacity(0.45))
        } else {
            shape.fill(Color.clear)
        }
    }

    // MARK: - Binding sullo store

    private var weightBinding: Binding<Double?> {
        Binding(
            get: { currentSet?.weightKg },
            set: { newValue in
                app.store.updateSet(id: setID, inEntry: entryID) { $0.weightKg = newValue }
                refreshRecordsIfCompleted()
            }
        )
    }

    private var repsBinding: Binding<Int?> {
        Binding(
            get: { currentSet?.reps },
            set: { newValue in
                app.store.updateSet(id: setID, inEntry: entryID) { $0.reps = newValue }
                refreshRecordsIfCompleted()
            }
        )
    }

    /// Correggere i numeri di una serie **già spuntata** sposta i record: lo store
    /// li ricalcola solo alla spunta, quindi qui si richiede il ricalcolo a mano.
    private func refreshRecordsIfCompleted() {
        guard isCompleted else { return }
        app.store.rebuildLiveRecords()
    }

    private var durationBinding: Binding<Int?> {
        Binding(
            get: { currentSet?.durationSec },
            set: { newValue in
                app.store.updateSet(id: setID, inEntry: entryID) { $0.durationSec = newValue }
            }
        )
    }

    private var completedBinding: Binding<Bool> {
        Binding(
            get: { isCompleted },
            set: { shouldComplete in
                if shouldComplete {
                    if SessionSetStopwatch.shared.isRunning(setID) {
                        let seconds = SessionSetStopwatch.shared.stop(asOf: app.now)
                        app.store.updateSet(id: setID, inEntry: entryID) { $0.durationSec = seconds }
                    }
                    _ = app.store.completeSet(id: setID, inEntry: entryID)
                    onComplete()
                } else {
                    app.store.uncompleteSet(id: setID, inEntry: entryID)
                }
            }
        )
    }
}

/// Intestazione delle colonne della tabella.
@MainActor
struct SetTableHeader: View {

    /// Larghezze condivise con ``SetRowView``: le colonne restano allineate.
    static let setColumnWidth: CGFloat = 30
    static let previousColumnWidth: CGFloat = 78

    let measureKind: MeasureKind

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("SERIE").frame(width: Self.setColumnWidth, alignment: .leading)
            Text("PRECEDENTE").frame(width: Self.previousColumnWidth, alignment: .leading)
            switch measureKind {
            case .reps:
                Text("KG").frame(minWidth: 56)
                Text("REPS").frame(minWidth: 56)
            case .duration:
                Text(MeasureKind.duration.columnTitle).frame(minWidth: 64)
                Spacer().frame(width: Theme.Size.minTapTarget)
            }
            Spacer().frame(width: Theme.Size.minTapTarget)
        }
        .font(.system(.caption2, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, Theme.Spacing.s)
        .accessibilityHidden(true)
    }
}
