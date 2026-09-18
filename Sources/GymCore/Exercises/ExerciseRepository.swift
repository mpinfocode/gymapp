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
///
/// In costruzione applica ``ExerciseCorrections``: da qui in avanti `target` è
/// quello anatomicamente giusto e il campo `muscle_group` del dataset non viene
/// mai indicizzato (SPEC §2, punti 1 e 2).
public final class ExerciseRepository: Sendable {

    /// Voce di indice: tutte le stringhe sono già normalizzate (vedi ``SearchText``).
    private struct IndexEntry: Sendable {
        let nameKey: String
        /// Byte UTF-8 di ``nameKey`` e delle sue parole: il confronto per byte rende
        /// la ricerca molto più rapida di `String.range(of:)`.
        let nameBytes: [UInt8]
        let nameTokenBytes: [[UInt8]]
        /// Nome + muscoli + attrezzo + categoria + zona, in inglese **e** in italiano.
        /// Non contiene `muscle_group`: è un campo inaffidabile del dataset.
        let haystackBytes: [UInt8]
        let category: String
        let equipment: String
        let target: String
        let muscleGroup: MuscleGroup
        /// `true` per le varianti ridondanti ("v. 2", "(male)", "(back pov)"…).
        let isRedundantVariant: Bool
        /// `false` per i personalizzati eliminati: restano risolvibili per id ma
        /// spariscono da ricerca e facet.
        let isSelectable: Bool
    }

    /// Tutti gli esercizi, ordinati alfabeticamente per nome normalizzato.
    public let all: [Exercise]
    private let byID: [String: Exercise]
    /// Parallelo ad ``all``: stessa posizione, stesso esercizio.
    private let index: [IndexEntry]
    /// Titolo e sottoriga già pronti, calcolati una volta all'indicizzazione.
    private let presentationByID: [String: ExercisePresentation]

