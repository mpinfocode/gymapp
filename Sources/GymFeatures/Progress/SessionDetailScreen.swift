import Foundation
import SwiftUI

/// Dettaglio di una sessione dello storico: esercizi, serie, volume, note, con
/// modifica ed eliminazione (SPEC §5.5). Tema chiaro, a differenza del riepilogo
/// di fine allenamento.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct SessionDetailScreen: View {

    private let sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    public var body: some View {
        PlaceholderScreen(
            title: "Allenamento",
            systemImage: "clock.arrow.circlepath",
            message: "Serie svolte, volume e note della sessione.",
            parameters: "sessione \(sessionID.uuidString.prefix(8))"
        )
    }
}
