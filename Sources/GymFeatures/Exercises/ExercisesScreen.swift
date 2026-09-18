import SwiftUI

/// Tab **Esercizi**: ricerca, chip di filtro con conteggi, lista con thumbnail.
/// Il dettaglio si apre con `NavigationLink(value: AppRoute.exercise(id:))`
/// (la destinazione è già installata da `RootView`).
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct ExercisesScreen: View {

    public init() {}

    public var body: some View {
        PlaceholderScreen(
            title: "Esercizi",
            systemImage: "square.grid.2x2",
            message: "Ricerca, filtri e libreria completa."
        )
    }
}
