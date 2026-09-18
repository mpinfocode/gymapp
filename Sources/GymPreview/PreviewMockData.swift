#if os(macOS)
import Foundation
import GymCore
import GymFeatures

/// Dati finti per l'anteprima interattiva.
///
/// È l'adattamento di `Sources/GymSnapshots/MockData.swift`: la logica è la stessa
/// (si costruisce tutto attraverso l'API pubblica di ``AppStore``, mai a mano), ma
/// non si può importare un target eseguibile e quindi il minimo necessario è
/// ricopiato qui.
///
/// Due differenze volute rispetto agli screenshot:
/// - **"adesso" è l'ora vera** (`Date()`): questo è uno strumento, non una feature,
///   e l'utente si aspetta che "oggi" sia davvero oggi. L'orologio resta fisso solo
///   mentre si creano le schede, così le date relative restano coerenti, poi passa
///   in tempo reale.
/// - i dati vivono in una **cartella temporanea** nuova a ogni caricamento: niente
///   di quello che si tocca qui finisce nei dati veri dell'app.
enum PreviewMockData {

    /// Ambiente pronto per lo scenario richiesto.
    @MainActor
    static func environment(for scenario: PreviewScenario) async -> AppEnvironment {
        switch scenario {
        case .sample: await fullEnvironment()
        case .empty: await emptyEnvironment()
        }
    }

    // MARK: - Varianti

    /// Primo avvio: nessuna scheda, nessuna rilevazione.
    @MainActor
    static func emptyEnvironment() async -> AppEnvironment {
        let clock = PreviewClock(Date())
        let environment = await makeEnvironment(clock: clock)
        clock.goLive()
        return environment
    }

    /// Uso reale: scheda d'esempio attiva alla settimana 3 di 6, un ciclo
    /// precedente in archivio, 6 rilevazioni corporee, qualche preferito.
    @MainActor
    static func fullEnvironment() async -> AppEnvironment {
        let clock = PreviewClock(Date())
        let environment = await makeEnvironment(clock: clock)
        populate(store: environment.store, clock: clock)
        clock.goLive()
        return environment
    }

    // MARK: - Costruzione

    /// Repository caricato una volta sola e condiviso da tutti gli ambienti: il
    /// dataset è grande, ricaricarlo a ogni cambio di scenario bloccherebbe la UI.
    @MainActor private static var repository: ExerciseRepository?

    @MainActor
    private static func loadRepository() async -> ExerciseRepository? {
        if let repository { return repository }
        repository = try? await ExerciseRepository.loadFromBundle()
        return repository
    }

    @MainActor
    private static func makeEnvironment(clock: PreviewClock) async -> AppEnvironment {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GymPreview-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(
            store: JSONFileStore(directory: directory),
            exercises: await loadRepository(),
            saveDelay: .seconds(2),
            now: { clock.date }
        )
        let environment = AppEnvironment(store: store)
        await environment.start()
        return environment
    }

    // MARK: - Schede e rilevazioni

    @MainActor
    private static func populate(store: AppStore, clock: PreviewClock) {
        let now = clock.date
        let calendar = store.calendar

        // Ciclo precedente, ormai in archivio.
        clock.date = calendar.date(byAdding: .day, value: -37, to: now) ?? now
        var previous = SampleProgram.make(startDate: clock.date, now: clock.date)
        previous.name = "Full body, ciclo precedente"
        previous.plannedWeeks = 3
        store.addProgram(previous, makeActive: true)

        // Scheda attiva: iniziata 16 giorni fa, quindi "Settimana 3 di 6".
        let activeStart = calendar.date(byAdding: .day, value: -16, to: now) ?? now

        clock.date = activeStart
        store.addProgram(SampleProgram.make(startDate: activeStart, now: activeStart), makeActive: true)

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

        clock.date = now
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

/// Orologio dello store: fisso mentre si scrive lo storico, poi in tempo reale.
///
/// ``AppStore`` riceve una closure `@Sendable`, quindi il valore va protetto da un
/// lock anche se di fatto si legge e si scrive solo dal main actor.
final class PreviewClock: @unchecked Sendable {

    private let lock = NSLock()
    private var fixed: Date?

    init(_ date: Date) {
        fixed = date
    }

    /// Data corrente: quella imposta, oppure l'ora vera quando l'orologio è "vivo".
    var date: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return fixed ?? Date()
        }
        set {
            lock.lock()
            fixed = newValue
            lock.unlock()
        }
    }

    /// Passa all'ora di sistema: da qui in poi l'app vede scorrere il tempo.
    func goLive() {
        lock.lock()
        fixed = nil
        lock.unlock()
    }
}
#endif
