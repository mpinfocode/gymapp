import Foundation

public enum ExerciseRepositoryError: Error, Sendable, CustomStringConvertible {
    case resourceMissing(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name): "Risorsa mancante nel bundle: \(name)"
        }
    }
}

/// Libreria degli esercizi: immutabile, `Sendable`, con indici pre-calcolati.
///
/// Si costruisce una volta sola (`loadFromBundle()`, fuori dal main thread) e poi
/// tutte le interrogazioni sono sincrone e veloci, così la UI può filtrare mentre
/// l'utente digita senza salti di frame.
public final class ExerciseRepository: Sendable {

    /// Voce di indice: tutte le stringhe sono già normalizzate (vedi ``SearchText``).
    private struct IndexEntry: Sendable {
        let nameKey: String
        let nameTokens: [String]
        /// Nome + muscoli + attrezzo + categoria, in inglese **e** in italiano.
        let haystack: String
        let category: String
        let equipment: String
        let target: String
    }

    /// Tutti gli esercizi, ordinati alfabeticamente per nome normalizzato.
    public let all: [Exercise]
    private let byID: [String: Exercise]
    /// Parallelo ad ``all``: stessa posizione, stesso esercizio.
    private let index: [IndexEntry]

    public init(exercises: [Exercise]) {
        let sorted = exercises.sorted { SearchText.normalize($0.name) < SearchText.normalize($1.name) }
        all = sorted
        byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        index = sorted.map(ExerciseRepository.makeIndexEntry)
    }

    private static func makeIndexEntry(for exercise: Exercise) -> IndexEntry {
        let nameKey = SearchText.normalize(exercise.name)
        var terms: [String] = [
            nameKey,
            SearchText.normalize(exercise.category),
            SearchText.normalize(exercise.equipment),
            SearchText.normalize(exercise.target),
            SearchText.normalize(exercise.muscleGroup),
            SearchText.normalize(Localization.category(exercise.category)),
            SearchText.normalize(Localization.equipment(exercise.equipment)),
            SearchText.normalize(Localization.muscle(exercise.target)),
            SearchText.normalize(Localization.muscle(exercise.muscleGroup)),
        ]
        for muscle in exercise.secondaryMuscles {
            terms.append(SearchText.normalize(muscle))
            terms.append(SearchText.normalize(Localization.muscle(muscle)))
        }
        // Deduplica mantenendo l'ordine, poi unisce con " | " per evitare match a cavallo di due termini.
        var seen: Set<String> = []
        let unique = terms.filter { !$0.isEmpty && seen.insert($0).inserted }
        return IndexEntry(
            nameKey: nameKey,
            nameTokens: nameKey.split(separator: " ").map(String.init),
            haystack: unique.joined(separator: " | "),
            category: exercise.category,
            equipment: exercise.equipment,
            target: exercise.target
        )
    }

    // MARK: - Caricamento

