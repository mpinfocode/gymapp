#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Scene della Home: la scheda attiva in consultazione e il dettaglio di un
/// esercizio aperto da un giorno (con il blocco "La tua scheda").
///
/// Riusa la scheda "ricca" di ``ProgramMockData`` (sei esercizi, un superset, uno a
/// tempo, note), così Home e Scheda mostrano gli stessi dati.
struct HomeVariantScene: View {

    enum Variant {
        /// Primo giorno, quello che si vede aprendo l'app.
        case day
        /// Un altro giorno scelto con i chip.
        case otherDay
        /// Dettaglio di un esercizio aperto dal giorno.
        case detail
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
            environment = await ProgramMockData.environment(for: .day)
        }
    }

    @ViewBuilder
    private func content(_ environment: AppEnvironment) -> some View {
        let program = environment.store.activeProgram
        switch variant {
        case .day:
            HomeScreen()
        case .otherDay:
            if let program, program.days.count > 1 {
                HomeScreen(dayID: program.days[1].id)
            }
        case .detail:
            if let program, let day = program.days.first, let item = day.items.first {
                ExerciseDetailScreen(
                    exerciseID: item.exerciseID,
                    purpose: .plan(PlanItemContext(programID: program.id, dayID: day.id, itemID: item.id))
                )
            }
        }
    }
}
#endif
