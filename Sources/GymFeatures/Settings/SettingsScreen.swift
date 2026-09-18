import SwiftUI

/// Impostazioni: nome, unità, recupero di default, haptics, download offline dei
/// media, esporta/importa backup, crediti e licenze (SPEC §5.6).
///
/// Si apre come **sheet** da ``TodayScreen`` (avatar in alto a destra), non è un tab.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct SettingsScreen: View {

    public init() {}

    public var body: some View {
        PlaceholderScreen(
            title: "Impostazioni",
            systemImage: "gearshape",
            message: "Unità, recupero, haptics, media offline e backup."
        )
    }
}
