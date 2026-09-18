import SwiftUI
import GymCore
import GymUI

/// Dettaglio di un esercizio aperto da una riga della scheda (Home o editor del
/// giorno): è ``ExerciseDetailScreen`` con in testa il blocco "La tua scheda".
///
/// Esiste come schermata a sé perché è la destinazione della rotta
/// ``AppRoute/planItem(programID:dayID:itemID:)``: risolve da sola l'id
/// dell'esercizio, così la shell può installare la destinazione senza leggere lo
/// store nel proprio `body`. Se la riga nel frattempo è stata cancellata, la pagina
/// lo dice invece di restare bianca.
struct PlanItemDetailScreen: View {

    @Environment(AppEnvironment.self) private var app

    let context: PlanItemContext

    var body: some View {
        if let exerciseID {
            ExerciseDetailScreen(exerciseID: exerciseID, purpose: .plan(context))
        } else {
            EmptyStateView(
                systemImage: "list.bullet.rectangle",
                title: "Esercizio non più in scheda",
                message: "Questa riga è stata rimossa dal giorno."
            )
            .frame(maxHeight: .infinity)
            .pageBackground()
        }
    }

    private var exerciseID: String? {
        app.store.program(id: context.programID)?
            .day(id: context.dayID)?
            .items.first { $0.id == context.itemID }?
            .exerciseID
    }
}
