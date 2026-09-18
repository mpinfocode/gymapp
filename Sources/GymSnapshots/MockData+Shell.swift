#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Una pagina **spinta dentro la shell**, non renderizzata da sola.
///
/// Serve proprio a intercettare i difetti che si vedono solo con la tab bar
/// flottante in basso: un bottone primario ancorato al fondo, l'ultima riga di
/// una lista, l'altezza reale dell'iPhone. Le scene "scheda-giorno" e compagnia
/// rendono la pagina isolata e per questo non avevano mai mostrato il bug.
struct ShellScene: View {

    enum Variant {
        /// Giorno della scheda (sei esercizi) dentro il tab Scheda.
        case programDay
        /// Dettaglio di un esercizio dentro il tab Esercizi.
        case exerciseDetail
        /// Dettaglio del peso corporeo dentro il tab Misure.
        case bodyMetric
    }

    let variant: Variant

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                RootView(environment: environment, initialTab: ShellMockData.tab(for: variant))
            }
        }
        .task {
            environment = await ShellMockData.environment(for: variant)
        }
    }
}

/// Ambienti delle scene "dentro la shell": il path del tab è già popolato, così
/// `RootView` parte con la pagina spinta già in cima.
enum ShellMockData {

    static func tab(for variant: ShellScene.Variant) -> AppTab {
        switch variant {
        case .programDay: .program
        case .exerciseDetail: .exercises
        case .bodyMetric: .measures
        }
    }

    @MainActor
    static func environment(for variant: ShellScene.Variant) async -> AppEnvironment {
        switch variant {
        case .programDay:
            let environment = await ProgramMockData.environment(for: .day)
            if let program = environment.store.activeProgram, let day = program.days.first {
                environment.router.programPath = [.programDay(programID: program.id, dayID: day.id)]
            }
            return environment

        case .exerciseDetail:
            let environment = await MockData.fullEnvironment()
            environment.router.exercisesPath = [.exercise(id: "0227")]
            return environment

        case .bodyMetric:
            let environment = await MockData.fullEnvironment()
            environment.router.measuresPath = [.bodyMetric(.weight)]
            return environment
        }
    }
}
#endif
