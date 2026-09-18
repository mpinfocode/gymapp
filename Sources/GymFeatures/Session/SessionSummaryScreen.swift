import Foundation
import SwiftUI
import GymUI

/// Riepilogo di fine allenamento: durata, volume, serie, record, nota finale
/// (SPEC §5.4). Tema **scuro immersivo** come la sessione.
///
/// Riceve l'id della sessione già archiviata da `store.finishSession()`, quindi si
/// legge con `app.store.session(id:)`. Lo apre la sessione attiva alla chiusura;
/// è riaperto dallo storico solo in lettura.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct SessionSummaryScreen: View {

    private let sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    public var body: some View {
        PlaceholderScreen(
            title: "Riepilogo",
            systemImage: "checkmark.seal",
            message: "Durata, volume, serie e record della sessione.",
            parameters: "sessione \(sessionID.uuidString.prefix(8))"
        )
        .immersiveDark()
    }
}
