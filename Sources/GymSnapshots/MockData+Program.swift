#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Scena di una variante della sezione Scheda: costruisce il proprio ambiente in
/// `task`, così non serve allargare la firma di `makeScenes` (file condiviso).
struct ProgramVariantScene: View {

    enum Variant {
        /// Editor del giorno con sei esercizi, un superset e uno a durata.
        case day
        /// Editor di un esercizio (sheet a mezza altezza).
        case item
        /// Creazione di una scheda nuova.
        case create
        /// Archivio con due cicli passati.
        case archive
        /// Scheda in modalità a giorni fissi.
        case weekdays
    }

    let variant: Variant

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                NavigationStack {
                    content(environment)
                }
                .environment(environment)
            }
        }
        .task {
            environment = await ProgramMockData.environment(for: variant)
        }
    }

    @ViewBuilder
    private func content(_ environment: AppEnvironment) -> some View {
        let program = environment.store.activeProgram
        switch variant {
        case .day:
            if let program, let day = program.days.first {
                ProgramDayEditor(programID: program.id, dayID: day.id)
            }
        case .item:
            if let program, let day = program.days.first, let item = day.items.first {
                PlanItemEditorSheet(programID: program.id, dayID: day.id, itemID: item.id)
            }
        case .create:
            ProgramFormSheet(mode: .create)
        case .archive:
            ProgramArchiveScreen()
        case .weekdays:
            ProgramScreen()
        }
    }
}

/// Schede finte per gli screenshot della sezione Scheda: un giorno "ricco"
/// (superset e esercizio a tempo), una scheda a giorni fissi, un archivio con due
/// cicli passati.
///
/// Come ``MockData``, passa sempre dall'API pubblica di ``AppStore`` su una
/// directory temporanea, con l'orologio fermo a giovedì 17 settembre 2026.
@MainActor
enum ProgramMockData {

    static func environment(for variant: ProgramVariantScene.Variant) async -> AppEnvironment {
        let clock = MockClock(MockData.now)
        let environment = await makeEnvironment(clock: clock)
        let store = environment.store
        let start = day(offset: -16)
        clock.date = start

        switch variant {
        case .day, .item:
            store.addProgram(richProgram(start: start, now: start), makeActive: true)
        case .create:
            break
        case .archive:
            store.addProgram(previousProgram(start: day(offset: -100), now: day(offset: -100)), makeActive: true)
            store.addProgram(SampleProgram.make(startDate: day(offset: -60), now: day(offset: -60)), makeActive: true)
            store.addProgram(richProgram(start: start, now: start), makeActive: true)
        case .weekdays:
            store.addProgram(weekdaysProgram(start: start, now: start), makeActive: true)
        }

        clock.date = MockData.now
        return environment
    }

    // MARK: - Schede

    /// Giorno A con sei esercizi: due in superset e uno a tempo.
    private static func richProgram(start: Date, now: Date) -> Program {
        Program(
            name: "Forza e ipertrofia",
            notes: "",
            startDate: start,
            plannedWeeks: 6,
            mode: .rotation,
            days: [
                ProgramDay(
                    name: "Giorno A",
                    items: [
                        PlanItem(exerciseID: "0025", targetSets: 4, measure: .reps(min: 6, max: 8),
                                 targetWeightKg: 80, warmupSets: 2, restSeconds: 150),
                        PlanItem(exerciseID: "0027", targetSets: 4, measure: .reps(min: 8, max: 10),
                                 targetWeightKg: 60, restSeconds: 120),
                        PlanItem(exerciseID: "0405", targetSets: 3, measure: .reps(min: 8, max: 12),
                                 targetWeightKg: 22, restSeconds: 90),
                        PlanItem(exerciseID: "0334", targetSets: 3, measure: .reps(min: 12, max: 15),
                                 targetWeightKg: 10, restSeconds: 60, supersetGroup: 1),
                        PlanItem(exerciseID: "0201", targetSets: 3, measure: .reps(min: 10, max: 12),
                                 targetWeightKg: 25, restSeconds: 60, supersetGroup: 1),
                        PlanItem(exerciseID: "0464", targetSets: 3, measure: .duration(seconds: 45),
                                 restSeconds: 60),
                    ]
                ),
                ProgramDay(name: "Giorno B", items: [
                    PlanItem(exerciseID: "0043", targetSets: 4, measure: .reps(min: 6, max: 8),
                             targetWeightKg: 90, warmupSets: 2, restSeconds: 180),
                    PlanItem(exerciseID: "0085", targetSets: 3, measure: .reps(min: 8, max: 10),
                             targetWeightKg: 70, restSeconds: 150),
                    PlanItem(exerciseID: "0585", targetSets: 3, measure: .reps(min: 12, max: 15),
                             targetWeightKg: 45, restSeconds: 75),
                    PlanItem(exerciseID: "0605", targetSets: 4, measure: .reps(min: 12, max: 15),
                             targetWeightKg: 60, restSeconds: 60),
                ]),
                ProgramDay(name: "Giorno C", items: [
                    PlanItem(exerciseID: "0652", targetSets: 4, measure: .reps(min: 6, max: 10), restSeconds: 120),
                    PlanItem(exerciseID: "0861", targetSets: 3, measure: .reps(min: 10, max: 12),
                             targetWeightKg: 55, restSeconds: 90),
                    PlanItem(exerciseID: "0031", targetSets: 3, measure: .reps(min: 8, max: 10),
                             targetWeightKg: 30, restSeconds: 60),
                ]),
            ],
            accent: 3,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Scheda a giorni fissi: lunedì, mercoledì e venerdì.
    private static func weekdaysProgram(start: Date, now: Date) -> Program {
        var program = richProgram(start: start, now: now)
        program.name = "Full body"
        program.mode = .weekdays
        program.accent = 5
        let weekdays: [Weekday] = [.monday, .wednesday, .friday]
        for index in program.days.indices where index < weekdays.count {
            program.days[index].weekday = weekdays[index]
        }
        return program
    }

    /// Ciclo vecchio, solo per riempire l'archivio.
    private static func previousProgram(start: Date, now: Date) -> Program {
        var program = SampleProgram.make(startDate: start, now: now)
        program.name = "Adattamento, primo ciclo"
        program.plannedWeeks = 4
        program.accent = 6
        return program
    }

    // MARK: - Costruzione

    private static var repository: ExerciseRepository?

    private static func makeEnvironment(clock: MockClock) async -> AppEnvironment {
        if repository == nil {
            repository = try? await ExerciseRepository.loadFromBundle()
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GymSnapshots-scheda-\(UUID().uuidString)", isDirectory: true)
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

    private static func day(offset: Int) -> Date {
        let calendar = Stats.weekCalendar()
        return calendar.date(byAdding: .day, value: offset, to: MockData.now) ?? MockData.now
    }
}
#endif
