#if os(macOS)
import Foundation
import GymCore
import GymFeatures

/// Ambienti finti per le scene della sessione attiva.
///
/// Tutto passa dall'API pubblica di ``AppStore``, come in ``MockData``: qui cambia
/// solo il fatto che la sessione in corso è costruita "al secondo", così si possono
/// fotografare situazioni precise (appena iniziata, a metà con il recupero in corso,
/// superset, esercizio a tempo).
///
/// La libreria esercizi viene riusata da un ambiente già caricato, così non si paga
/// di nuovo la lettura del JSON e la costruzione resta sincrona.
@MainActor
enum SessionMock {

    /// Costruisce una sessione in corso su misura.
    ///
    /// - Parameters:
    ///   - repository: libreria già caricata (da `MockData.fullEnvironment()`).
    ///   - dayIndex: giorno della scheda d'esempio (0 Push, 1 Pull, 2 Legs).
    ///   - completedEntries: quanti esercizi risultano chiusi.
    ///   - partialSets: serie già spuntate nell'esercizio in primo piano.
    ///   - lastSetSecondsAgo: quanti secondi fa è stata spuntata l'ultima serie.
    ///     Se è meno del recupero dell'esercizio, la schermata riprende il recupero
    ///     dallo stato salvato.
    ///   - elapsedMinutes: da quanto è iniziato l'allenamento.
    static func environment(
        repository: ExerciseRepository?,
        dayIndex: Int,
        completedEntries: Int,
        partialSets: Int,
        lastSetSecondsAgo: Int,
        elapsedMinutes: Int = 38
    ) -> AppEnvironment {
        let now = MockData.now
        let clock = MockClock(now)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GymSnapshots-sessione-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(
            store: JSONFileStore(directory: directory),
            exercises: repository,
            saveDelay: .seconds(600),
            now: { clock.date }
        )
        let environment = AppEnvironment(store: store, phase: .ready)

        // Scheda attiva iniziata 16 giorni fa: "Settimana 3 di 6".
        let start = now.addingTimeInterval(-16 * 24 * 3600)
        clock.date = start
        store.addProgram(SampleProgram.make(startDate: start, now: start), makeActive: true)

        guard let program = store.activeProgram, program.days.indices.contains(dayIndex) else {
            clock.date = now
            return environment
        }

        // Tre allenamenti passati: riempiono la colonna PRECEDENTE e fanno nascere
        // gli hint di progressione (tutte le serie chiuse al massimo del range).
        for (offset, dayOffset) in [-12, -9, -5].enumerated() {
            let day = program.days[(dayIndex + offset) % program.days.count]
            logPastSession(
                store: store,
                clock: clock,
                program: program,
                day: day,
                start: now.addingTimeInterval(TimeInterval(dayOffset * 24 * 3600)),
                bump: Double(offset) * 2.5
            )
        }

        // Sessione in corso.
        let startedAt = now.addingTimeInterval(TimeInterval(-elapsedMinutes * 60))
        clock.date = startedAt
        let day = program.days[dayIndex]
        guard store.startSession(programID: program.id, dayID: day.id) != nil,
              let session = store.activeSession else {
            clock.date = now
            return environment
        }

        var targets: [(entry: SessionEntry, set: SetLog)] = []
        for (index, entry) in session.entries.enumerated() {
            if index < completedEntries {
                targets.append(contentsOf: entry.sets.map { (entry, $0) })
            } else if index == completedEntries {
                targets.append(contentsOf: entry.sets.prefix(partialSets).map { (entry, $0) })
            }
        }

        let end = now.addingTimeInterval(TimeInterval(-lastSetSecondsAgo))
        for (position, target) in targets.enumerated() {
            let item = day.items.first { $0.id == target.entry.planItemID }
            let weight = loadedWeight(for: target.entry.exerciseID, in: store, base: baseWeight(target.entry.exerciseID) + 10)
            store.updateSet(id: target.set.id, inEntry: target.entry.id) { log in
                switch target.entry.measureKind {
                case .reps:
                    log.weightKg = weight.map { target.set.kind == .warmup ? ($0 * 0.6).rounded() : $0 }
                    log.reps = max(6, (item?.measure.repsRange?.upperBound ?? 10) - position % 3)
                case .duration:
                    log.durationSec = item?.measure.durationSeconds ?? 45
                }
            }
            clock.date = completionDate(
                position: position,
                count: targets.count,
                startedAt: startedAt,
                end: end
            )
            _ = store.completeSet(id: target.set.id, inEntry: target.entry.id)
        }

        clock.date = now
        return environment
    }

    /// Istante in cui è stata spuntata la serie numero `position`: le serie si
    /// distribuiscono fra l'inizio dell'allenamento e l'ultima spunta.
    private static func completionDate(position: Int, count: Int, startedAt: Date, end: Date) -> Date {
        guard count > 1 else { return end }
        let span = end.timeIntervalSince(startedAt) - 120
        let step = max(30, span / Double(count - 1))
        return startedAt.addingTimeInterval(120 + Double(position) * step)
    }

    /// Un allenamento passato completo, con tutte le serie al massimo del range.
    private static func logPastSession(
        store: AppStore,
        clock: MockClock,
        program: Program,
        day: ProgramDay,
        start: Date,
        bump: Double
    ) {
        clock.date = start
        guard store.startSession(programID: program.id, dayID: day.id) != nil,
              let session = store.activeSession else { return }

        for entry in session.entries {
            let item = day.items.first { $0.id == entry.planItemID }
            let weight = loadedWeight(for: entry.exerciseID, in: store, base: baseWeight(entry.exerciseID) + bump)
            for set in entry.sets {
                store.updateSet(id: set.id, inEntry: entry.id) { log in
                    switch entry.measureKind {
                    case .reps:
                        log.weightKg = weight.map { set.kind == .warmup ? ($0 * 0.6).rounded() : $0 }
                        log.reps = item?.measure.repsRange?.upperBound ?? 10
                    case .duration:
                        log.durationSec = item?.measure.durationSeconds ?? 45
                    }
                }
                clock.date = clock.date.addingTimeInterval(150)
                _ = store.completeSet(id: set.id, inEntry: entry.id)
            }
        }
        clock.date = start.addingTimeInterval(60 * 60)
        _ = store.finishSession()
    }

    /// Carico da registrare, `nil` dove il carico non si regola (corpo libero,
    /// elastici): lì le serie restano senza kg, come in palestra.
    private static func loadedWeight(for exerciseID: String, in store: AppStore, base: Double) -> Double? {
        let equipment = store.exercise(id: exerciseID)?.equipment ?? ""
        guard !WeightStep.progressesByReps(forEquipment: equipment) else { return nil }
        return base
    }

    /// Carico di partenza plausibile e stabile, derivato dall'id del dataset.
    private static func baseWeight(_ exerciseID: String) -> Double {
        let seed = Int(exerciseID) ?? 7
        return 20 + Double(seed % 9) * 5
    }

    /// Prima serie ancora da spuntare: serve alla scena delle opzioni avanzate.
    static func firstPendingSet(in environment: AppEnvironment) -> (entryID: UUID, setID: UUID)? {
        guard let session = environment.store.activeSession else { return nil }
        for entry in session.entries {
            if let set = entry.sets.first(where: { !$0.isCompleted }) {
                return (entry.id, set.id)
            }
        }
        return nil
    }
}
#endif
