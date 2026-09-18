import Foundation
import GymCore

/// Una "porta" della libreria: la radice di Esercizi ne mostra l'elenco e toccandone
/// una si apre la lista corrispondente.
///
/// Sono tre cose diverse con lo stesso comportamento (titolo, conteggio, filtro),
/// quindi un solo tipo: le zone colpite più le due scorciatoie che l'utente si è
/// costruito da sé (preferiti, esercizi personalizzati).
public enum ExerciseSection: Hashable, Sendable, Identifiable {
    /// Una zona colpita ("Petto", "Dorso"…).
    case group(MuscleGroup)
    /// Gli esercizi messi tra i preferiti.
    case favorites
    /// Gli esercizi creati dall'utente.
    case custom

    public var id: String {
        switch self {
        case .group(let group): "group-\(group.rawValue)"
        case .favorites: "favorites"
        case .custom: "custom"
        }
    }

    /// Titolo della pagina e della riga.
    public var title: String {
        switch self {
        case .group(let group): group.displayName
        case .favorites: "Preferiti"
        case .custom: "I miei esercizi"
        }
    }

    /// Icona della riga; le zone non ne hanno (sarebbe decorazione).
    var systemImage: String? {
        switch self {
        case .group: nil
        case .favorites: "heart"
        case .custom: "square.and.pencil"
        }
    }

    /// Filtro di base della sezione, senza gli attrezzi scelti nella pagina.
    var filter: ExerciseFilter {
        switch self {
        case .group(let group): ExerciseFilter(muscleGroups: [group])
        case .favorites: ExerciseFilter(favoritesOnly: true)
        case .custom: ExerciseFilter()
        }
    }

    /// Gli esercizi personalizzati non sono un filtro del repository: si prendono
    /// dallo store e basta.
    var isCustomOnly: Bool {
        if case .custom = self { return true }
        return false
    }
}

/// Ordinamento delle liste di zona: prima i nomi "canonici", poi le varianti
/// ridondanti del dataset ("v. 2", "(back pov)"…), a parità di tutto in ordine
/// alfabetico sul titolo mostrato (SPEC §2, punto 4).
enum ExerciseListOrder {

    static func sorted(_ exercises: [Exercise]) -> [Exercise] {
        exercises.sorted { first, second in
            if first.isRedundantVariant != second.isRedundantVariant {
                return !first.isRedundantVariant
            }
            let left = first.shortDisplayName
            let right = second.shortDisplayName
            if left != right { return left.localizedCaseInsensitiveCompare(right) == .orderedAscending }
            return first.id < second.id
        }
    }
}
