import SwiftUI

/// Tab **Scheda**: scheda attiva in alto (card con gradiente, date, settimana,
/// giorni), archivio sotto, editor per ricopiare la scheda cartacea dell'istruttore,
/// azioni attiva / archivia / duplica / elimina, empty state con "Carica scheda
/// d'esempio" (`AppStore.loadSampleProgram()`), SPEC §5.3.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct ProgramScreen: View {

    public init() {}

    public var body: some View {
        PlaceholderScreen(
            title: "Scheda",
            systemImage: "list.bullet.rectangle",
            message: "Scheda attiva, archivio ed editor dei giorni."
        )
    }
}
