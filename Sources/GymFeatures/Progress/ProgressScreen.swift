import SwiftUI

/// Tab **Progressi**: griglia di card (allenamenti, volume, costanza, peso e misure
/// corporee, record), dettaglio per card con range 1M/3M/6M/1A e storico sessioni
/// filtrabile (SPEC §5.5).
///
/// Il dettaglio di una sessione si apre con
/// `NavigationLink(value: AppRoute.session(id:))`.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct ProgressScreen: View {

    public init() {}

    public var body: some View {
        PlaceholderScreen(
            title: "Progressi",
            systemImage: "chart.line.uptrend.xyaxis",
            message: "Allenamenti, volume, corpo, record e storico."
        )
    }
}
