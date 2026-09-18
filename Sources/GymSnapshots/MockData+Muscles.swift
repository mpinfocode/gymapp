#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Scene della ripartizione dei muscoli colpiti: riepilogo esteso, versione
/// compatta della Home, scheda squilibrata (con le zone non allenate) e stato vuoto.
///
/// Come le altre scene, costruisce il proprio ambiente in `task` su una directory
/// temporanea, con l'orologio fermo a giovedì 17 settembre 2026.
struct MusclesScene: View {

    enum Variant {
        /// Riepilogo esteso dell'intera scheda.
        case summary
        /// Riepilogo del solo primo giorno.
        case day
        /// Scheda che allena solo la parte alta: compare la riga delle zone mancanti.
        case unbalanced
        /// Versione compatta com'è in Home, fra intestazione e chip dei giorni.
        case compact
        /// Scheda senza esercizi.
        case empty
    }

    let variant: Variant

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        content(environment)
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.vertical, Theme.Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .environment(environment)
            }
        }
        .task {
            environment = await MusclesMockData.environment(for: variant)
        }
    }

    @ViewBuilder
    private func content(_ environment: AppEnvironment) -> some View {
        if let program = environment.store.activeProgram {
            switch variant {
            case .summary, .unbalanced, .empty:
                MuscleDistributionSection(programID: program.id)
            case .day:
                if let day = program.days.first {
                    MuscleDistributionSection(
                        programID: program.id,
                        dayID: day.id,
                        title: "Muscoli del giorno"
                    )
                }
            case .compact:
                if let day = program.days.first {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        Text(program.name)
                            .font(.greeting)
                            .foregroundStyle(Theme.textPrimary)
                        Text(program.statusText(asOf: environment.now, calendar: environment.calendar))
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                        MuscleDistributionCompact(programID: program.id, dayID: day.id)
                    }
                    MuscleDistributionSection(
                        programID: program.id,
                        dayID: day.id,
                        title: "Foglio di dettaglio, ambito giorno"
                    )
                }
            }
        }
    }
}

/// Schede finte per le scene dei muscoli colpiti.
@MainActor
enum MusclesMockData {

    static func environment(for variant: MusclesScene.Variant) async -> AppEnvironment {
        let clock = MockClock(MockData.now)
        let environment = await makeEnvironment(clock: clock)
        let start = day(offset: -16)
        clock.date = start

        switch variant {
        case .summary, .day, .compact:
            environment.store.addProgram(SampleProgram.make(startDate: start, now: start), makeActive: true)
        case .unbalanced:
            environment.store.addProgram(upperOnly(start: start, now: start), makeActive: true)
        case .empty:
            environment.store.addProgram(withoutExercises(start: start, now: start), makeActive: true)
        }

        clock.date = MockData.now
        return environment
    }

    /// Scheda che trascura completamente le gambe: è il caso in cui la ripartizione
    /// serve davvero ("in cosa si concentra la mia scheda?").
    private static func upperOnly(start: Date, now: Date) -> Program {
        Program(
            name: "Solo parte alta",
            startDate: start,
            plannedWeeks: 4,
            days: [
                ProgramDay(name: "Giorno A", items: [
                    PlanItem(exerciseID: "0025", targetSets: 5, measure: .reps(min: 5, max: 8), warmupSets: 2),
                    PlanItem(exerciseID: "0047", targetSets: 4, measure: .reps(min: 8, max: 10)),
                    PlanItem(exerciseID: "0334", targetSets: 4, measure: .reps(min: 12, max: 15)),
                    PlanItem(exerciseID: "0201", targetSets: 3, measure: .reps(min: 10, max: 12)),
                ]),
                ProgramDay(name: "Giorno B", items: [
                    PlanItem(exerciseID: "0652", targetSets: 5, measure: .reps(min: 6, max: 10)),
                    PlanItem(exerciseID: "0027", targetSets: 4, measure: .reps(min: 8, max: 10)),
                    PlanItem(exerciseID: "0031", targetSets: 3, measure: .reps(min: 8, max: 10)),
                    PlanItem(exerciseID: "0313", targetSets: 3, measure: .reps(min: 10, max: 12)),
                ]),
            ],
            accent: 2,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func withoutExercises(start: Date, now: Date) -> Program {
        Program(
            name: "Nuova scheda",
            startDate: start,
            plannedWeeks: 6,
            days: [ProgramDay(name: "Giorno A"), ProgramDay(name: "Giorno B")],
            accent: 1,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Costruzione

    private static var repository: ExerciseRepository?

    private static func makeEnvironment(clock: MockClock) async -> AppEnvironment {
        if repository == nil {
            repository = try? await ExerciseRepository.loadFromBundle()
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GymSnapshots-muscoli-\(UUID().uuidString)", isDirectory: true)
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
