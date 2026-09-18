import SwiftUI

/// Dettaglio di un esercizio: GIF su tile bianca, muscoli, attrezzo, istruzioni a
/// passi, preferito, storico personale, "Aggiungi alla scheda", attribuzione
/// "© Gym visual · https://gymvisual.com/" (SPEC §5.2).
///
/// Riceve solo l'id: l'esercizio si risolve con `app.exercise(id:)`, così la
/// schermata funziona anche se arriva da un backup con un id non più esistente.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct ExerciseDetailScreen: View {

    private let exerciseID: String

    public init(exerciseID: String) {
        self.exerciseID = exerciseID
    }

    public var body: some View {
        PlaceholderScreen(
            title: "Esercizio",
            systemImage: "figure.strengthtraining.traditional",
            message: "GIF, muscoli, istruzioni, storico e record.",
            parameters: "id \(exerciseID)"
        )
    }
}
