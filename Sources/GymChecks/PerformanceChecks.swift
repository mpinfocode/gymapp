import Foundation
import Observation
import GymCore

/// Contenitore mutabile condivisibile con una closure `@Sendable`
/// (`withObservationTracking(_:onChange:)` vuole una closure Sendable).
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}

/// Check delle correzioni prestazionali di GymCore.
///
/// Verificano **invarianza** (ordinamento, risultati di ricerca, facet, formato del
/// file delle impostazioni) e **granularità** dell'osservazione: sono i due modi in
/// cui un'ottimizzazione può rompere l'app senza che si veda subito.
@MainActor
func runPerformanceChecks(_ h: Harness, repository: ExerciseRepository?) async {
    guard let repository else {
        h.fail("prestazioni: libreria non disponibile")
        return
    }

    normalizationChecks(h, repository: repository)
    orderingChecks(h, repository: repository)
    await customIndexChecks(h, repository: repository)
    await observationChecks(h, repository: repository)
    await settingsFormatChecks(h, repository: repository)
    presentationChecks(h, repository: repository)
}

// MARK: - 3. Normalizzatore

/// Il fast-path ASCII deve dare **esattamente** lo stesso risultato del percorso
/// Unicode completo: se divergesse, cambierebbero indicizzazione e ricerca.
@MainActor
private func normalizationChecks(_ h: Harness, repository: ExerciseRepository) {
    h.section("prestazioni · normalizzazione")

    var divergences: [String] = []
    for exercise in repository.all {
        for text in [exercise.name, exercise.category, exercise.equipment, exercise.target] {
            if SearchText.normalize(text) != SearchText.normalizeReference(text) {
                divergences.append(text)
            }
        }
    }
    h.check("fast-path ASCII identico al riferimento su tutto il dataset (\(divergences.count) divergenze)",
            divergences.isEmpty)

    let tricky = [
        "", "   ", "Pull-Up (wide grip)", "3/4 sit-up", "V. 2", "ABC123",
        "Flessori dell'anca", "Trazioni alla sbarra", "Curl bicipiti · manubri",
        "Pettorali—alti", "Caffè", "Ångström", "ＦＵＬＬＷＩＤＴＨ", "naïve café",
        "émile   zola", "----", "a-b_c", "  bordi  ",
    ]
    var trickyDivergences: [String] = []
    for text in tricky where SearchText.normalize(text) != SearchText.normalizeReference(text) {
        trickyDivergences.append(text)
    }
    h.check("fast-path identico al riferimento sui casi limite (\(trickyDivergences))", trickyDivergences.isEmpty)

    h.check("normalizzazione invariata: punteggiatura", SearchText.normalize("Pull-Up (wide grip)") == "pull up wide grip")
    h.check("normalizzazione invariata: apostrofo", SearchText.normalize("Flessori dell'anca") == "flessori dell anca")
    h.check("normalizzazione invariata: accenti", SearchText.normalize("Caffè") == "caffe")
    h.check("normalizzazione invariata: stringa vuota", SearchText.normalize("") == "")
    h.check("normalizzazione invariata: solo separatori", SearchText.normalize(" --- ") == "")
}

// MARK: - 3. Ordinamento della libreria

/// L'ordinamento decorate-sort-undecorate deve produrre la stessa sequenza di
/// chiavi del vecchio `sorted { normalize($0.name) < normalize($1.name) }`.
@MainActor
private func orderingChecks(_ h: Harness, repository: ExerciseRepository) {
    h.section("prestazioni · ordinamento libreria")

    let keys = repository.all.map { SearchText.normalize($0.name) }
    h.check("chiavi non decrescenti", zip(keys, keys.dropFirst()).allSatisfy { $0 <= $1 })
    h.check("sequenza di chiavi identica all'ordinamento di riferimento", keys == keys.sorted())
    h.check("nessun record perso", Set(repository.all.map(\.id)).count == repository.count)
    h.check("libreria da 1.324 record", repository.count == 1_324)

    // Ricostruendo l'indice da un input mescolato si deve riottenere lo stesso ordine.
    var shuffled = repository.all
    shuffled.shuffle()
    let rebuilt = ExerciseRepository(exercises: shuffled)
    h.check("ordine indipendente dall'ordine di input",
            rebuilt.all.map { SearchText.normalize($0.name) } == keys)
}

// MARK: - 2. Indice separato dei personalizzati

