#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Scena di una variante di Oggi: costruisce il proprio ambiente in `task`, così
/// non serve allargare la firma di `makeScenes` (file condiviso con le altre feature).
struct TodayVariantScene: View {

    enum Variant {
        case rest
        case completed
        case expiring
    }

    let variant: Variant

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                NavigationStack {
                    TodayScreen()
                }
                .environment(environment)
            }
        }
        .task {
            switch variant {
            case .rest: environment = await TodayMockData.restEnvironment()
            case .completed: environment = await TodayMockData.completedEnvironment()
            case .expiring: environment = await TodayMockData.expiringEnvironment()
            }
        }
    }
}

/// Ambienti finti per le varianti della schermata Oggi: giorno di riposo,
/// allenamento già fatto oggi, scheda in scadenza.
///
/// Come ``MockData``, non inventa niente a mano: costruisce tutto attraverso
/// l'API pubblica di ``AppStore`` su una directory temporanea, con l'orologio
/// fermo allo stesso istante degli altri screenshot (giovedì 17 settembre 2026).
@MainActor
enum TodayMockData {

    /// Modalità a giorni fissi, nessun giorno assegnato al giovedì: oggi si riposa.
    static func restEnvironment() async -> AppEnvironment {
        let clock = MockClock(MockData.now)
        let environment = await makeEnvironment(clock: clock)
        let start = day(offset: -16)

        var program = SampleProgram.make(startDate: start, now: start)
        program.mode = .weekdays
        let weekdays: [Weekday] = [.monday, .tuesday, .saturday]
        for index in program.days.indices where index < weekdays.count {
            program.days[index].weekday = weekdays[index]
        }

        populate(store: environment.store, clock: clock, program: program, offsets: [-16, -15, -11, -9, -8, -3, -2])
        return environment
    }

    /// L'allenamento di oggi è già stato fatto stamattina.
    static func completedEnvironment() async -> AppEnvironment {
        let clock = MockClock(MockData.now)
        let environment = await makeEnvironment(clock: clock)
        let start = day(offset: -16)
        let program = SampleProgram.make(startDate: start, now: start)

        populate(
            store: environment.store,
            clock: clock,
            program: program,
            offsets: [-16, -14, -12, -9, -7, -5, -2, 0],
            startHour: 7
        )
        return environment
    }

    /// Scheda di 6 settimane iniziata 37 giorni fa: scade fra 5 giorni.
    static func expiringEnvironment() async -> AppEnvironment {
        let clock = MockClock(MockData.now)
        let environment = await makeEnvironment(clock: clock)
        let start = day(offset: -37)
        let program = SampleProgram.make(startDate: start, now: start)

        populate(store: environment.store, clock: clock, program: program, offsets: [-16, -14, -12, -9, -7, -5, -3, -1])
        return environment
    }

    // MARK: - Costruzione

    /// Libreria caricata una volta sola e condivisa dai tre ambienti.
    private static var repository: ExerciseRepository?

    private static func makeEnvironment(clock: MockClock) async -> AppEnvironment {
        if repository == nil {
            repository = try? await ExerciseRepository.loadFromBundle()
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GymSnapshots-oggi-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(
            store: JSONFileStore(directory: directory),
            exercises: repository,
            saveDelay: .seconds(60),
            now: { clock.date }
        )
        let environment = AppEnvironment(store: store)
        await environment.start()
        return environment
    }

    /// Attiva la scheda e registra una sessione completa per ogni scarto indicato.
    private static func populate(
        store: AppStore,
        clock: MockClock,
        program: Program,
        offsets: [Int],
        startHour: Int = 18
    ) {
        clock.date = program.startDate
        store.addProgram(program, makeActive: true)

        for (index, offset) in offsets.enumerated() {
            guard let active = store.activeProgram, !active.days.isEmpty else { continue }
            let programDay = active.days[index % active.days.count]
            log(
                store: store,
                clock: clock,
                programID: active.id,
                dayID: programDay.id,
                start: moment(offset: offset, hour: startHour),
                week: index / 3
            )
        }
        clock.date = MockData.now
    }

    private static func log(
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
            let weight = baseWeight(forExerciseID: entry.exerciseID) + Double(week) * 2.5
            for (position, set) in entry.sets.enumerated() {
                store.updateSet(id: set.id, inEntry: entry.id) { log in
                    switch entry.measureKind {
                    case .reps:
                        log.weightKg = set.kind == .warmup ? (weight * 0.6).rounded() : weight
                        log.reps = max(6, 12 - position)
                    case .duration:
                        log.durationSec = 45 + position * 5
                    }
                }
                clock.date = clock.date.addingTimeInterval(TimeInterval(140 + position * 10))
                _ = store.completeSet(id: set.id, inEntry: entry.id)
            }
        }

        clock.date = start.addingTimeInterval(TimeInterval(62 * 60))
        _ = store.finishSession()
    }

    // MARK: - Date e carichi

    private static func day(offset: Int) -> Date {
        let calendar = Stats.weekCalendar()
        return calendar.date(byAdding: .day, value: offset, to: MockData.now) ?? MockData.now
    }

    private static func moment(offset: Int, hour: Int) -> Date {
        let calendar = Stats.weekCalendar()
        let midnight = calendar.startOfDay(for: day(offset: offset))
        return calendar.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
    }

    private static func baseWeight(forExerciseID id: String) -> Double {
        let seed = Int(id) ?? 7
        return 20 + Double(seed % 9) * 5
    }
}
#endif
