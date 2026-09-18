#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Scene della feature Esercizi che hanno bisogno di uno stato proprio (recenti,
/// un esercizio personalizzato, uno sheet aperto).
///
/// Come ``TodayVariantScene``, l'ambiente se lo costruisce da sola in `task`, così
/// `makeScenes` resta una riga per scena e il file condiviso non cresce.
struct ExercisesVariantScene: View {

    enum Variant {
        /// Catalogo con qualche esercizio già visto di recente.
        case catalog
        /// Sheet dei filtri con attrezzo e preferiti già attivi.
        case filters
        /// Form dell'esercizio personalizzato, con il nome cercato già scritto.
        case customForm
        /// Dettaglio di un esercizio personalizzato (segnaposto, note, menu).
        case customDetail
    }

    let variant: Variant

    @State private var environment: AppEnvironment?
    @State private var model = ExerciseSearchModel(
        muscleGroups: [.chest],
        equipment: ["barbell"],
        favoritesOnly: false
    )

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                NavigationStack {
                    content(in: environment)
                }
                .environment(environment)
            }
        }
        .task {
            environment = await ExercisesMockData.environment()
        }
    }

    @ViewBuilder
    private func content(in environment: AppEnvironment) -> some View {
        switch variant {
        case .catalog:
            ExercisesScreen()
        case .filters:
            ExerciseFiltersSheet(model: $model)
        case .customForm:
            CustomExerciseFormSheet(prefilledName: "Face Pull")
        case .customDetail:
            ExerciseDetailScreen(exerciseID: ExercisesMockData.customID(in: environment))
        }
    }
}

/// Ambiente della feature Esercizi: come ``MockData/fullEnvironment()``, più un
/// esercizio personalizzato e qualche esercizio aperto di recente.
@MainActor
enum ExercisesMockData {

    /// Nome dell'esercizio personalizzato: uno di quelli che al dataset mancano davvero.
    static let customName = "Face Pull"

    static func environment() async -> AppEnvironment {
        let environment = await MockData.fullEnvironment()
        let store = environment.store

        store.createCustomExercise(
            name: customName,
            category: "shoulders",
            equipment: "cable",
            target: "delts",
            notes: "Cavi alti, gomiti larghi, fermo un secondo alla massima contrazione."
        )

        // Gli ultimi esercizi guardati: l'ordine è dal più recente.
        for id in ["0043", "0652", "0025"] {
            store.markRecent(id)
        }
        return environment
    }

    static func customID(in environment: AppEnvironment) -> String {
        environment.store.availableCustomExercises.first?.id ?? ""
    }
}
#endif