/// L'indice base + indice dei personalizzati deve dare **gli stessi risultati e gli
/// stessi facet** della vecchia fusione in un unico repository.
@MainActor
private func customIndexChecks(_ h: Harness, repository: ExerciseRepository) async {
    h.section("prestazioni · indice dei personalizzati")

    let customs = [
        Exercise.custom(name: "Face pull", category: "shoulders", equipment: "cable", target: "rear deltoids"),
        Exercise.custom(name: "Bulgarian split squat", category: "upper legs", equipment: "dumbbell", target: "quads"),
        Exercise.custom(name: "Barbell bench press", category: "chest", equipment: "barbell", target: "pectorals"),
        Exercise.custom(name: "Zercher squat", category: "upper legs", equipment: "barbell", target: "glutes"),
    ]

    // Vecchia strada: un unico indice ricostruito da zero.
    let legacy = ExerciseRepository(exercises: repository.all + customs)
    // Nuova strada: indice base immutabile + piccolo indice separato.
    let index = ExerciseLibraryIndex(library: repository, custom: ExerciseRepository(exercises: customs))

    h.check("stesso numero di esercizi", index.count == legacy.count)

    let favorites: Set<String> = [customs[0].id, "0025", "0652"]
    let queries: [ExerciseFilter] = [
        .empty,
        ExerciseFilter(query: "face pull"),
        ExerciseFilter(query: "squat"),
        ExerciseFilter(query: "panca piana"),
        ExerciseFilter(query: "bench press"),
        ExerciseFilter(query: "split"),
        ExerciseFilter(query: "zercher"),
        ExerciseFilter(query: "trazioni"),
        ExerciseFilter(query: "alzate laterali manubri"),
        ExerciseFilter(query: "curl"),
        ExerciseFilter(categories: ["chest"]),
        ExerciseFilter(equipment: ["cable"]),
        ExerciseFilter(query: "squat", muscleGroups: [.quads]),
        ExerciseFilter(favoritesOnly: true),
        ExerciseFilter(query: "press", favoritesOnly: true),
    ]

    var searchDivergences: [String] = []
    var facetDivergences: [String] = []
    for filter in queries {
        let old = legacy.search(filter, favorites: favorites).map(\.id)
        let new = index.search(filter, favorites: favorites).map(\.id)
        if old != new { searchDivergences.append("\"\(filter.query)\"") }

        if legacy.facets(for: filter, favorites: favorites) != index.facets(for: filter, favorites: favorites) {
            facetDivergences.append("\"\(filter.query)\"")
        }
    }
    h.check("ricerca identica alla vecchia fusione (\(searchDivergences))", searchDivergences.isEmpty)
    h.check("facet identici alla vecchia fusione (\(facetDivergences))", facetDivergences.isEmpty)

    var limitDivergences = 0
    for filter in queries where legacy.search(filter, favorites: favorites, limit: 20).map(\.id)
        != index.search(filter, favorites: favorites, limit: 20).map(\.id) {
        limitDivergences += 1
    }
    h.check("ricerca con limite identica (\(limitDivergences) divergenze)", limitDivergences == 0)

    // Lo store deve dare le stesse cose sia dall'indice nuovo sia dalla proprietà
    // di compatibilità `searchableLibrary` (che ora fonde due indici già costruiti).
    let directory = TempDirectory.make()
    defer { TempDirectory.remove(directory) }
    let store = AppStore(
        store: JSONFileStore(directory: directory),
        exercises: repository,
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(20),
        now: TestClock(Fixtures.date(2025, 3, 3)).provider
    )
    await store.load()
    for custom in customs {
        store.createCustomExercise(
            name: custom.name,
            category: custom.category,
            equipment: custom.equipment,
            target: custom.target
        )
    }

    h.check("searchableLibrary conta libreria + personalizzati", store.searchableLibrary?.count == 1_328)
    h.check("exerciseIndex conta libreria + personalizzati", store.exerciseIndex?.count == 1_328)

    var compatDivergences: [String] = []
    for filter in queries {
        let compat = store.searchableLibrary?.search(filter, favorites: store.favoriteExerciseIDs).map(\.id) ?? []
        let granular = store.searchExercises(filter).map(\.id)
        if compat != granular { compatDivergences.append("\"\(filter.query)\"") }
    }
    h.check("searchableLibrary e searchExercises coincidono (\(compatDivergences))", compatDivergences.isEmpty)
    h.check("facet dallo store coincidono con searchableLibrary",
            store.exerciseFacets(for: .empty) == store.searchableLibrary?.facets(for: .empty, favorites: []))

    // Un personalizzato eliminato sparisce da ricerca e facet ma resta risolvibile.
    guard let first = store.availableCustomExercises.first(where: { $0.name == "Zercher squat" }) else {
        h.fail("personalizzato di prova non trovato")
        return
    }
    let before = store.exerciseIndex?.count ?? 0
    let outcome = store.deleteCustomExercise(id: first.id)
    h.check("non essendo usato viene rimosso davvero", outcome == .removed)
    h.check("eliminando un personalizzato l'indice si accorcia", store.exerciseIndex?.count == before - 1)
    h.check("non compare più nella ricerca",
            !store.searchExercises(ExerciseFilter(query: "zercher")).contains { $0.id == first.id })

    // Un personalizzato citato dalla scheda viene invece archiviato: sparisce
    // dall'indice ma il lookup per id deve continuare a risolverlo (storico).
    guard let used = store.availableCustomExercises.first(where: { $0.name == "Face pull" }) else {
        h.fail("personalizzato di prova non trovato")
        return
    }
    let program = store.createProgram(name: "Prova indice")
    let day = store.addDay(name: "A", toProgram: program.id)
    store.addItem(exerciseID: used.id, toDay: day.id, inProgram: program.id)
    h.check("personalizzato usato: soft delete", store.deleteCustomExercise(id: used.id) == .archived)
    h.check("resta risolvibile per id", store.exercise(id: used.id) != nil)
    h.check("sparisce dall'indice consultabile", store.exerciseIndex?.exercise(id: used.id) == nil)
    h.check("sparisce dalla ricerca",
            !store.searchExercises(ExerciseFilter(query: "face pull")).contains { $0.id == used.id })
    h.check("la presentazione resta disponibile per lo storico",
            store.exercisePresentation(id: used.id)?.title == "Face Pull")

    // Snapshot Sendable usabile fuori dal main actor (punto 6).
    guard let snapshot = store.exerciseSearchSnapshot() else {
        h.fail("snapshot di ricerca non disponibile")
        return
    }
    let filter = ExerciseFilter(query: "panca piana")
    let expected = store.searchExercises(filter, limit: 10).map(\.id)
    let offMain = await Task.detached(priority: .userInitiated) {
        snapshot.search(filter, limit: 10).map(\.id)
    }.value
    h.check("lo snapshot dà gli stessi risultati fuori dal main actor", offMain == expected)

    let expectedFacets = store.exerciseFacets(for: filter)
    let offMainFacets = await Task.detached(priority: .userInitiated) { snapshot.facets(for: filter) }.value
    h.check("lo snapshot dà gli stessi facet fuori dal main actor", offMainFacets == expectedFacets)
}

