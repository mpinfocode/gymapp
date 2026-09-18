import SwiftUI

/// Tab **Oggi**: saluto, hero dell'allenamento di oggi, striscia settimana,
/// riepilogo settimanale, ultime sessioni. Apre ``SettingsScreen`` come sheet
/// dall'avatar in alto a destra (SPEC §5.1).
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct TodayScreen: View {

    public init() {}

    public var body: some View {
        PlaceholderScreen(
            title: "Oggi",
            systemImage: "house",
            message: "Allenamento di oggi, settimana corrente e ultime sessioni."
        )
    }
}
