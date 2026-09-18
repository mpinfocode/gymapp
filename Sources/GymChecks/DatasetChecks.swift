import Foundation
import GymCore

/// Check su dataset, traduzioni, ricerca e filtri. Restituisce il repository
/// caricato perché lo riusino gli altri check.
@MainActor
func runDatasetChecks(_ h: Harness) async -> ExerciseRepository? {

    h.section("dataset · caricamento")

    let repository: ExerciseRepository
    do {
        repository = try await ExerciseRepository.loadFromBundle()
    } catch {
        h.fail("caricamento di exercises.json dal bundle: \(error)")
        return nil
    }

    h.check("1.324 esercizi decodificati", repository.count == 1_324)
    h.check("id univoci", Set(repository.all.map(\.id)).count == repository.count)
    h.check("nessun nome vuoto", repository.all.allSatisfy { !$0.name.isEmpty })
    h.check("tutti hanno istruzioni", repository.all.allSatisfy { !$0.steps.isEmpty })
    h.check("tutti hanno una GIF", repository.all.allSatisfy { $0.gifURL != nil })
    h.check("tutti hanno un'immagine", repository.all.allSatisfy { $0.imageURL != nil })
    h.check("tutti hanno l'attribuzione Gym visual", repository.all.allSatisfy { $0.attribution.contains("Gym visual") })
    h.check("tutti hanno categoria, attrezzo e target", repository.all.allSatisfy {
        !$0.category.isEmpty && !$0.equipment.isEmpty && !$0.target.isEmpty
    })
    h.check("GIF sul prefisso corretto", repository.all.allSatisfy {
        $0.gifURL?.absoluteString.hasPrefix("https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/") == true
    })
    h.check("10 categorie", repository.allCategories.count == 10)
    h.check("28 attrezzi", repository.allEquipment.count == 28)
    h.check("19 target", repository.allTargets.count == 19)
    h.check("ordinamento alfabetico stabile", repository.all.map(\.name) == repository.all.map(\.name).sorted {
        SearchText.normalize($0) < SearchText.normalize($1)
    })

    // Lookup per id
    h.check("lookup per id", repository.exercise(id: "0025")?.name == "barbell bench press")
    h.check("lookup id inesistente → nil", repository.exercise(id: "zzzz") == nil)
    h.check("lookup multiplo mantiene l'ordine", repository.exercises(ids: ["0043", "0025"]).map(\.id) == ["0043", "0025"])
    h.check("lookup multiplo salta gli id ignoti", repository.exercises(ids: ["0025", "nope"]).count == 1)
    h.check("indice per id completo", repository.exercisesByID().count == repository.count)

    // MARK: Traduzioni

    h.section("dataset · copertura Localization")

    h.check("10 categorie tradotte", Localization.categoryTranslations.count == 10)
    h.check("28 attrezzi tradotti", Localization.equipmentTranslations.count == 28)
    h.check("50 muscoli tradotti", Localization.muscleTranslations.count == 50)

    let missing = Localization.missingTerms(in: repository.all)
    h.check("nessuna categoria senza traduzione: \(missing.categories)", missing.categories.isEmpty)
    h.check("nessun attrezzo senza traduzione: \(missing.equipment)", missing.equipment.isEmpty)
    h.check("nessun muscolo senza traduzione: \(missing.muscles)", missing.muscles.isEmpty)

    var allTranslations: [String] = Array(Localization.categoryTranslations.values)
    allTranslations.append(contentsOf: Localization.equipmentTranslations.values)
    allTranslations.append(contentsOf: Localization.muscleTranslations.values)
    h.check("nessuna traduzione vuota", allTranslations.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })

    // Nessuna chiave inutile: le mappe devono rispecchiare esattamente il dataset.
    var datasetCategories: Set<String> = []
    var datasetEquipment: Set<String> = []
    var datasetMuscles: Set<String> = []
    for exercise in repository.all {
        datasetCategories.insert(exercise.category)
        datasetCategories.insert(exercise.bodyPart)
        datasetEquipment.insert(exercise.equipment)
        datasetMuscles.insert(exercise.target)
        datasetMuscles.insert(exercise.muscleGroup)
        datasetMuscles.formUnion(exercise.secondaryMuscles)
    }
    let staleCategories = Set(Localization.categoryTranslations.keys).subtracting(datasetCategories)
    let staleEquipment = Set(Localization.equipmentTranslations.keys).subtracting(datasetEquipment)
    let staleMuscles = Set(Localization.muscleTranslations.keys).subtracting(datasetMuscles)
    h.check("nessuna categoria tradotta di troppo: \(staleCategories.sorted())", staleCategories.isEmpty)
    h.check("nessun attrezzo tradotto di troppo: \(staleEquipment.sorted())", staleEquipment.isEmpty)
    h.check("nessun muscolo tradotto di troppo: \(staleMuscles.sorted())", staleMuscles.isEmpty)

    h.check("traduzione categoria", Localization.category("upper legs") == "Gambe")
    h.check("traduzione attrezzo", Localization.equipment("leverage machine") == "Macchina a leva")
    h.check("traduzione muscolo", Localization.muscle("hamstrings") == "Femorali")
    h.check("lookup insensibile a maiuscole e spazi", Localization.equipment("  BODY WEIGHT ") == "Corpo libero")
    h.check("termine ignoto → fallback capitalizzato", Localization.muscle("space biceps") == "Space Biceps")
    h.check("stringa vuota → vuota", Localization.category("") == "")
    h.check("lista muscoli deduplicata", Localization.muscles(["lats", "latissimus dorsi", "lats", "traps", "trapezius"]) == ["Dorsali", "Gran dorsale", "Trapezio"])

    // MARK: Ricerca

    h.section("dataset · ricerca")

    func search(_ query: String, favorites: Set<String> = []) -> [Exercise] {
        repository.search(ExerciseFilter(query: query), favorites: favorites)
    }

    h.check("query vuota → tutta la libreria", search("").count == repository.count)
    h.check("query di soli spazi → tutta la libreria", search("   ").count == repository.count)

    let exactMatch = search("barbell bench press")
    h.check("match esatto in prima posizione", exactMatch.first?.id == "0025")

    let benchPress = search("bench press")
    h.check("ricerca parziale trova la panca piana", benchPress.contains { $0.id == "0025" })
    h.check("tutti i risultati contengono entrambi i token", benchPress.allSatisfy {
        let key = SearchText.normalize($0.name)
        return key.contains("bench") && key.contains("press")
    })

    let prefixed = search("barbell")
    h.check("i nomi che iniziano con la query vengono prima", prefixed.first?.name.hasPrefix("barbell") == true)

    // Diacritici e maiuscole
    h.check("case-insensitive", search("BARBELL BENCH PRESS").map(\.id) == exactMatch.map(\.id))
    h.check("punteggiatura equivalente a spazio", search("pull up").map(\.id) == search("pull-up").map(\.id))
    h.check("ricerca con accenti", !search("glutèi").isEmpty)
    h.check("trova il pull-up esatto", search("pull-up").first?.id == "0652")

    // Ricerca sui termini italiani tradotti
    let dumbbells = search("manubri")
    h.check("ricerca italiana su attrezzo: risultati", dumbbells.count > 100)
    h.check("ricerca italiana su attrezzo: coerenti", dumbbells.allSatisfy { $0.equipment == "dumbbell" })
    h.check("ricerca italiana su attrezzo = filtro equivalente",
            dumbbells.count == repository.search(ExerciseFilter(equipment: ["dumbbell"])).count)

    let pectorals = search("pettorali")
    h.check("ricerca italiana su muscolo: risultati", !pectorals.isEmpty)
    h.check("ricerca italiana su muscolo: coerenti", pectorals.allSatisfy {
        ([$0.target, $0.muscleGroup] + $0.secondaryMuscles).contains("pectorals")
    })

    let italianCategory = search("gambe")
    h.check("ricerca italiana su categoria", !italianCategory.isEmpty && italianCategory.allSatisfy { $0.category == "upper legs" })

    h.check("apostrofo nelle traduzioni: 'flessori dell'anca'", !search("flessori dell'anca").isEmpty)
    h.check("apostrofo omesso dà lo stesso risultato", search("flessori dell anca").count == search("flessori dell'anca").count)

    // Ricerca mista inglese + italiano
    let mixed = search("bilanciere squat")
    h.check("query mista italiano+inglese", !mixed.isEmpty && mixed.allSatisfy {
        $0.equipment == "barbell" && SearchText.normalize($0.name).contains("squat")
    })

    h.check("query senza riscontri → vuoto", search("zzz nessun esercizio").isEmpty)
    h.check("limite risultati rispettato", repository.search(ExerciseFilter(query: "press"), limit: 5).count == 5)
    h.check("limite 0 → vuoto", repository.search(ExerciseFilter(query: "press"), limit: 0).isEmpty)

    // MARK: Filtri

    h.section("dataset · filtri e facets")

    let chest = repository.search(ExerciseFilter(categories: ["chest"]))
    h.check("filtro categoria", !chest.isEmpty && chest.allSatisfy { $0.category == "chest" })

    let chestBarbell = repository.search(ExerciseFilter(categories: ["chest"], equipment: ["barbell"]))
    h.check("filtri combinati in AND", !chestBarbell.isEmpty && chestBarbell.allSatisfy { $0.category == "chest" && $0.equipment == "barbell" })
    h.check("combinare filtri restringe", chestBarbell.count < chest.count)

    let twoCategories = repository.search(ExerciseFilter(categories: ["chest", "back"]))
    h.check("più valori nella stessa dimensione sono in OR", twoCategories.allSatisfy { $0.category == "chest" || $0.category == "back" })
    h.check("OR somma i due insiemi", twoCategories.count == chest.count + repository.search(ExerciseFilter(categories: ["back"])).count)

    let targeted = repository.search(ExerciseFilter(targets: ["biceps"]))
    h.check("filtro target", !targeted.isEmpty && targeted.allSatisfy { $0.target == "biceps" })

    let queryAndFilter = repository.search(ExerciseFilter(query: "press", categories: ["chest"]))
    h.check("query + filtro", !queryAndFilter.isEmpty && queryAndFilter.allSatisfy {
        $0.category == "chest" && SearchText.normalize($0.name).contains("press")
    })

    let favorites: Set<String> = ["0025", "0043", "0652"]
    let onlyFavorites = repository.search(ExerciseFilter(favoritesOnly: true), favorites: favorites)
    h.check("solo preferiti", Set(onlyFavorites.map(\.id)) == favorites)
    h.check("preferiti + categoria", repository.search(ExerciseFilter(categories: ["chest"], favoritesOnly: true), favorites: favorites).map(\.id) == ["0025"])
    h.check("preferiti senza elenco → vuoto", repository.search(ExerciseFilter(favoritesOnly: true)).isEmpty)
    h.check("filtro con valore inesistente → vuoto", repository.search(ExerciseFilter(categories: ["marte"])).isEmpty)

    var toggling = ExerciseFilter()
    h.check("filtro vuoto", toggling.isEmpty)
    toggling.toggleCategory("chest")
    h.check("toggle accende", toggling.categories == ["chest"] && toggling.activeFacetCount == 1)
    toggling.toggleCategory("chest")
    h.check("toggle spegne", toggling.categories.isEmpty)
    toggling.toggleEquipment("barbell")
    toggling.favoritesOnly = true
    toggling.query = "press"
    toggling.clearFacets()
    h.check("clearFacets tiene la query", toggling.query == "press" && toggling.activeFacetCount == 0)

    // Facets
    let allFacets = repository.facets(for: ExerciseFilter())
    h.check("facets: totale = libreria", allFacets.total == repository.count)
    h.check("facets: 10 categorie", allFacets.categories.count == 10)
    h.check("facets: 28 attrezzi", allFacets.equipment.count == 28)
    h.check("facets: 19 target", allFacets.targets.count == 19)
    h.check("facets: somma categorie = totale", allFacets.categories.reduce(0) { $0 + $1.count } == repository.count)
    h.check("facets: conteggio petto coerente", allFacets.categories.first { $0.value == "chest" }?.count == chest.count)
    h.check("facets: etichette tradotte", allFacets.categories.first { $0.value == "chest" }?.label == "Petto")
    h.check("facets: ordinati per conteggio decrescente", zip(allFacets.categories, allFacets.categories.dropFirst()).allSatisfy { $0.count >= $1.count })

    let chestFacets = repository.facets(for: ExerciseFilter(categories: ["chest"]))
    h.check("facets: totale segue il filtro", chestFacets.total == chest.count)
    h.check("facets: la dimensione filtrata resta completa", chestFacets.categories.count == 10)
    h.check("facets: le altre dimensioni si restringono", chestFacets.equipment.reduce(0) { $0 + $1.count } == chest.count)

    let favoriteFacets = repository.facets(for: ExerciseFilter(), favorites: favorites)
    h.check("facets: conteggio preferiti", favoriteFacets.favorites == favorites.count)

    let queryFacets = repository.facets(for: ExerciseFilter(query: "barbell curl"))
    h.check("facets: seguono la query", queryFacets.total == search("barbell curl").count)

    // MARK: Esercizi alternativi

    h.section("dataset · esercizi alternativi")

    guard let benchPressExercise = repository.exercise(id: "0025") else {
        h.fail("panca piana assente dal dataset")
        return repository
    }

    let alternatives = repository.alternatives(for: benchPressExercise, limit: 10)
    h.check("propone alternative", !alternatives.isEmpty)
    h.check("non propone l'esercizio stesso", !alternatives.contains { $0.id == "0025" })
    h.check("rispetta il limite", alternatives.count <= 10)
    h.check("tutte pertinenti (stesso target o stessa categoria)", alternatives.allSatisfy {
        $0.target == benchPressExercise.target || $0.category == benchPressExercise.category
    })
    h.check("lo stesso target viene prima della sola categoria", {
        guard let lastSameTarget = alternatives.lastIndex(where: { $0.target == benchPressExercise.target }) else { return true }
        return alternatives.prefix(lastSameTarget + 1).allSatisfy { $0.target == benchPressExercise.target }
    }())
    h.check("privilegia un attrezzo diverso dall'originale", alternatives.first?.equipment != benchPressExercise.equipment)

    let favoriteAlternatives = repository.alternatives(for: benchPressExercise, favorites: ["0308"], limit: 10)
    h.check("un preferito sale in classifica",
            (favoriteAlternatives.firstIndex { $0.id == "0308" } ?? .max) <= (alternatives.firstIndex { $0.id == "0308" } ?? .max))

    h.check("limite 0 → nessuna alternativa", repository.alternatives(for: benchPressExercise, limit: 0).isEmpty)
    let orphan = Exercise(id: "zz", name: "esercizio inventato")
    h.check("esercizio senza target né categoria → nessuna alternativa",
            Stats.alternatives(for: orphan, among: repository.all).isEmpty)

    // MARK: Nessun trattino lungo nelle stringhe mostrate

    h.section("testi · nessun trattino lungo")

    let forbidden: [Character] = ["\u{2014}", "\u{2013}"]
    func hasLongDash(_ text: String) -> Bool { text.contains { forbidden.contains($0) } }

    var uiStrings: [String] = []
    uiStrings.append(contentsOf: Localization.categoryTranslations.values)
    uiStrings.append(contentsOf: Localization.equipmentTranslations.values)
    uiStrings.append(contentsOf: Localization.muscleTranslations.values)
    uiStrings.append(Exercise.displayAttribution)
    uiStrings.append(Exercise.defaultAttribution)
    uiStrings.append(contentsOf: Weekday.allCases.flatMap { [$0.displayName, $0.shortName, $0.letter] })
    uiStrings.append(contentsOf: SetKind.allCases.map(\.displayName))
    uiStrings.append(contentsOf: MeasureKind.allCases.map(\.displayName))
    uiStrings.append(contentsOf: ProgramMode.allCases.flatMap { [$0.displayName, $0.explanation] })
    uiStrings.append(contentsOf: Stats.RecordKind.allCases.flatMap { [$0.displayName, $0.badge] })
    uiStrings.append(contentsOf: BodyMetricKind.allCases.flatMap { [$0.displayName, $0.shortName] })
    uiStrings.append(contentsOf: WeightUnit.allCases.map(\.displayName))

    let sample = SampleProgram.make(startDate: Date(), now: Date())
    uiStrings.append(sample.name)
    uiStrings.append(sample.notes)
    uiStrings.append(sample.statusText())
    uiStrings.append(contentsOf: sample.days.flatMap { [$0.name, $0.note] })
    uiStrings.append(contentsOf: sample.days.flatMap(\.items).flatMap { [$0.note, $0.summary(), $0.measure.displayText] })

    let progressionItem = PlanItem(exerciseID: "0025", targetSets: 3, measure: .reps(min: 6, max: 8))
    let maxedSession = WorkoutSession(
        name: "x",
        startedAt: Date(),
        endedAt: Date(),
        entries: [SessionEntry(exerciseID: "0025", sets: (0..<3).map { _ in
            SetLog(kind: .normal, weightKg: 80, reps: 8, completedAt: Date())
        })]
    )
    for equipment in ["barbell", "dumbbell"] {
        if let suggestion = Stats.progressionSuggestion(for: progressionItem, lastSession: maxedSession, equipment: equipment) {
            uiStrings.append(suggestion.reason)
        }
    }
    uiStrings.append(contentsOf: [
        Stats.formatDuration(4_320), Stats.formatVolume(12_400),
        WeightUnit.kg.format(kilograms: 82.5), BackupPayload(programs: [], sessions: [], bodyEntries: [], settings: UserSettings()).summary,
    ])

    let offenders = uiStrings.filter(hasLongDash)
    h.check("nessun trattino lungo nelle stringhe di presentazione: \(offenders)", offenders.isEmpty)
    h.check("attribuzione di presentazione col separatore corretto", Exercise.displayAttribution == "© Gym visual · https://gymvisual.com/")
    h.check("il controllo sa riconoscere un trattino lungo", hasLongDash("Gym visual \u{2014} gymvisual"))

    // MARK: Prestazioni

    h.section("dataset · prestazioni")

    let queries = ["bench", "barbell squat", "manubri", "pull up", "pettorali", "cavi", "press", "lever", "curl", "femorali"]
    let started = Date()
    var produced = 0
    for _ in 0..<30 {
        for query in queries {
            produced += repository.search(ExerciseFilter(query: query), limit: 50).count
        }
    }
    let elapsed = Date().timeIntervalSince(started)
    h.check("300 ricerche su 1.324 esercizi in meno di 3s (\(String(format: "%.2f", elapsed))s)", elapsed < 3.0)
    h.check("le ricerche hanno prodotto risultati", produced > 0)

    return repository
}