// MARK: - 1. Granularità dell'osservazione

@MainActor
private func observationChecks(_ h: Harness, repository: ExerciseRepository) async {
    h.section("prestazioni · granularità dell'osservazione")

    let directory = TempDirectory.make()
    defer { TempDirectory.remove(directory) }
    let store = AppStore(
        store: JSONFileStore(directory: directory),
        exercises: repository,
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(20),
        now: TestClock(Fixtures.date(2025, 3, 3)).provider
    )
    await store.load()
    store.markRecent("0001")

    // Scrivere i recenti (ogni apertura di un esercizio) non deve toccare nessuno.
    let favoritesFlag = Flag()
    withObservationTracking { _ = store.favoriteExerciseIDs } onChange: { favoritesFlag.set() }
    let hapticsFlag = Flag()
    withObservationTracking { _ = store.hapticsEnabled } onChange: { hapticsFlag.set() }
    let searchFlag = Flag()
    withObservationTracking { _ = store.searchExercises(.empty, limit: 5) } onChange: { searchFlag.set() }
    let facetsFlag = Flag()
    withObservationTracking { _ = store.exerciseFacets(for: .empty) } onChange: { facetsFlag.set() }
    let unitFlag = Flag()
    withObservationTracking { _ = store.unit } onChange: { unitFlag.set() }
    let settingsFlag = Flag()
    withObservationTracking { _ = store.settings } onChange: { settingsFlag.set() }
    let recentsFlag = Flag()
    withObservationTracking { _ = store.recentExerciseIDs } onChange: { recentsFlag.set() }

    store.markRecent("0025")

    h.check("i recenti NON invalidano i preferiti", !favoritesFlag.isSet)
    h.check("i recenti NON invalidano le vibrazioni", !hapticsFlag.isSet)
    h.check("i recenti NON invalidano la ricerca", !searchFlag.isSet)
    h.check("i recenti NON invalidano i facet", !facetsFlag.isSet)
    h.check("i recenti NON invalidano l'unità di misura", !unitFlag.isSet)
    h.check("i recenti invalidano chi legge i recenti", recentsFlag.isSet)
    h.check("i recenti invalidano chi legge settings (dipendenza larga, documentata)", settingsFlag.isSet)

    // Un preferito invalida ricerca e facet (che li leggono) ma non le vibrazioni.
    let hapticsFlag2 = Flag()
    withObservationTracking { _ = store.hapticsEnabled } onChange: { hapticsFlag2.set() }
    let recentsFlag2 = Flag()
    withObservationTracking { _ = store.recentExerciseIDs } onChange: { recentsFlag2.set() }
    let searchFlag2 = Flag()
    withObservationTracking { _ = store.searchExercises(.empty, limit: 5) } onChange: { searchFlag2.set() }

    store.toggleFavorite("0025")

    h.check("i preferiti NON invalidano le vibrazioni", !hapticsFlag2.isSet)
    h.check("i preferiti NON invalidano i recenti", !recentsFlag2.isSet)
    h.check("i preferiti invalidano la ricerca", searchFlag2.isSet)

    // Le vibrazioni (shell dell'app) non toccano ricerca e preferiti.
    let searchFlag3 = Flag()
    withObservationTracking { _ = store.searchExercises(.empty, limit: 5) } onChange: { searchFlag3.set() }
    let favoritesFlag3 = Flag()
    withObservationTracking { _ = store.favoriteExerciseIDs } onChange: { favoritesFlag3.set() }

    store.updateSettings { $0.hapticsEnabled = false }

    h.check("le vibrazioni NON invalidano la ricerca", !searchFlag3.isSet)
    h.check("le vibrazioni NON invalidano i preferiti", !favoritesFlag3.isSet)
    h.check("updateSettings scrive davvero", !store.hapticsEnabled)

    // markRecent è un no-op se l'id è già in testa.
    store.markRecent("0100")
    let noopFlag = Flag()
    withObservationTracking { _ = store.recentExerciseIDs } onChange: { noopFlag.set() }
    let recentsBefore = store.recentExerciseIDs
    store.markRecent("0100")
    h.check("markRecent con id già in testa è un no-op", !noopFlag.isSet)
    h.check("markRecent no-op non cambia i recenti", store.recentExerciseIDs == recentsBefore)
    h.check("markRecent con id diverso sposta in testa", { store.markRecent("0200"); return store.recentExerciseIDs.first == "0200" }())
    h.check("i recenti restano deduplicati", Set(store.recentExerciseIDs).count == store.recentExerciseIDs.count)

    // Il cambio dei personalizzati invalida chi consulta libreria e lookup.
    let indexFlag = Flag()
    withObservationTracking { _ = store.exerciseIndex } onChange: { indexFlag.set() }
    let lookupFlag = Flag()
    withObservationTracking { _ = store.exercise(id: "0025") } onChange: { lookupFlag.set() }
    store.createCustomExercise(name: "Pallof press", category: "waist", target: "abs")
    h.check("un personalizzato nuovo invalida l'indice", indexFlag.isSet)
    h.check("un personalizzato nuovo invalida il lookup per id", lookupFlag.isSet)
}