    /// Carica e indicizza `exercises.json` da `Bundle.module` fuori dal main thread.
    public static func loadFromBundle() async throws -> ExerciseRepository {
        try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
                throw ExerciseRepositoryError.resourceMissing("exercises.json")
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let exercises = try JSONDecoder().decode([Exercise].self, from: data)
            return ExerciseRepository(exercises: exercises)
        }.value
    }

    // MARK: - Accesso diretto

    public var count: Int { all.count }
    public var isEmpty: Bool { all.isEmpty }

    /// Esercizio per id del dataset, `nil` se assente (es. backup che cita un id rimosso).
    public func exercise(id: String) -> Exercise? { byID[id] }

    /// Esercizi per una lista di id, nell'ordine richiesto, saltando quelli sconosciuti.
    public func exercises(ids: some Sequence<String>) -> [Exercise] {
        ids.compactMap { byID[$0] }
    }

    /// Dizionario id → esercizio, utile per le aggregazioni di ``Stats``.
    public func exercisesByID() -> [String: Exercise] { byID }

    /// Valori distinti di una dimensione, ordinati per etichetta italiana.
    public var allCategories: [String] { distinct(\.category) }
    public var allEquipment: [String] { distinct(\.equipment) }
    public var allTargets: [String] { distinct(\.target) }

    private func distinct(_ keyPath: KeyPath<Exercise, String>) -> [String] {
        var seen: Set<String> = []
        var values: [String] = []
        for exercise in all {
            let value = exercise[keyPath: keyPath]
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            values.append(value)
        }
        return values.sorted()
    }

    // MARK: - Ricerca

    /// Esercizi che soddisfano il filtro, ordinati per rilevanza e poi per nome.
    ///
    /// - Parameters:
    ///   - filter: criteri combinati.
    ///   - favorites: id preferiti, necessari se `filter.favoritesOnly` è attivo.
    ///   - limit: numero massimo di risultati (`nil` = tutti).
    public func search(_ filter: ExerciseFilter, favorites: Set<String> = [], limit: Int? = nil) -> [Exercise] {
        let tokens = SearchText.tokens(filter.query)
        var matches: [(score: Int, position: Int)] = []
        matches.reserveCapacity(64)

        for position in index.indices {
            let entry = index[position]
            guard passesFacets(entry, position: position, filter: filter, favorites: favorites) else { continue }
            guard let score = score(entry, tokens: tokens) else { continue }
            matches.append((score, position))
        }

        matches.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.position < rhs.position : lhs.score > rhs.score
        }

        let selected = limit.map { matches.prefix(max(0, $0)) } ?? matches[...]
        return selected.map { all[$0.position] }
    }

    /// Conteggi per i chip di filtro.
    ///
    /// Ogni dimensione è contata **ignorando il proprio filtro** (faceting classico):
    /// così selezionando "Petto" si continua a vedere quanti esercizi darebbe "Schiena".
    public func facets(for filter: ExerciseFilter, favorites: Set<String> = []) -> ExerciseFacets {
        let tokens = SearchText.tokens(filter.query)

        var categoryCounts: [String: Int] = [:]
        var equipmentCounts: [String: Int] = [:]
        var targetCounts: [String: Int] = [:]
        var favoritesCount = 0
        var total = 0

        var withoutCategories = filter; withoutCategories.categories = []
        var withoutEquipment = filter; withoutEquipment.equipment = []
        var withoutTargets = filter; withoutTargets.targets = []
        var withoutFavorites = filter; withoutFavorites.favoritesOnly = false

        for position in index.indices {
            let entry = index[position]
            guard score(entry, tokens: tokens) != nil else { continue }

            if passesFacets(entry, position: position, filter: withoutCategories, favorites: favorites), !entry.category.isEmpty {
                categoryCounts[entry.category, default: 0] += 1
            }
            if passesFacets(entry, position: position, filter: withoutEquipment, favorites: favorites), !entry.equipment.isEmpty {
                equipmentCounts[entry.equipment, default: 0] += 1
            }
            if passesFacets(entry, position: position, filter: withoutTargets, favorites: favorites), !entry.target.isEmpty {
                targetCounts[entry.target, default: 0] += 1
            }
            if passesFacets(entry, position: position, filter: withoutFavorites, favorites: favorites),
               favorites.contains(all[position].id) {
                favoritesCount += 1
            }
            if passesFacets(entry, position: position, filter: filter, favorites: favorites) {
                total += 1
            }
        }

        return ExerciseFacets(
            categories: Self.facetList(categoryCounts, label: Localization.category),
            equipment: Self.facetList(equipmentCounts, label: Localization.equipment),
            targets: Self.facetList(targetCounts, label: Localization.muscle),
            favorites: favoritesCount,
            total: total
        )
    }

    private static func facetList(_ counts: [String: Int], label: (String) -> String) -> [FacetCount] {
        counts
            .map { FacetCount(value: $0.key, label: label($0.key), count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.label < rhs.label : lhs.count > rhs.count
            }
    }

    /// Esercizi con cui sostituire quello indicato (stesso target, poi stessa categoria).
    ///
    /// Vedi ``Stats/alternatives(for:among:favorites:limit:)`` per i criteri di ordinamento.
    public func alternatives(for exercise: Exercise, favorites: Set<String> = [], limit: Int = 12) -> [Exercise] {
        Stats.alternatives(for: exercise, among: all, favorites: favorites, limit: limit)
    }

    // MARK: - Interni

    private func passesFacets(_ entry: IndexEntry, position: Int, filter: ExerciseFilter, favorites: Set<String>) -> Bool {
        if !filter.categories.isEmpty, !filter.categories.contains(entry.category) { return false }
        if !filter.equipment.isEmpty, !filter.equipment.contains(entry.equipment) { return false }
        if !filter.targets.isEmpty, !filter.targets.contains(entry.target) { return false }
        if filter.favoritesOnly, !favorites.contains(all[position].id) { return false }
        return true
    }

    /// Punteggio di rilevanza, `nil` se anche un solo token non compare (match in AND).
    ///
    /// Priorità: prefisso del nome intero > prefisso di una parola del nome >
    /// sottostringa del nome > match su muscoli/attrezzo/categoria (anche tradotti).
    private func score(_ entry: IndexEntry, tokens: [String]) -> Int? {
        guard !tokens.isEmpty else { return 0 }
        var total = 0
        for token in tokens {
            if entry.nameKey.hasPrefix(token) {
                total += 100
            } else if entry.nameTokens.contains(where: { $0.hasPrefix(token) }) {
                total += 60
            } else if SearchText.contains(entry.nameKey, token) {
                total += 30
            } else if SearchText.contains(entry.haystack, token) {
                total += 10
            } else {
                return nil
            }
        }
        // Un nome che corrisponde esattamente alla query va sempre per primo.
        if entry.nameKey == tokens.joined(separator: " ") { total += 1_000 }
        return total
    }
}
