import Foundation
import SwiftUI
import GymCore
import GymUI

/// Dettaglio di una sessione dello storico: esercizi, serie, volume, note, con
/// eliminazione dal menu "…" (SPEC §5.5). Tema chiaro, a differenza del riepilogo
/// di fine allenamento.
public struct SessionDetailScreen: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let sessionID: UUID

    @State private var isConfirmingDelete = false

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    public var body: some View {
        Group {
            if let session = app.store.session(id: sessionID) {
                content(session)
            } else {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "Allenamento non disponibile",
                    message: "Questa sessione non è più nello storico."
                )
                .frame(maxHeight: .infinity)
            }
        }
        .pageBackground()
        .alert("Eliminare l'allenamento?", isPresented: $isConfirmingDelete) {
            Button("Elimina", role: .destructive) {
                app.store.deleteSession(id: sessionID)
                dismiss()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le serie registrate verranno rimosse dallo storico e dalle statistiche.")
        }
    }

    // MARK: - Contenuto

    @ViewBuilder
    private func content(_ session: WorkoutSession) -> some View {
        let records = RecordTimeline.records(
            inSession: session.id,
            events: RecordTimeline.events(in: app.store.sessions)
        )

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                header(session)
                stats(session)

                if !session.notes.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Nota")
                                .overlineStyle()
                            Text(session.notes)
                                .font(.bodyText)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }

                ForEach(session.entries) { entry in
                    exerciseBlock(entry, records: records)
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
    }

    private func header(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Formatters.longDateUppercased(session.startedAt, calendar: app.calendar))
                .overlineStyle()

            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                Text(session.name)
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: Theme.Spacing.s)

                EllipsisMenu(accessibilityTitle: "Azioni sull'allenamento") {
                    Button("Elimina", role: .destructive) { isConfirmingDelete = true }
                }
            }
        }
    }

    private func stats(_ session: WorkoutSession) -> some View {
        Card {
            StatTriple(items: [
                StatTriple.Item(label: "Durata", value: Formatters.minutes(session.duration)),
                StatTriple.Item(label: "Volume", value: Formatters.volume(session.totalVolumeKg, unit: app.unit)),
                StatTriple.Item(label: "Serie", value: "\(session.completedSets)"),
            ])
        }
    }

    // MARK: - Esercizi

    @ViewBuilder
    private func exerciseBlock(_ entry: SessionEntry, records: [String: Double]) -> some View {
        let sets = entry.sets.filter(\.isCompleted)
        // Una sola etichetta "Record" per esercizio: la serie che ha firmato il primato.
        let recordSetID = records[entry.exerciseID].flatMap { weight in
            sets.first { $0.isWorkingSet && ($0.weightKg ?? 0) >= weight }?.id
        }
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            exerciseRow(entry, sets: sets)

            if sets.isEmpty {
                Text("Nessuna serie completata")
                    .captionStyle(color: Theme.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                        setRow(
                            set,
                            position: index + 1,
                            measure: entry.measureKind,
                            isRecord: set.id == recordSetID,
                            showsSeparator: set.id != sets.last?.id
                        )
                    }
                }
            }

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(_ entry: SessionEntry, sets: [SetLog]) -> some View {
        let subtitle = "\(sets.count) serie · \(Formatters.volume(entry.volumeKg, unit: app.unit))"
        if let exercise = app.exercise(id: entry.exerciseID) {
            NavigationLink(value: AppRoute.exercise(id: entry.exerciseID)) {
                ExerciseRowView(exercise: exercise, subtitle: subtitle) {
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.store.exerciseDisplayName(id: entry.exerciseID))
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func setRow(
        _ set: SetLog,
        position: Int,
        measure: MeasureKind,
        isRecord: Bool,
        showsSeparator: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                Text("\(position)\(set.kind.symbol)")
                    .font(.system(.footnote, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, alignment: .leading)

                Text(setText(set, measure: measure))
                    .font(.cellNumber)
                    .foregroundStyle(Theme.textPrimary)

                if let rpe = set.rpe {
                    Text("RPE \(Formatters.decimal(rpe))")
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.s)

                if isRecord {
                    Text("Record")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.Metric.rosa.onFill)
                        .padding(.horizontal, Theme.Spacing.s + 2)
                        .padding(.vertical, 4)
                        .background(Theme.Metric.rosa.fill, in: Capsule(style: .continuous))
                }
            }
            .frame(minHeight: Theme.Size.minTapTarget)
            .accessibilityElement(children: .combine)

            if showsSeparator {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.Size.hairline)
            }
        }
    }

    /// "80 kg × 8" oppure "00:45".
    private func setText(_ set: SetLog, measure: MeasureKind) -> String {
        switch measure {
        case .reps:
            let weight = set.weightKg.map { Formatters.weight($0, unit: app.unit) } ?? Formatters.missing
            let reps = set.reps.map { "\($0)" } ?? Formatters.missing
            return "\(weight) × \(reps)"
        case .duration:
            guard let seconds = set.durationSec else { return Formatters.missing }
            return Formatters.clock(seconds: seconds)
        }
    }
}