// MARK: - 1. Formato del file delle impostazioni

/// ``UserSettings`` resta il DTO di serializzazione: il file su disco non cambia.
@MainActor
private func settingsFormatChecks(_ h: Harness, repository: ExerciseRepository) async {
    h.section("prestazioni · formato delle impostazioni")

    let directory = TempDirectory.make()
    defer { TempDirectory.remove(directory) }
    let fileStore = JSONFileStore(directory: directory)
    let store = AppStore(
        store: fileStore,
        exercises: repository,
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(20),
        now: TestClock(Fixtures.date(2025, 3, 3)).provider
    )
    await store.load()

    let program = store.createProgram(name: "Prova")
    store.updateSettings { $0.unit = .lb; $0.displayName = "Fra"; $0.defaultRestSeconds = 120 }
    store.toggleFavorite("0025")
    store.markRecent("0652")
    await store.flush()

    let url = await fileStore.url(for: .settings)
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        h.fail("file delle impostazioni illeggibile")
        return
    }

    let expectedKeys: Set<String> = [
        "displayName", "activeProgramID", "unit", "defaultRestSeconds",
        "favoriteExerciseIDs", "recentExerciseIDs", "hapticsEnabled",
    ]
    h.check("chiavi del file invariate (\(Set(json.keys).sorted()))", Set(json.keys) == expectedKeys)
    h.check("displayName sul disco", json["displayName"] as? String == "Fra")
    h.check("unit sul disco", json["unit"] as? String == "lb")
    h.check("defaultRestSeconds sul disco", json["defaultRestSeconds"] as? Int == 120)
    h.check("hapticsEnabled sul disco", json["hapticsEnabled"] as? Bool == true)
    h.check("preferiti sul disco", (json["favoriteExerciseIDs"] as? [String]) == ["0025"])
    h.check("recenti sul disco", (json["recentExerciseIDs"] as? [String]) == ["0652"])
    h.check("scheda attiva sul disco", json["activeProgramID"] as? String == program.id.uuidString)

    // Round-trip: quello che si rilegge è esattamente quello che c'era.
    let reloaded = AppStore(
        store: JSONFileStore(directory: directory),
        exercises: repository,
        calendar: Fixtures.calendar,
        now: TestClock(Fixtures.date(2025, 3, 3)).provider
    )
    await reloaded.load()
    h.check("round-trip del DTO", reloaded.settings == store.settings)
    h.check("round-trip: proprietà granulari", reloaded.unit == .lb
            && reloaded.displayName == "Fra"
            && reloaded.defaultRestSeconds == 120
            && reloaded.favoriteExerciseIDs == ["0025"]
            && reloaded.recentExerciseIDs == ["0652"]
            && reloaded.hapticsEnabled
            && reloaded.activeProgramID == program.id)

    // Un file scritto da una versione precedente resta leggibile.
    let legacy = """
    {"displayName":"Vecchio","unit":"kg","defaultRestSeconds":75,\
    "favoriteExerciseIDs":["0001"],"recentExerciseIDs":["0002"],"hapticsEnabled":false}
    """
    try? Data(legacy.utf8).write(to: url)
    let fromLegacy = AppStore(
        store: JSONFileStore(directory: directory),
        exercises: repository,
        calendar: Fixtures.calendar,
        now: TestClock(Fixtures.date(2025, 3, 3)).provider
    )
    await fromLegacy.load()
    h.check("file di una versione precedente ancora leggibile",
            fromLegacy.displayName == "Vecchio" && fromLegacy.defaultRestSeconds == 75
                && !fromLegacy.hapticsEnabled && fromLegacy.activeProgramID == nil)
}

