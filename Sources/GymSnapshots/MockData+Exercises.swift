#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Scene della feature Esercizi che hanno bisogno di uno stato proprio (recenti,
/// un esercizio personalizzato, una zona già aperta, il picker).
///
/// Come le altre scene di variante, l'ambiente se lo costruisce da sola in `task`,
/// così `makeScenes` resta una riga per scena e il file condiviso non cresce.
struct ExercisesVariantScene: View {

    enum Variant {
        /// Radice: ricerca e zone colpite con i conteggi.
        case catalog
        /// Elenco di una zona colpita, con i chip per attrezzo.
        case group
        /// Form dell'esercizio personalizzato, con il nome cercato già scritto.
        case customForm
        /// Dettaglio di un esercizio personalizzato (segnaposto, note, menu).
        case customDetail
        /// Picker della scheda: radice a zone.
        case picker
        /// Picker della scheda: elenco di una zona.
        case pickerGroup
        /// Picker della scheda: dettaglio con la GIF e "Aggiungi alla scheda".
        case pickerDetail
    }

    let variant: Variant

    @State private var environment: AppEnvironment?

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
        case .group:
            ExercisesScreen(section: .group(.chest))
        case .customForm:
            CustomExerciseFormSheet(prefilledName: "Face Pull")
        case .customDetail:
            ExerciseDetailScreen(exerciseID: ExercisesMockData.customID(in: environment))
        case .picker:
            ExercisesMockData.picker(section: nil)
        case .pickerGroup:
            ExercisesMockData.picker(section: .group(.chest))
        case .pickerDetail:
            // È il dettaglio che il picker presenta toccando una riga: GIF grande,
            // istruzioni e un solo bottone primario.
            ExerciseDetailScreen(exerciseID: "0025", purpose: .picking(isAdded: false, add: {}))
        }
    }
}

/// Ambiente della feature Esercizi: come ``MockData/fullEnvironment()``, più un
/// esercizio personalizzato e qualche esercizio aperto di recente.
@MainActor
enum ExercisesMockData {

    /// Nome dell'esercizio personalizzato: uno di quelli che al dataset mancano davvero.
    static let customName = "Face Pull"

    /// Esercizi già presenti nel giorno: nel picker restano visibili ma spenti.
    static let excludedIDs: Set<String> = ["0047", "0652"]

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

    @ViewBuilder
    static func picker(section: ExerciseSection?) -> some View {
        if let section {
            ExercisePickerSheet(
                title: "Aggiungi esercizi",
                allowsMultipleSelection: true,
                excludedIDs: excludedIDs,
                section: section,
                onPick: { _ in }
            )
        } else {
            ExercisePickerSheet(
                title: "Aggiungi esercizi",
                allowsMultipleSelection: true,
                excludedIDs: excludedIDs,
                onPick: { _ in }
            )
        }
    }

    static func customID(in environment: AppEnvironment) -> String {
        environment.store.availableCustomExercises.first?.id ?? ""
    }
}
#endif
