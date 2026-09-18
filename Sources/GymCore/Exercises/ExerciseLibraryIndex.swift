import Foundation

// MARK: - Presentazione pre-calcolata

/// Titolo e sottoriga di un esercizio, calcolati **una volta** all'indicizzazione.
///
/// Le righe delle liste (libreria, picker, editor della scheda, storico) mostrano
/// sempre le stesse due stringhe: ricostruirle a ogni `body` significa capitalizzare
/// il nome, togliere il prefisso dell'attrezzo e tradurre muscolo e attrezzo per
/// ogni riga visibile, a ogni scroll. Qui esistono già.
///
///     if let p = store.exercisePresentation(id: item.exerciseID) {
///         Text(p.title)
///         Text(p.subtitle)
///     }
public struct ExercisePresentation: Sendable, Hashable, Identifiable {
    /// Id dell'esercizio.
    public let id: String
    /// Titolo della riga.
    public let title: String
    /// Sottoriga "muscolo · attrezzo" in italiano, es. `"Pettorali · Bilanciere"`.
    /// Può essere vuota (esercizi personalizzati senza muscolo né attrezzo).
    public let subtitle: String

    public init(id: String, title: String, subtitle: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    /// Costruisce la presentazione di un esercizio.
    ///
    /// È il **punto unico** in cui si decide quale nome mostrare: oggi
    /// ``Exercise/shortDisplayName`` (nome senza il prefisso dell'attrezzo, che è
    /// già scritto nella sottoriga). Cambiare qui cambia tutta l'app.
    public init(exercise: Exercise) {
        self.init(
            id: exercise.id,
            title: exercise.shortDisplayName,
            subtitle: Self.subtitle(for: exercise)
        )
    }

    /// Sottoriga "muscolo · attrezzo", saltando i campi vuoti.
    public static func subtitle(for exercise: Exercise) -> String {
        [exercise.localizedTarget, exercise.localizedEquipment]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Ranking fondibile

/// Chiave di ordinamento di un risultato di ricerca.
///
/// Esiste per poter ordinare insieme i risultati di **più indici** (libreria del
/// dataset + indice degli esercizi personalizzati) con lo stesso criterio che
/// userebbe un indice unico.
struct SearchRank: Sendable {
    let matchesInName: Bool
    let extraNameTokens: Int
    let score: Int
    let isRedundantVariant: Bool
    /// Nome normalizzato: sostituisce la posizione quando i risultati arrivano da
    /// indici diversi (dentro un indice l'ordine per nome **è** l'ordine per posizione).
    let nameKey: String
    /// `true` per la libreria del dataset: a parità di nome sta prima dei personalizzati.
    let isPrimary: Bool
    /// Posizione nell'indice di provenienza.
    let position: Int

    static func precedes(_ lhs: SearchRank, _ rhs: SearchRank) -> Bool {
        if lhs.matchesInName != rhs.matchesInName { return lhs.matchesInName }
        if lhs.matchesInName {
            if lhs.extraNameTokens != rhs.extraNameTokens { return lhs.extraNameTokens < rhs.extraNameTokens }
        } else if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.isRedundantVariant != rhs.isRedundantVariant { return !lhs.isRedundantVariant }
        if lhs.nameKey != rhs.nameKey { return lhs.nameKey < rhs.nameKey }
        if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
        return lhs.position < rhs.position
    }
}

/// Un esercizio trovato, con la sua chiave di ordinamento.
struct RankedExercise: Sendable {
    let exercise: Exercise
    let rank: SearchRank
}

/// Conteggi grezzi dei facet: additivi, quindi fondibili fra indici.
struct FacetCounts: Sendable {
    var categories: [String: Int] = [:]
    var equipment: [String: Int] = [:]
    var targets: [String: Int] = [:]
    var muscleGroups: [MuscleGroup: Int] = [:]
    var favorites: Int = 0
    var total: Int = 0

    func merging(_ other: FacetCounts) -> FacetCounts {
        FacetCounts(
            categories: categories.merging(other.categories, uniquingKeysWith: +),
            equipment: equipment.merging(other.equipment, uniquingKeysWith: +),
            targets: targets.merging(other.targets, uniquingKeysWith: +),
            muscleGroups: muscleGroups.merging(other.muscleGroups, uniquingKeysWith: +),
            favorites: favorites + other.favorites,
            total: total + other.total
        )
    }

    func makeFacets() -> ExerciseFacets {
        ExerciseFacets(
            categories: ExerciseRepository.facetList(categories, label: Localization.category),
            equipment: ExerciseRepository.facetList(equipment, label: Localization.equipment),
            targets: ExerciseRepository.facetList(targets, label: Localization.muscle),
            favorites: favorites,
            total: total,
            muscleGroups: ExerciseRepository.muscleGroupFacetList(muscleGroups)
        )
    }
}

// MARK: - Indice consultabile

/// Libreria consultabile = indice **base immutabile** del dataset + piccolo indice
/// separato per gli esercizi personalizzati.
///
/// Sostituisce la vecchia fusione in un unico `ExerciseRepository`: creare un
/// esercizio personalizzato non ricostruisce più 1.325 voci di indice, ne costruisce
/// una sola. Ricerca e facet interrogano i due indici e fondono i risultati a valle
/// con lo **stesso ranking** di prima (verificato in GymChecks).
///
/// È `Sendable` e non tocca lo stato dell'app: si può usare dentro un `Task`
/// fuori dal main actor (vedi ``ExerciseSearchSnapshot``).
public struct ExerciseLibraryIndex: Sendable {

    /// Indice del dataset, immutabile per tutta la vita dell'app.
    public let library: ExerciseRepository
    /// Indice degli esercizi personalizzati utilizzabili; `nil` se non ce ne sono.
    public let custom: ExerciseRepository?

    public init(library: ExerciseRepository, custom: ExerciseRepository? = nil) {
        self.library = library
        self.custom = custom
    }

    /// Numero di esercizi consultabili (dataset + personalizzati utilizzabili).
    public var count: Int { library.count + (custom?.count ?? 0) }

    /// Esercizio per id, cercato prima fra i personalizzati.
    public func exercise(id: String) -> Exercise? {
        custom?.exercise(id: id) ?? library.exercise(id: id)
    }

    /// Titolo e sottoriga pre-calcolati. Vedi ``ExercisePresentation``.
    public func presentation(for id: String) -> ExercisePresentation? {
        custom?.presentation(for: id) ?? library.presentation(for: id)
    }

    /// Ricerca su dataset + personalizzati, con lo stesso ordinamento di un indice unico.
    public func search(_ filter: ExerciseFilter = .empty, favorites: Set<String> = [], limit: Int? = nil) -> [Exercise] {
        guard let custom else { return library.search(filter, favorites: favorites, limit: limit) }
        var matches = library.rankedMatches(filter, favorites: favorites, isPrimary: true)
        matches.append(contentsOf: custom.rankedMatches(filter, favorites: favorites, isPrimary: false))
        return ExerciseRepository.ordered(matches, limit: limit)
    }

    /// Facet su dataset + personalizzati: i conteggi dei due indici si sommano.
    public func facets(for filter: ExerciseFilter = .empty, favorites: Set<String> = []) -> ExerciseFacets {
        let base = library.facetCounts(for: filter, favorites: favorites)
        guard let custom else { return base.makeFacets() }
        return base.merging(custom.facetCounts(for: filter, favorites: favorites)).makeFacets()
    }

    /// Esercizi con cui sostituire quello indicato, personalizzati compresi.
    public func alternatives(for exercise: Exercise, favorites: Set<String> = [], limit: Int = 12) -> [Exercise] {
        var candidates = library.all.filter(\.isSelectable)
        if let custom { candidates.append(contentsOf: custom.all.filter(\.isSelectable)) }
        return Stats.alternatives(for: exercise, among: candidates, favorites: favorites, limit: limit)
    }
}

// MARK: - Snapshot per il lavoro in background

/// Fotografia `Sendable` di indice **e** preferiti, pensata per essere usata dentro
/// un `Task` fuori dal main actor.
///
/// Permette alle feature di fare debounce e calcolo in background senza toccare
/// ``AppStore`` (che è `@MainActor`) dal task:
///
///     let snapshot = app.store.exerciseSearchSnapshot()
///     let found = await Task.detached(priority: .userInitiated) {
///         snapshot?.search(filter, limit: 50) ?? []
///     }.value
///
/// Lo snapshot è immutabile: va ripreso quando cambiano i preferiti o i personalizzati.
public struct ExerciseSearchSnapshot: Sendable {

    public let index: ExerciseLibraryIndex
    /// Preferiti al momento dello snapshot.
    public let favorites: Set<String>

    public init(index: ExerciseLibraryIndex, favorites: Set<String>) {
        self.index = index
        self.favorites = favorites
    }

    public func search(_ filter: ExerciseFilter = .empty, limit: Int? = nil) -> [Exercise] {
        index.search(filter, favorites: favorites, limit: limit)
    }

    public func facets(for filter: ExerciseFilter = .empty) -> ExerciseFacets {
        index.facets(for: filter, favorites: favorites)
    }

    public func alternatives(for exercise: Exercise, limit: Int = 12) -> [Exercise] {
        index.alternatives(for: exercise, favorites: favorites, limit: limit)
    }

    public func presentation(for id: String) -> ExercisePresentation? {
        index.presentation(for: id)
    }

    public func exercise(id: String) -> Exercise? { index.exercise(id: id) }
}
