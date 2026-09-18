import Foundation
import GymCore

/// Logica di presentazione della sessione: funzioni pure, nessuna view, nessun
/// dominio duplicato (i calcoli veri stanno in `Stats`).
enum SessionPresentation {

    // MARK: - Etichette delle serie

    /// Etichette della colonna SERIE: le serie di riscaldamento diventano "R",
    /// le altre sono numerate da 1 indipendentemente dal riscaldamento.
    static func setLabels(for entry: SessionEntry) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        var working = 0
        for set in entry.sets {
            switch set.kind {
            case .warmup:
                labels[set.id] = SetKind.warmup.symbol
            case .normal:
                working += 1
                labels[set.id] = "\(working)"
            case .drop, .failure:
                working += 1
                labels[set.id] = "\(working)\(set.kind.symbol)"
            }
        }
        return labels
    }

    /// Posizione della serie fra quelle di lavoro (serve per la colonna PRECEDENTE).
    static func workingPosition(of setID: UUID, in entry: SessionEntry) -> Int {
        var position = 0
        for set in entry.sets {
            if set.id == setID { return position }
            if set.kind.countsTowardVolume { position += 1 }
        }
        return position
    }

    // MARK: - Colonna PRECEDENTE

    /// Testo della colonna PRECEDENTE ("80 × 8", "45 s"); ``Formatters/missing`` se non c'è storico.
    static func previousText(
        _ previous: Stats.PreviousPerformance?,
        position: Int,
        kind: MeasureKind,
        unit: WeightUnit
    ) -> String {
        guard let previous, !previous.sets.isEmpty else { return Formatters.missing }
        let set = previous.sets.indices.contains(position) ? previous.sets[position] : previous.sets[previous.sets.count - 1]
        switch kind {
        case .reps:
            guard let weight = set.weightKg, let reps = set.reps else { return Formatters.missing }
            return "\(Formatters.weight(weight, unit: unit, includeSymbol: false)) × \(reps)"
        case .duration:
            guard let seconds = set.durationSec else { return Formatters.missing }
            return SetMeasure.formatDuration(seconds)
        }
    }

    // MARK: - Riga obiettivo della scheda

    /// Obiettivo della scheda su una riga: "4 × 8-12 · 90 s", con il carico previsto
    /// quando la scheda lo indica.
    static func targetLine(entry: SessionEntry, item: PlanItem?, unit: WeightUnit) -> String {
        var parts: [String] = []

        let sets = item?.targetSets ?? entry.sets.filter { $0.kind.countsTowardVolume }.count
        let measureText: String
        if let item {
            measureText = item.measure.displayText
        } else if entry.measureKind == .duration {
            measureText = SetMeasure.formatDuration(entry.sets.compactMap(\.durationSec).first ?? 0)
        } else {
            measureText = entry.sets.compactMap(\.reps).first.map(String.init) ?? Formatters.missing
        }
        if sets > 0 { parts.append("\(sets) × \(measureText)") }

        if let weight = item?.targetWeightKg {
            parts.append(Formatters.weight(weight, unit: unit))
        }
        if entry.restSeconds > 0 {
            parts.append("\(entry.restSeconds) s")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Avanzamento

    /// Quanti esercizi sono già chiusi e quanti ce ne sono in tutto.
    static func progress(in session: WorkoutSession) -> (current: Int, total: Int) {
        let total = session.entries.count
        guard total > 0 else { return (0, 0) }
        let index = session.entries.firstIndex { entry in
            entry.sets.contains { !$0.isCompleted }
        }
        return ((index ?? total - 1) + 1, total)
    }

    /// Esercizio da tenere in primo piano: quello scelto a mano se ha ancora serie
    /// da fare, altrimenti il primo incompleto, altrimenti l'ultimo.
    static func foregroundEntryID(in session: WorkoutSession, pinned: UUID?) -> UUID? {
        if let pinned, let entry = session.entries.first(where: { $0.id == pinned }),
           entry.sets.contains(where: { !$0.isCompleted }) {
            return pinned
        }
        if let next = session.entries.first(where: { entry in entry.sets.contains { !$0.isCompleted } }) {
            return next.id
        }
        return pinned ?? session.entries.last?.id
    }

    // MARK: - Superset

    /// Esercizi del gruppo di superset a cui appartiene la riga, in ordine di sessione.
    static func supersetSiblings(of entry: SessionEntry, in session: WorkoutSession) -> [SessionEntry] {
        guard let group = entry.supersetGroup else { return [entry] }
        return session.entries.filter { $0.supersetGroup == group }
    }

    /// Il recupero parte solo dopo l'**ultimo** esercizio del superset.
    static func startsRest(entryID: UUID, in session: WorkoutSession) -> Bool {
        guard let entry = session.entries.first(where: { $0.id == entryID }) else { return false }
        guard entry.supersetGroup != nil else { return true }
        return supersetSiblings(of: entry, in: session).last?.id == entryID
    }

    /// Blocchi in cui si divide l'elenco: un esercizio da solo, oppure un superset.
    struct Block: Identifiable {
        let id: UUID
        let supersetGroup: Int?
        let entries: [SessionEntry]

        var isSuperset: Bool { supersetGroup != nil && entries.count > 1 }
    }

    /// Raggruppa le righe consecutive che condividono lo stesso gruppo di superset.
    static func blocks(in session: WorkoutSession) -> [Block] {
        var result: [Block] = []
        for entry in session.entries {
            if let group = entry.supersetGroup,
               let last = result.last, last.supersetGroup == group {
                result[result.count - 1] = Block(id: last.id, supersetGroup: group, entries: last.entries + [entry])
            } else {
                result.append(Block(id: entry.id, supersetGroup: entry.supersetGroup, entries: [entry]))
            }
        }
        return result
    }

    // MARK: - Ripristino del recupero da una sessione salvata

    /// Recupero ancora in corso dedotto dallo stato salvato.
    ///
    /// Lo store non persiste il timer, ma persiste `completedAt` di ogni serie: se
    /// l'ultima serie spuntata è più recente del suo recupero, il recupero sta
    /// ancora correndo. Così riaprendo l'app a metà allenamento l'anello riparte
    /// dal punto giusto invece di sparire.
    struct PendingRest: Sendable, Hashable {
        let entryID: UUID
        let exerciseID: String
        let totalSeconds: Int
        let endsAt: Date
    }

    static func pendingRest(in session: WorkoutSession, asOf now: Date) -> PendingRest? {
        var latest: (date: Date, entry: SessionEntry)?
        for entry in session.entries {
            for set in entry.sets {
                guard let completedAt = set.completedAt else { continue }
                if latest == nil || completedAt > latest!.date {
                    latest = (completedAt, entry)
                }
            }
        }
        guard let latest, latest.entry.restSeconds > 0 else { return nil }
        guard startsRest(entryID: latest.entry.id, in: session) else { return nil }
        let endsAt = latest.date.addingTimeInterval(TimeInterval(latest.entry.restSeconds))
        guard endsAt > now else { return nil }
        return PendingRest(
            entryID: latest.entry.id,
            exerciseID: latest.entry.exerciseID,
            totalSeconds: latest.entry.restSeconds,
            endsAt: endsAt
        )
    }

    // MARK: - Record

    /// Record battuti in una sessione, per esercizio.
    struct RecordHighlight: Identifiable, Hashable {
        let exerciseID: String
        let kinds: [Stats.RecordKind]

        var id: String { exerciseID }
    }

    /// Record della sessione in corso, dai record "in tempo reale" dello store.
    static func liveHighlights(
        in session: WorkoutSession,
        liveRecords: [UUID: Set<Stats.RecordKind>]
    ) -> [RecordHighlight] {
        var byExercise: [String: Set<Stats.RecordKind>] = [:]
        for entry in session.entries {
            for set in entry.sets {
                guard let kinds = liveRecords[set.id], !kinds.isEmpty else { continue }
                byExercise[entry.exerciseID, default: []].formUnion(kinds)
            }
        }
        return highlights(from: byExercise, order: session.exerciseIDs)
    }

    /// Record di una sessione già archiviata: un record vale per questa sessione se
    /// la data del primato cade dentro la sessione.
    static func archivedHighlights(
        in session: WorkoutSession,
        records: (String) -> Stats.ExerciseRecords?
    ) -> [RecordHighlight] {
        let start = session.startedAt
        let end = session.endedAt ?? session.startedAt
        func isInside(_ date: Date) -> Bool { date >= start && date <= end.addingTimeInterval(1) }

        var byExercise: [String: Set<Stats.RecordKind>] = [:]
        for exerciseID in Set(session.exerciseIDs) {
            guard let record = records(exerciseID) else { continue }
            var kinds: Set<Stats.RecordKind> = []
            if isInside(record.maxWeightDate) { kinds.insert(.maxWeight) }
            if isInside(record.best1RMDate) { kinds.insert(.best1RM) }
            if isInside(record.maxSessionVolumeDate) { kinds.insert(.sessionVolume) }
            if !kinds.isEmpty { byExercise[exerciseID] = kinds }
        }
        return highlights(from: byExercise, order: session.exerciseIDs)
    }

    private static func highlights(
        from byExercise: [String: Set<Stats.RecordKind>],
        order: [String]
    ) -> [RecordHighlight] {
        var seen: Set<String> = []
        return order
            .filter { seen.insert($0).inserted }
            .compactMap { exerciseID in
                guard let kinds = byExercise[exerciseID], !kinds.isEmpty else { return nil }
                let sorted = Stats.RecordKind.allCases.filter { kinds.contains($0) }
                return RecordHighlight(exerciseID: exerciseID, kinds: sorted)
            }
    }
}
