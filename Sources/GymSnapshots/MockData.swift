#if os(macOS)
import Foundation
import GymCore
import GymFeatures

/// Dati finti realistici per gli screenshot.
///
/// Non inventa niente a mano: costruisce tutto attraverso l'API pubblica di
/// ``AppStore`` (scheda, rilevazioni, preferiti) su una **directory temporanea**,
/// con una sorgente di tempo controllata. Quello che si vede negli screenshot è
/// quindi esattamente quello che l'app produrrebbe.
///
/// Niente sessioni di allenamento: la UI non le espone più (SPEC §0) e generarle
/// costava qualche secondo a ogni esecuzione.
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

    /// Primo avvio: nessuna scheda, nessuna rilevazione.
    static func emptyEnvironment() async -> AppEnvironment {
        let clock = MockClock(now)
        let environment = await makeEnvironment(clock: clock)
        clock.date = now
        return environment
    }

    /// Uso reale: scheda d'esempio attiva alla settimana 3 di 6, un ciclo
    /// precedente in archivio, 6 rilevazioni corporee, qualche preferito.
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

    /// Riga di riepilogo stampata all'avvio: serve a verificare a colpo d'occhio
    /// che i dati finti siano quelli attesi.
    @MainActor
    static func summary(of environment: AppEnvironment, label: String) -> String {
        let store = environment.store
        let program = store.activeProgram
        let status = program?.statusText(asOf: now, calendar: store.calendar) ?? "nessuna scheda"
        return "[\(label)] schede: \(store.programs.count) · rilevazioni: \(store.bodyEntries.count) · \(program?.name ?? "") \(status)"
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

    // MARK: - Schede e rilevazioni

    @MainActor
    private static func populate(store: AppStore, clock: MockClock) {
        let calendar = store.calendar

        // Ciclo precedente, ormai in archivio.
        let previousStart = calendar.date(byAdding: .day, value: -37, to: now) ?? now
        clock.date = previousStart
        var previous = SampleProgram.make(startDate: previousStart, now: previousStart)
        previous.name = "Full body, ciclo precedente"
        previous.plannedWeeks = 3
        store.addProgram(previous, makeActive: true)

        // Scheda attiva: iniziata 16 giorni fa, quindi "Settimana 3 di 6".
        // Attivarla archivia automaticamente quella precedente.
        let activeStart = calendar.date(byAdding: .day, value: -16, to: now) ?? now
        clock.date = activeStart
        store.addProgram(SampleProgram.make(startDate: activeStart, now: activeStart), makeActive: true)

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