// MARK: - 5. Presentazione pre-calcolata

@MainActor
private func presentationChecks(_ h: Harness, repository: ExerciseRepository) {
    h.section("prestazioni · presentazione pre-calcolata")

    guard let bench = repository.exercise(id: "0025"),
          let presentation = repository.presentation(for: "0025") else {
        h.fail("presentazione dell'esercizio 0025 mancante")
        return
    }

    h.check("titolo = shortDisplayName", presentation.title == bench.shortDisplayName)
    h.check("sottoriga muscolo · attrezzo", presentation.subtitle == "Pettorali · Bilanciere")
    h.check("id coerente", presentation.id == bench.id)

    var divergences = 0
    for exercise in repository.all {
        guard let value = repository.presentation(for: exercise.id) else { divergences += 1; continue }
        if value.title != exercise.shortDisplayName { divergences += 1 }
        if value.subtitle != ExercisePresentation.subtitle(for: exercise) { divergences += 1 }
    }
    h.check("presentazione coerente su tutto il dataset (\(divergences) divergenze)", divergences == 0)
    h.check("id sconosciuto → nil", repository.presentation(for: "non-esiste") == nil)

    let custom = Exercise.custom(name: "Face pull", equipment: "cable", target: "rear deltoids")
    let customPresentation = ExercisePresentation(exercise: custom)
    h.check("i personalizzati non perdono il nome", customPresentation.title == "Face Pull")
    h.check("nessun trattino lungo nelle sottorighe",
            repository.all.allSatisfy { repository.presentation(for: $0.id)?.subtitle.contains("—") == false })
}
