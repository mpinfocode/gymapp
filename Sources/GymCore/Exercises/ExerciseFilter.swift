import Foundation

/// Criteri di ricerca combinabili per la libreria esercizi.
///
/// Tutti i filtri sono in **AND** fra loro; dentro una singola dimensione i valori
/// sono in **OR** (es. `categories = ["chest", "back"]` → petto *oppure* schiena).
/// I valori sono i termini inglesi del dataset.
public struct ExerciseFilter: Sendable, Hashable {
    /// Testo libero: nome, muscoli, attrezzo, categoria, anche nella traduzione italiana.
    public var query: String
    public var categories: Set<String>
    public var equipment: Set<String>
    public var targets: Set<String>
    /// Se `true` restituisce solo gli esercizi presenti fra i preferiti passati alla ricerca.
    public var favoritesOnly: Bool
    /// Zona colpita "da palestra" (SPEC §2, punto 3): è il filtro principale,
    /// accanto a quello per categoria del dataset. Vedi ``MuscleGroup``.
    public var muscleGroups: Set<MuscleGroup>

    public init(
        query: String = "",
        categories: Set<String> = [],
        equipment: Set<String> = [],
        targets: Set<String> = [],
        favoritesOnly: Bool = false,
        muscleGroups: Set<MuscleGroup> = []
    ) {
        self.query = query
        self.categories = categories
        self.equipment = equipment
        self.targets = targets
        self.favoritesOnly = favoritesOnly
        self.muscleGroups = muscleGroups
    }

    /// Filtro vuoto: restituisce l'intera libreria.
    public static let empty = ExerciseFilter()

    /// `true` se nessun criterio è attivo.
    public var isEmpty: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && categories.isEmpty && equipment.isEmpty && targets.isEmpty && !favoritesOnly
            && muscleGroups.isEmpty
    }

    /// Numero di filtri "a chip" attivi (la query non conta), per il badge della UI.
    public var activeFacetCount: Int {
        categories.count + equipment.count + targets.count + muscleGroups.count + (favoritesOnly ? 1 : 0)
    }

    /// Inverte la presenza di un valore in una dimensione (comodo per i chip).
    public mutating func toggleCategory(_ value: String) { Self.toggle(value, in: &categories) }
    public mutating func toggleEquipment(_ value: String) { Self.toggle(value, in: &equipment) }
    public mutating func toggleTarget(_ value: String) { Self.toggle(value, in: &targets) }
    public mutating func toggleMuscleGroup(_ value: MuscleGroup) { Self.toggle(value, in: &muscleGroups) }

    /// Azzera i filtri mantenendo la query di testo.
    public mutating func clearFacets() {
        categories.removeAll()
        equipment.removeAll()
        targets.removeAll()
        muscleGroups.removeAll()
        favoritesOnly = false
    }

    private static func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

/// Un valore del filtro "zona colpita" con il suo conteggio.
public struct MuscleGroupFacet: Sendable, Hashable, Identifiable {
    public let group: MuscleGroup
    public let count: Int

    public var id: MuscleGroup { group }
    /// Etichetta italiana da palestra ("Quadricipiti", "Dorso"…).
    public var label: String { group.displayName }

    public init(group: MuscleGroup, count: Int) {
        self.group = group
        self.count = count
    }
}

/// Un valore di filtro con il suo conteggio, già tradotto in italiano.
public struct FacetCount: Sendable, Hashable, Identifiable {
    /// Termine inglese del dataset (da rimettere nel filtro).
    public let value: String
    /// Etichetta italiana da mostrare.
    public let label: String
    /// Numero di esercizi che ricadrebbero in questo valore.
    public let count: Int

    public var id: String { value }

    public init(value: String, label: String, count: Int) {
        self.value = value
        self.label = label
        self.count = count
    }
}

/// Conteggi per ogni dimensione di filtro, calcolati sul risultato corrente.
public struct ExerciseFacets: Sendable, Hashable {
    public let categories: [FacetCount]
    public let equipment: [FacetCount]
    public let targets: [FacetCount]
    /// Numero di esercizi preferiti che soddisfano gli altri criteri.
    public let favorites: Int
    /// Numero di esercizi che soddisfano l'intero filtro.
    public let total: Int
    /// Conteggi per zona colpita, nell'ordine stabile di ``MuscleGroup``.
    /// È il facet principale della schermata Esercizi (SPEC §2, punto 3).
    public let muscleGroups: [MuscleGroupFacet]

    public init(
        categories: [FacetCount],
        equipment: [FacetCount],
        targets: [FacetCount],
        favorites: Int,
        total: Int,
        muscleGroups: [MuscleGroupFacet] = []
    ) {
        self.categories = categories
        self.equipment = equipment
        self.targets = targets
        self.favorites = favorites
        self.total = total
        self.muscleGroups = muscleGroups
    }
}
