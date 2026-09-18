import SwiftUI
import GymCore

/// Picker esercizi riusabile: lo aprono l'editor della scheda (aggiunta multipla)
/// e la sessione attiva (aggiungi / sostituisci esercizio).
///
/// Si presenta come sheet e riusa la stessa ricerca di ``ExercisesScreen``.
/// Chi lo apre resta responsabile della chiusura: `onPick` viene chiamato con gli
/// esercizi scelti (uno solo se `allowsMultipleSelection` è `false`); se l'utente
/// annulla, `onPick` non viene chiamato.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct ExercisePickerSheet: View {

    private let title: String
    private let allowsMultipleSelection: Bool
    private let excludedIDs: Set<String>
    private let onPick: ([Exercise]) -> Void

    /// - Parameters:
    ///   - title: titolo della sheet ("Aggiungi esercizi", "Sostituisci").
    ///   - allowsMultipleSelection: selezione multipla con conferma, invece del tocco singolo.
    ///   - excludedIDs: esercizi da non mostrare (già presenti nel giorno o nella sessione).
    ///   - onPick: esercizi scelti, nell'ordine di selezione.
    public init(
        title: String,
        allowsMultipleSelection: Bool,
        excludedIDs: Set<String>,
        onPick: @escaping ([Exercise]) -> Void
    ) {
        self.title = title
        self.allowsMultipleSelection = allowsMultipleSelection
        self.excludedIDs = excludedIDs
        self.onPick = onPick
    }

    public var body: some View {
        PlaceholderScreen(
            title: title,
            systemImage: "magnifyingglass",
            message: "Ricerca e scelta degli esercizi da aggiungere.",
            parameters: "selezione multipla: \(allowsMultipleSelection ? "sì" : "no") · esclusi: \(excludedIDs.count)"
        )
    }
}
