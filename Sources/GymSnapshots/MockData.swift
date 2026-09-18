#if os(macOS)
import Foundation
import GymCore
import GymFeatures

/// Dati finti realistici per gli screenshot.
///
/// Non inventa niente a mano: costruisce tutto attraverso l'API pubblica di
/// ``AppStore`` (scheda, sessioni, serie completate, rilevazioni, preferiti) su una
/// **directory temporanea**, con una sorgente di tempo controllata. Quello che si
/// vede negli screenshot è quindi esattamente quello che l'app produrrebbe.
enum MockData {

    /// "Adesso" fisso di tutti gli screenshot: giovedì 17 settembre 2026, 17:40.
    static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .gmt
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 17
        components.hour = 17
        components.minute = 40
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_789_000_000)
    }()

    // MARK: - Varianti

    /// Primo avvio: nessuna scheda, nessuna sessione, nessuna rilevazione.
    static func emptyEnvironment() async -> AppEnvironment {
        let clock = MockClock(now)
        let environment = await makeEnvironment(clock: clock)
        clock.date = now
        return environment
    }

    /// Uso reale: scheda d'esempio attiva alla settimana 3 di 6, un ciclo
    /// precedente in archivio, 14 sessioni completate nelle ultime 5 settimane,
    /// 6 rilevazioni corporee, qualche preferito.
    static func fullEnvironment() async -> AppEnvironment {
        let clock = MockClock(now)
        let environment = await makeEnvironment(clock: clock)
        let store = await environment.store

        await MainActor.run {
            populate(store: store, clock: clock)
            clock.date = now
        }
        return environment
    }

    /// Come ``fullEnvironment()`` ma con una sessione in corso a metà,
    /// iniziata 38 minuti fa.
    static func activeSessionEnvironment() async -> AppEnvironment {
        let clock = MockClock(now)
        let environment = await makeEnvironment(clock: clock)
        let store = await environment.store

        await MainActor.run {
            populate(store: store, clock: clock)
            startHalfDoneSession(store: store, clock: clock)
            clock.date = now
        }
        return environment
    }

    /// Riga di riepilogo stampata all'avvio: serve a verificare a colpo d'occhio
    /// che i dati finti siano quelli attesi.
    @MainActor
    static func summary(of environment: AppEnvironment, label: String) -> String {
        let store = environment.store
        let program = store.activeProgram
        let status = program?.statusText(asOf: now, calendar: store.calendar) ?? "nessuna scheda"
        let active = store.activeSession.map { "sessione in corso: \($0.completedSets) serie" } ?? "nessuna sessione in corso"
        return "[\(label)] schede: \(store.programs.count) · sessioni: \(store.sessions.count) · rilevazioni: \(store.bodyEntries.count) · \(program?.name ?? "") \(status) · \(active)"
    }

    // MARK: - Costruzione

    /// Repository caricato una volta sola e condiviso da tutti gli ambienti.
    @MainActor private static var repository: ExerciseRepository?

    @MainActor
    private static func loadRepository() async -> ExerciseRepository? {
        if let repository { return repository }
        repository = try? await ExerciseRepository.loadFromBundle()
        return repository
    }

    @MainActor
    private static func makeEnvironment(clock: MockClock) async -> AppEnvironment {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GymSnapshots-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(
            store: JSONFileStore(directory: directory),
            exercises: await loadRepository(),
            saveDelay: .seconds(60),
            now: { clock.date }
        )
        let environment = AppEnvironment(store: store)
        await environment.start()
        return environment
    }

    // MARK: - Storico

    @MainActor
    private static func populate(store: AppStore, clock: MockClock) {
        let calendar = store.calendar

        // Ciclo precedente, ormai in archivio: copre le settimane 5 e 4 fa.
        clock.date = calendar.date(byAdding: .day, value: -37, to: now) ?? now
        var previous = SampleProgram.make(startDate: clock.date, now: clock.date)
        previous.name = "Full body, ciclo precedente"
        previous.plannedWeeks = 3
        store.addProgram(previous, makeActive: true)

        // Scheda attiva: iniziata 16 giorni fa, quindi "Settimana 3 di 6".
        // Attivarla archivia automaticamente quella precedente.
        let activeStart = calendar.date(byAdding: .day, value: -16, to: now) ?? now

        // 14 sessioni: le prime 7 con la scheda precedente, le ultime 7 con quella attiva.
        for (sessionIndex, dayOffset) in historyOffsets.enumerated() {
            if sessionIndex == 7 {
                clock.date = activeStart
                store.addProgram(SampleProgram.make(startDate: activeStart, now: activeStart), makeActive: true)
            }
            guard let program = store.activeProgram, !program.days.isEmpty else { continue }
            let day = program.days[sessionIndex % program.days.count]
            logSession(
                store: store,
                clock: clock,
                programID: program.id,
                dayID: day.id,
                start: trainingStart(dayOffset: dayOffset, calendar: calendar),
                week: sessionIndex / 3
            )
        }

        // Rilevazioni corporee: una ogni due settimane circa, dalle più vecchie.
        for measurement in bodyMeasurements {
            let date = calendar.date(byAdding: .day, value: measurement.dayOffset, to: now) ?? now
            store.addBodyEntry(
                date: date,
                weightKg: measurement.weightKg,
                bodyFatPct: measurement.bodyFatPct,
                leanMassKg: measurement.leanMassKg,
                muscleMassKg: measurement.muscleMassKg,
                waterPct: measurement.waterPct,
                measurementsCm: [
                    .chest: measurement.chest,
                    .waist: measurement.waist,
                    .armRight: measurement.arm,
                    .thighRight: measurement.thigh,
                ]
            )
        }

        for id in ["0025", "0043", "0652"] {
            _ = store.toggleFavorite(id)
        }
    }

    /// Giorni (rispetto ad "adesso") in cui è stato fatto un allenamento:
    /// 14 sessioni su 5 settimane, tipicamente lunedì, mercoledì e venerdì.
    private static let historyOffsets: [Int] = [
        -33, -31, -29,
        -26, -24, -22,
        -19, -17, -15,
        -12, -10, -8,
        -5, -3,
    ]

    /// Inizio dell'allenamento: le 18:00 del giorno indicato.
    private static func trainingStart(dayOffset: Int, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 18, to: midnight) ?? midnight
    }

    /// Registra una sessione completa: serie precompilate, carichi in progressione,
    /// serie spuntate una dopo l'altra, sessione chiusa dopo circa un'ora.
    @MainActor
    private static func logSession(
        store: AppStore,
        clock: MockClock,
        programID: UUID,
        dayID: UUID,
        start: Date,
        week: Int
    ) {
        clock.date = start
        guard store.startSession(programID: programID, dayID: dayID) != nil,
              let session = store.activeSession else { return }

        for entry in session.entries {
            let base = baseWeight(forExerciseID: entry.exerciseID)
            let weight = base + Double(week) * 2.5
            for (position, set) in entry.sets.enumerated() {
                store.updateSet(id: set.id, inEntry: entry.id) { log in
                    switch entry.measureKind {
                    case .reps:
                        log.weightKg = set.kind == .warmup ? (weight * 0.6).rounded() : weight
                        log.reps = max(6, 12 - position)
                    case .duration:
                        log.durationSec = 45 + position * 5
                    }
                    if position == entry.sets.count - 1 { log.rpe = 8.5 }
                }
                clock.date = clock.date.addingTimeInterval(TimeInterval(140 + position * 10))
                _ = store.completeSet(id: set.id, inEntry: entry.id)
            }
        }

        clock.date = start.addingTimeInterval(TimeInterval(58 * 60 + week * 90))
        _ = store.finishSession()
    }

    /// Sessione in corso: primi due esercizi conclusi, il terzo a metà.
    @MainActor
    private static func startHalfDoneSession(store: AppStore, clock: MockClock) {
        guard let program = store.activeProgram, let day = program.days.first else { return }
        clock.date = now.addingTimeInterval(-38 * 60)
        guard store.startSession(programID: program.id, dayID: day.id) != nil,
              let session = store.activeSession else { return }

        let completedEntries = session.entries.prefix(3)
        for (index, entry) in completedEntries.enumerated() {
            let weight = baseWeight(forExerciseID: entry.exerciseID) + 10
            // L'ultimo esercizio resta a metà: si spunta solo la prima serie.
            let setsToComplete = index == 2 ? 1 : entry.sets.count
            for (position, set) in entry.sets.prefix(setsToComplete).enumerated() {
                store.updateSet(id: set.id, inEntry: entry.id) { log in
                    switch entry.measureKind {
                    case .reps:
                        log.weightKg = weight
                        log.reps = max(6, 11 - position)
                    case .duration:
                        log.durationSec = 45
                    }
                }
                clock.date = clock.date.addingTimeInterval(160)
                _ = store.completeSet(id: set.id, inEntry: entry.id)
            }
        }
    }

    /// Carico di partenza plausibile, derivato dall'id del dataset così da restare
    /// identico a ogni esecuzione.
    private static func baseWeight(forExerciseID id: String) -> Double {
        let seed = Int(id) ?? 7
        return 20 + Double(seed % 9) * 5
    }

    // MARK: - Rilevazioni corporee

    private struct BodyMeasurement {
        let dayOffset: Int
        let weightKg: Double
        let bodyFatPct: Double
        let leanMassKg: Double
        let muscleMassKg: Double
        let waterPct: Double
        let chest: Double
        let waist: Double
        let arm: Double
        let thigh: Double
    }

    private static let bodyMeasurements: [BodyMeasurement] = [
        BodyMeasurement(dayOffset: -70, weightKg: 79.4, bodyFatPct: 19.1, leanMassKg: 64.2, muscleMassKg: 36.1, waterPct: 54.2, chest: 100.5, waist: 86.0, arm: 35.0, thigh: 57.0),
        BodyMeasurement(dayOffset: -56, weightKg: 79.0, bodyFatPct: 18.6, leanMassKg: 64.3, muscleMassKg: 36.3, waterPct: 54.6, chest: 100.8, waist: 85.2, arm: 35.2, thigh: 57.2),
        BodyMeasurement(dayOffset: -42, weightKg: 78.5, bodyFatPct: 18.0, leanMassKg: 64.4, muscleMassKg: 36.6, waterPct: 55.0, chest: 101.0, waist: 84.5, arm: 35.4, thigh: 57.4),
        BodyMeasurement(dayOffset: -28, weightKg: 78.1, bodyFatPct: 17.4, leanMassKg: 64.5, muscleMassKg: 36.8, waterPct: 55.3, chest: 101.4, waist: 83.8, arm: 35.7, thigh: 57.6),
        BodyMeasurement(dayOffset: -14, weightKg: 77.6, bodyFatPct: 16.9, leanMassKg: 64.5, muscleMassKg: 37.0, waterPct: 55.6, chest: 101.6, waist: 83.0, arm: 35.9, thigh: 57.9),
        BodyMeasurement(dayOffset: -2, weightKg: 77.2, bodyFatPct: 16.4, leanMassKg: 64.6, muscleMassKg: 37.2, waterPct: 55.9, chest: 101.8, waist: 82.4, arm: 36.1, thigh: 58.1),
    ]
}

/// Orologio mutabile condiviso con ``AppStore``: lo store riceve una closure
/// `@Sendable`, quindi il valore va protetto da un lock anche se di fatto si legge
/// e si scrive solo dal main actor.
final class MockClock: @unchecked Sendable {

    private let lock = NSLock()
    private var value: Date

    init(_ date: Date) {
        value = date
    }

    var date: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}
#endif