    /// - Parameters:
    ///   - exercises: record del dataset e/o esercizi personalizzati.
    ///   - applyingCorrections: applica ``ExerciseCorrections`` ai record del dataset.
    ///     Gli esercizi personalizzati non vengono mai toccati. Lasciarlo `true`
    ///     (default) è la strada normale; `false` serve solo a chi vuole ispezionare
    ///     il dataset grezzo.
    public init(exercises: [Exercise], applyingCorrections: Bool = true) {
        let source = applyingCorrections ? ExerciseCorrections.apply(to: exercises) : exercises

        // Decorate-sort-undecorate: la chiave di ordinamento si calcola **una volta
        // per esercizio** invece che a ogni confronto (con `sorted` il comparatore
        // gira ~n·log n volte, cioè ~28.000 normalizzazioni per 1.324 record).
        var decorated = source.map { (key: SearchText.normalize($0.name), exercise: $0) }
        decorated.sort { $0.key < $1.key }

        all = decorated.map(\.exercise)
        byID = Dictionary(decorated.map { ($0.exercise.id, $0.exercise) }, uniquingKeysWith: { first, _ in first })
        index = decorated.map { ExerciseRepository.makeIndexEntry(for: $0.exercise, nameKey: $0.key) }
        presentationByID = Dictionary(
            decorated.map { ($0.exercise.id, ExercisePresentation(exercise: $0.exercise)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Unisce due indici **già costruiti** senza rinormalizzare nulla.
    ///
    /// Serve alla proprietà di compatibilità ``AppStore/searchableLibrary``: le voci
    /// di indice, le chiavi e le presentazioni sono già calcolate, quindi qui si fa
    /// solo una fusione di due sequenze ordinate. Per la ricerca vera si usa
    /// ``ExerciseLibraryIndex``, che non copia proprio niente.
    init(merging base: ExerciseRepository, with extra: ExerciseRepository) {
        var mergedAll: [Exercise] = []
        var mergedIndex: [IndexEntry] = []
        mergedAll.reserveCapacity(base.all.count + extra.all.count)
        mergedIndex.reserveCapacity(base.index.count + extra.index.count)

        var left = 0
        var right = 0
        while left < base.index.count || right < extra.index.count {
            let takeLeft: Bool
            if left >= base.index.count {
                takeLeft = false
            } else if right >= extra.index.count {
                takeLeft = true
            } else {
                takeLeft = base.index[left].nameKey <= extra.index[right].nameKey
            }
            if takeLeft {
                mergedAll.append(base.all[left])
                mergedIndex.append(base.index[left])
                left += 1
            } else {
                mergedAll.append(extra.all[right])
                mergedIndex.append(extra.index[right])
                right += 1
            }
        }

        all = mergedAll
        index = mergedIndex
        byID = base.byID.merging(extra.byID) { first, _ in first }
        presentationByID = base.presentationByID.merging(extra.presentationByID) { first, _ in first }
    }

    private static func makeIndexEntry(for exercise: Exercise, nameKey: String) -> IndexEntry {
        var terms: [String] = [
            nameKey,
            SearchText.normalize(exercise.category),
            SearchText.normalize(exercise.equipment),
            SearchText.normalize(exercise.target),
            SearchText.normalize(Localization.category(exercise.category)),
            SearchText.normalize(Localization.equipment(exercise.equipment)),
            SearchText.normalize(Localization.muscle(exercise.target)),
            SearchText.normalize(exercise.muscleGroupKind.displayName),
        ]
        for muscle in exercise.secondaryMuscles {
            terms.append(SearchText.normalize(muscle))
            terms.append(SearchText.normalize(Localization.muscle(muscle)))
        }
        if !exercise.notes.isEmpty { terms.append(SearchText.normalize(exercise.notes)) }
        // Deduplica mantenendo l'ordine, poi unisce con " | " per evitare match a cavallo di due termini.
        var seen: Set<String> = []
        let unique = terms.filter { !$0.isEmpty && seen.insert($0).inserted }
        let tokens = nameKey.split(separator: " ").map(String.init)
        return IndexEntry(
            nameKey: nameKey,
            nameBytes: Array(nameKey.utf8),
            nameTokenBytes: tokens.map { Array($0.utf8) },
            haystackBytes: Array(unique.joined(separator: " | ").utf8),
            category: exercise.category,
            equipment: exercise.equipment,
            target: exercise.target,
            muscleGroup: exercise.muscleGroupKind,
            isRedundantVariant: Exercise.isRedundantVariant(nameTokens: tokens),
            isSelectable: exercise.isSelectable
        )
    }

    // MARK: - Caricamento

    /// Carica e indicizza `exercises.json` da `Bundle.module` fuori dal main thread.
    ///
    /// - Parameter applyingCorrections: `false` restituisce il dataset **grezzo**,
    ///   utile solo ai check per misurare quante e quali correzioni scattano.
    public static func loadFromBundle(applyingCorrections: Bool = true) async throws -> ExerciseRepository {
        try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
                throw ExerciseRepositoryError.resourceMissing("exercises.json")
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let exercises = try JSONDecoder().decode([Exercise].self, from: data)
            return ExerciseRepository(exercises: exercises, applyingCorrections: applyingCorrections)
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

    /// Titolo e sottoriga **pre-calcolati** all'indicizzazione.
    ///
    /// Le righe della UI non devono ricostruire "Pettorali · Bilanciere" a ogni
    /// `body`: qui la stringa esiste già ed è la stessa istanza per tutta la vita
    /// dell'indice. Vedi ``ExercisePresentation``.
    public func presentation(for id: String) -> ExercisePresentation? { presentationByID[id] }

    /// Valori distinti di una dimensione, ordinati per etichetta italiana.
    public var allCategories: [String] { distinct(\.category) }
    public var allEquipment: [String] { distinct(\.equipment) }
    public var allTargets: [String] { distinct(\.target) }

    /// Zone colpite presenti in libreria, nell'ordine stabile di ``MuscleGroup``.
    public var allMuscleGroups: [MuscleGroup] {
        let present = Set(all.map(\.muscleGroupKind))
        return MuscleGroup.displayOrder.filter(present.contains)
    }

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
    /// La query passa da ``ItalianSynonyms``: ogni parola o espressione italiana si
    /// espande in alternative inglesi **in OR**, i gruppi restano **in AND** fra loro.
    /// Il termine digitato resta sempre fra le alternative, quindi nessuna query che
    /// funzionava prima smette di funzionare.
    ///
    /// - Parameters:
    ///   - filter: criteri combinati.
    ///   - favorites: id preferiti, necessari se `filter.favoritesOnly` è attivo.
    ///   - limit: numero massimo di risultati (`nil` = tutti).
    public func search(_ filter: ExerciseFilter, favorites: Set<String> = [], limit: Int? = nil) -> [Exercise] {
        Self.ordered(rankedMatches(filter, favorites: favorites, isPrimary: true), limit: limit)
    }

    /// Risultati **non ordinati** con la loro chiave di ranking.
    ///
    /// È il mattone che permette a ``ExerciseLibraryIndex`` di fondere i risultati
    /// dell'indice base con quelli del piccolo indice dei personalizzati senza
    /// ricostruire un indice unico: si concatenano le due liste e si ordina con lo
    /// stesso comparatore, quindi il ranking resta identico.
    func rankedMatches(_ filter: ExerciseFilter, favorites: Set<String>, isPrimary: Bool) -> [RankedExercise] {
        let query = makeQuery(filter.query)
        var cache = [Int](repeating: Self.notComputed, count: query.terms.count)
        var matches: [RankedExercise] = []
        matches.reserveCapacity(64)

        for position in index.indices {
            let entry = index[position]
            guard passesFacets(entry, position: position, filter: filter, favorites: favorites) else { continue }
            guard var match = score(entry, query: query, cache: &cache) else { continue }
            if match.matchesInName { match.extraNameTokens = extraNameTokens(entry, query: query) }
            matches.append(
                RankedExercise(
                    exercise: all[position],
                    rank: SearchRank(
                        matchesInName: match.matchesInName,
                        extraNameTokens: match.extraNameTokens,
                        score: match.score,
                        isRedundantVariant: match.isRedundantVariant,
                        nameKey: entry.nameKey,
                        isPrimary: isPrimary,
                        position: position
                    )
                )
            )
        }
        return matches
    }

    /// Ordina i risultati (di uno o più indici) e applica l'eventuale limite.
    ///
    /// Ordinamento (vedi ``Match``): prima chi soddisfa la query dentro al **nome**,
    /// e lì vince l'esercizio "canonico", cioè quello con meno parole di troppo
    /// ("dumbbell lateral raise" prima di "dumbbell incline one arm lateral raise").
    /// Chi corrisponde solo per muscolo/attrezzo resta ordinato per punteggio.
    static func ordered(_ matches: [RankedExercise], limit: Int? = nil) -> [Exercise] {
        var matches = matches
        matches.sort { SearchRank.precedes($0.rank, $1.rank) }
        let selected = limit.map { matches.prefix(max(0, $0)) } ?? matches[...]
        return selected.map(\.exercise)
    }

    /// Conteggi per i chip di filtro.
    ///
    /// Ogni dimensione è contata **ignorando il proprio filtro** (faceting classico):
    /// così selezionando "Petto" si continua a vedere quanti esercizi darebbe "Schiena".
    public func facets(for filter: ExerciseFilter, favorites: Set<String> = []) -> ExerciseFacets {
        facetCounts(for: filter, favorites: favorites).makeFacets()
    }

    /// Conteggi grezzi dei facet, **additivi**: sommando quelli di due indici si
    /// ottengono esattamente i conteggi di un indice unico (vedi ``ExerciseLibraryIndex``).
    func facetCounts(for filter: ExerciseFilter, favorites: Set<String>) -> FacetCounts {
        let query = makeQuery(filter.query)
        var cache = [Int](repeating: Self.notComputed, count: query.terms.count)

        var categoryCounts: [String: Int] = [:]
        var equipmentCounts: [String: Int] = [:]
        var targetCounts: [String: Int] = [:]
        var muscleGroupCounts: [MuscleGroup: Int] = [:]
        var favoritesCount = 0
        var total = 0

        var withoutCategories = filter; withoutCategories.categories = []
        var withoutEquipment = filter; withoutEquipment.equipment = []
        var withoutTargets = filter; withoutTargets.targets = []
        var withoutMuscleGroups = filter; withoutMuscleGroups.muscleGroups = []
        var withoutFavorites = filter; withoutFavorites.favoritesOnly = false

        for position in index.indices {
            let entry = index[position]
            guard entry.isSelectable else { continue }
            guard score(entry, query: query, cache: &cache) != nil else { continue }

            if passesFacets(entry, position: position, filter: withoutCategories, favorites: favorites), !entry.category.isEmpty {
                categoryCounts[entry.category, default: 0] += 1
            }
            if passesFacets(entry, position: position, filter: withoutEquipment, favorites: favorites), !entry.equipment.isEmpty {
                equipmentCounts[entry.equipment, default: 0] += 1
            }
            if passesFacets(entry, position: position, filter: withoutTargets, favorites: favorites), !entry.target.isEmpty {
                targetCounts[entry.target, default: 0] += 1
            }
            if passesFacets(entry, position: position, filter: withoutMuscleGroups, favorites: favorites) {
                muscleGroupCounts[entry.muscleGroup, default: 0] += 1
            }
            if passesFacets(entry, position: position, filter: withoutFavorites, favorites: favorites),
               favorites.contains(all[position].id) {
                favoritesCount += 1
            }
            if passesFacets(entry, position: position, filter: filter, favorites: favorites) {
                total += 1
            }
        }

        return FacetCounts(
            categories: categoryCounts,
            equipment: equipmentCounts,
            targets: targetCounts,
            muscleGroups: muscleGroupCounts,
            favorites: favoritesCount,
            total: total
        )
    }

    static func facetList(_ counts: [String: Int], label: (String) -> String) -> [FacetCount] {
        counts
            .map { FacetCount(value: $0.key, label: label($0.key), count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.label < rhs.label : lhs.count > rhs.count
            }
    }

    /// I chip "zona colpita" restano nell'ordine anatomico di ``MuscleGroup``:
    /// sono pochi e fissi, se ballassero a ogni ricerca sarebbero inutilizzabili.
    static func muscleGroupFacetList(_ counts: [MuscleGroup: Int]) -> [MuscleGroupFacet] {
        MuscleGroup.displayOrder.compactMap { group in
            guard let count = counts[group], count > 0 else { return nil }
            return MuscleGroupFacet(group: group, count: count)
        }
    }

    /// Esercizi con cui sostituire quello indicato (stesso target, poi stessa categoria).
    ///
    /// Vedi ``Stats/alternatives(for:among:favorites:limit:)`` per i criteri di ordinamento.
    public func alternatives(for exercise: Exercise, favorites: Set<String> = [], limit: Int = 12) -> [Exercise] {
        Stats.alternatives(for: exercise, among: all.filter(\.isSelectable), favorites: favorites, limit: limit)
    }

    // MARK: - Interni

    /// Un termine della query con i suoi byte UTF-8 già pronti.
    ///
    /// Le stringhe normalizzate sono ASCII (``SearchText`` toglie diacritici e
    /// punteggiatura), quindi confrontare byte è corretto ed è molto più veloce di
    /// `String.range(of:)`: la ricerca deve restare istantanea mentre si digita.
    private struct Term: Sendable {
        let bytes: [UInt8]
        init(_ text: String) { bytes = Array(text.utf8) }
    }

    /// Un'alternativa: i suoi termini (indici nella tabella dei termini distinti)
    /// sono in AND.
    private struct Alternative: Sendable {
        let terms: [Int]
        /// La frase intera (`"barbell bench press"`), per i bonus di contiguità.
        let phrase: [UInt8]
        let isPhrase: Bool
    }

    /// Un gruppo della query: le alternative sono in OR.
    private struct QueryGroup: Sendable {
        let alternatives: [Alternative]
    }

    /// Query pronta per lo scorer.
    ///
    /// I termini distinti stanno in una tabella: la stessa parola che compare in più
    /// alternative ("pulldown" in `cable pulldown`, `lat pulldown` e `pulldown`) viene
    /// così valutata una volta sola per esercizio.
    private struct Query: Sendable {
        let groups: [QueryGroup]
        let terms: [Term]
        /// Query normalizzata intera, per il bonus "nome identico a quanto digitato".
        let exactKey: String
        var isEmpty: Bool { groups.isEmpty }
    }

    private func makeQuery(_ text: String) -> Query {
        let tokens = SearchText.tokens(text)
        var terms: [Term] = []
        var termIndex: [String: Int] = [:]

        func index(of term: String) -> Int {
            if let existing = termIndex[term] { return existing }
            terms.append(Term(term))
            termIndex[term] = terms.count - 1
            return terms.count - 1
        }

        let groups = ItalianSynonyms.expand(tokens: tokens).map { group in
            QueryGroup(alternatives: group.alternatives.map { words in
                Alternative(
                    terms: words.map(index(of:)),
                    phrase: Array(words.joined(separator: " ").utf8),
                    isPhrase: words.count > 1
                )
            })
        }
        return Query(groups: groups, terms: terms, exactKey: tokens.joined(separator: " "))
    }

    private func passesFacets(_ entry: IndexEntry, position: Int, filter: ExerciseFilter, favorites: Set<String>) -> Bool {
        if !entry.isSelectable { return false }
        if !filter.categories.isEmpty, !filter.categories.contains(entry.category) { return false }
        if !filter.equipment.isEmpty, !filter.equipment.contains(entry.equipment) { return false }
        if !filter.targets.isEmpty, !filter.targets.contains(entry.target) { return false }
        if !filter.muscleGroups.isEmpty, !filter.muscleGroups.contains(entry.muscleGroup) { return false }
        if filter.favoritesOnly, !favorites.contains(all[position].id) { return false }
        return true
    }

    /// Esito della valutazione di un esercizio rispetto a una query.
    ///
    /// L'ordinamento finale usa, in quest'ordine:
    /// 1. ``matchesInName``: chi soddisfa **tutti** i gruppi dentro al nome sta sopra
    ///    a chi corrisponde solo per muscolo, attrezzo o zona;
    /// 2. ``extraNameTokens``: fra quelli, vince il nome con meno parole di troppo,
    ///    cioè l'esercizio "canonico" (`dumbbell lateral raise` prima di
    ///    `dumbbell incline one arm lateral raise`);
    /// 3. ``isRedundantVariant``: le varianti ridondanti ("v. 2", "(male)",
    ///    "(side pov)") dopo la loro base (SPEC §2, punto 4);
    /// 4. ordine alfabetico (la posizione nell'indice).
    ///
    /// ``score`` serve solo a ordinare chi **non** corrisponde nel nome.
    private struct Match {
        let score: Int
        let matchesInName: Bool
        let isRedundantVariant: Bool
        var extraNameTokens: Int = 0
    }

    /// Valuta un esercizio, `nil` se anche un solo gruppo resta senza riscontro.
    ///
    /// Priorità per singolo termine: prefisso del nome intero (100) > prefisso di una
    /// parola del nome (60) > sottostringa del nome (30) > match su
    /// muscoli/attrezzo/categoria/zona, anche tradotti (10).
    ///
    /// Un'alternativa di più parole prende un bonus se le parole compaiono **di fila**
    /// nel nome, e il bonus massimo se il nome è esattamente quella frase.
    ///
    /// - Parameter cache: buffer riusato fra un esercizio e l'altro (una allocazione
    ///   per ricerca invece di 1.324).
    private func score(_ entry: IndexEntry, query: Query, cache: inout [Int]) -> Match? {
        // Senza query si sta sfogliando la libreria: l'ordine resta alfabetico puro,
        // le varianti stanno accanto alla loro base.
        guard !query.isEmpty else {
            return Match(score: 0, matchesInName: false, isRedundantVariant: false)
        }

        for position in cache.indices { cache[position] = Self.notComputed }

        var total = 0
        var matchesInName = true
        for group in query.groups {
            var best: Int?
            var bestInName = false
            for alternative in group.alternatives {
                guard let value = score(entry, alternative: alternative, query: query, cache: &cache) else { continue }
                if best == nil || value.score > best! {
                    best = value.score
                    bestInName = value.inName
                } else if value.score == best!, value.inName {
                    bestInName = true
                }
            }
            guard let best else { return nil }
            total += best
            if !bestInName { matchesInName = false }
        }

        // Un nome che corrisponde esattamente a quanto digitato va sempre per primo.
        if entry.nameKey == query.exactKey { total += Self.exactNameBonus }
        return Match(score: total, matchesInName: matchesInName, isRedundantVariant: entry.isRedundantVariant)
    }

    /// Punteggio di una singola alternativa: i suoi termini sono in AND.
    ///
    /// `inName` è vero quando **ogni** termine dell'alternativa compare nel nome
    /// (punteggio ≥ 30) e non solo fra muscoli/attrezzo/categoria.
    ///
    /// In un'alternativa di più parole quel vincolo è obbligatorio: senza, "upper back"
    /// verrebbe soddisfatto da un `backward jump` di categoria `upper legs`, cioè da
    /// due campi diversi che per caso contengono le due parole.
    private func score(
        _ entry: IndexEntry,
        alternative: Alternative,
        query: Query,
        cache: inout [Int]
    ) -> (score: Int, inName: Bool)? {
        var total = 0
        var inName = true
        for term in alternative.terms {
            let value = score(entry, termAt: term, query: query, cache: &cache)
            guard value != Self.noMatch else { return nil }
            if value < 30 {
                if alternative.isPhrase { return nil }
                inName = false
            }
            total += value
        }
        guard alternative.isPhrase else { return (total, inName) }
        if entry.nameBytes == alternative.phrase {
            total += Self.exactNameBonus
        } else if Self.contains(entry.nameBytes, alternative.phrase) {
            total += Self.phraseBonus
        }
        return (total, inName)
    }

    private func score(_ entry: IndexEntry, termAt position: Int, query: Query, cache: inout [Int]) -> Int {
        if cache[position] != Self.notComputed { return cache[position] }
        let bytes = query.terms[position].bytes
        var value = Self.noMatch
        if Self.hasPrefix(entry.nameBytes, bytes) {
            value = 100
        } else if entry.nameTokenBytes.contains(where: { Self.hasPrefix($0, bytes) }) {
            value = 60
        } else if Self.contains(entry.nameBytes, bytes) {
            value = 30
        } else if Self.contains(entry.haystackBytes, bytes) {
            value = 10
        }
        cache[position] = value
        return value
    }

    /// Quante parole del nome **non** sono coperte da nessun termine della query espansa.
    ///
    /// È la misura di quanto l'esercizio è "in più" rispetto a quello che si è cercato:
    /// per "alzate laterali manubri" `dumbbell lateral raise` vale 0,
    /// `dumbbell incline one arm lateral raise` vale 3.
    private func extraNameTokens(_ entry: IndexEntry, query: Query) -> Int {
        var extra = 0
        for token in entry.nameTokenBytes {
            let covered = query.terms.contains { term in
                Self.hasPrefix(token, term.bytes) || Self.contains(token, term.bytes)
            }
            if !covered { extra += 1 }
        }
        return extra
    }

    // MARK: - Confronti byte a byte

    private static func hasPrefix(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for offset in needle.indices where haystack[offset] != needle[offset] { return false }
        return true
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard needle.count <= haystack.count else { return false }
        let first = needle[0]
        let last = haystack.count - needle.count
        var start = 0
        while start <= last {
            if haystack[start] == first {
                var offset = 1
                while offset < needle.count, haystack[start + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }

    /// Bonus del match esatto sul nome.
    private static let exactNameBonus = 1_000
    /// Bonus di una frase che compare di fila nel nome.
    private static let phraseBonus = 40
    /// Sentinelle della cache dei punteggi per termine.
    private static let notComputed = Int.min
    private static let noMatch = Int.min + 1
}
