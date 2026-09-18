import Foundation
import GymCore

/// Stato della ricerca esercizi: è lo stesso nel catalogo e nel picker, così i due
/// si comportano in modo identico senza duplicare nulla.
///
/// Tiene solo le dimensioni che l'utente vede davvero (testo, zona colpita, attrezzo,
/// preferiti): categoria e target grezzi del dataset restano in GymCore.
public struct ExerciseSearchModel: Sendable, Hashable {

    /// Testo digitato (accetta il gergo italiano: la traduzione la fa GymCore).
    public var query: String
    /// Zone colpite selezionate con i chip.
    public var muscleGroups: Set<MuscleGroup>
    /// Attrezzi selezionati nello sheet dei filtri.
    public var equipment: Set<String>
    /// Solo preferiti.
    public var favoritesOnly: Bool

    public init(
        query: String = "",
        muscleGroups: Set<MuscleGroup> = [],
        equipment: Set<String> = [],
        favoritesOnly: Bool = false
    ) {
        self.query = query
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.favoritesOnly = favoritesOnly
    }

    /// Filtro da passare a ``AppStore/searchExercises(_:limit:)``.
    public var filter: ExerciseFilter {
        ExerciseFilter(
            query: query,
            equipment: equipment,
            favoritesOnly: favoritesOnly,
            muscleGroups: muscleGroups
        )
    }

    /// Testo cercato senza spazi ai bordi.
    public var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `true` se l'utente sta cercando qualcosa.
    public var hasQuery: Bool { !trimmedQuery.isEmpty }

    /// `true` se almeno un filtro è attivo.
    public var hasAnyFilter: Bool {
        !equipment.isEmpty || favoritesOnly || !muscleGroups.isEmpty
    }

    public mutating func toggle(_ group: MuscleGroup) {
        if muscleGroups.contains(group) { muscleGroups.remove(group) } else { muscleGroups.insert(group) }
    }

    public mutating func toggleEquipment(_ value: String) {
        if equipment.contains(value) { equipment.remove(value) } else { equipment.insert(value) }
    }

    /// Azzera i filtri mantenendo il testo cercato.
    public mutating func clearFilters() {
        muscleGroups.removeAll()
        equipment.removeAll()
        favoritesOnly = false
    }
}

/// Funzioni di presentazione della libreria, pure e verificabili a occhio nudo.
enum ExerciseBrowseFormat {

    /// Conteggio discreto sotto i chip: "1.324 esercizi", "1 esercizio".
    static func resultsText(_ count: Int) -> String {
        count == 1 ? "1 esercizio" : "\(Formatters.integer(count)) esercizi"
    }

    /// Esercizi aperti di recente, nell'ordine in cui sono stati visti.
    ///
    /// - Parameters:
    ///   - ids: `settings.recentExerciseIDs`, già dal più recente.
    ///   - limit: quanti mostrarne (la sezione deve restare corta).
    ///   - resolve: risolutore per id (salta quelli spariti o eliminati).
    static func recents(
        ids: [String],
        limit: Int = 5,
        resolve: (String) -> Exercise?
    ) -> [Exercise] {
        var result: [Exercise] = []
        for id in ids {
            guard result.count < limit else { break }
            guard let exercise = resolve(id), exercise.isSelectable else { continue }
            result.append(exercise)
        }
        return result
    }
}

/// Valori di partenza sensati quando si aggiunge un esercizio a un giorno della scheda.
///
/// Non è logica di dominio: è solo il "primo suggerimento" del form, che l'utente
/// corregge dall'editor della scheda.
enum PlanDefaults {

    /// Serie e misura proposte per l'esercizio.
    static func suggestion(for exercise: Exercise) -> (sets: Int, measure: SetMeasure) {
        switch exercise.muscleGroupKind {
        case .cardio:
            return (1, .duration(seconds: 600))
        case .abs:
            return isBigCompound(exercise) ? (3, .reps(min: 10, max: 15)) : (3, .reps(min: 12, max: 20))
        case .chest, .back, .shoulders, .quads, .hamstrings, .glutes:
            return isBigCompound(exercise) ? (4, .reps(min: 6, max: 10)) : (3, .reps(min: 8, max: 12))
        case .biceps, .triceps, .forearms, .calves, .other:
            return (3, .reps(min: 10, max: 15))
        }
    }

    /// Riga descrittiva del suggerimento: "4 serie · 6-10 ripetizioni".
    static func summary(for exercise: Exercise) -> String {
        let suggestion = suggestion(for: exercise)
        let sets = suggestion.sets == 1 ? "1 serie" : "\(suggestion.sets) serie"
        switch suggestion.measure {
        case .reps(let min, let max):
            let range = min == max ? "\(min)" : "\(min)-\(max)"
            return "\(sets) · \(range) ripetizioni"
        case .duration(let seconds):
            return "\(sets) · \(Formatters.shortDuration(seconds: seconds))"
        }
    }

    /// Bilanciere, multipower e trap bar: i fondamentali si programmano più pesanti
    /// e con una serie in più.
    private static func isBigCompound(_ exercise: Exercise) -> Bool {
        ["barbell", "olympic barbell", "smith machine", "trap bar"].contains(exercise.equipment)
    }
}
