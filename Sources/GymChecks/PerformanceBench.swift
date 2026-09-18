import Foundation
import GymCore

/// Micro-benchmark informativo: **non** è un check e non può far fallire la suite.
///
/// I tempi dipendono dalla macchina, dal carico e dal fatto che qui si compila in
/// debug: servono a confrontare un prima e un dopo sullo **stesso** computer, non a
/// fissare una soglia. Su iPhone, in Release, i numeri sono di un altro ordine.
///
///     swift run -c release GymChecks
@MainActor
func runPerformanceBenchmark(repository: ExerciseRepository?) async {
    print("")
    print("— Benchmark informativo (non è un check) —")

    // 1. Caricamento + indicizzazione della libreria dal bundle.
    var loadSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        let loaded = try? await ExerciseRepository.loadFromBundle()
        loadSamples.append(milliseconds(since: start))
        if loaded == nil { print("  loadFromBundle: risorsa non disponibile"); return }
    }
    print("  loadFromBundle (decodifica + indicizzazione, \(loadSamples.count) giri): \(format(loadSamples)) ms")

    guard let repository else { return }

    // 2. Sola indicizzazione, partendo da record già decodificati.
    let records = repository.all
    var indexSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        _ = ExerciseRepository(exercises: records)
        indexSamples.append(milliseconds(since: start))
    }
    print("  indicizzazione di \(records.count) record (\(indexSamples.count) giri): \(format(indexSamples)) ms")

    // 2b. Solo l'ordinamento: vecchio metodo (normalizzazione dentro al comparatore,
    //     con il normalizzatore senza fast-path) contro decorate-sort-undecorate.
    var legacySortSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        _ = records.sorted { SearchText.normalizeReference($0.name) < SearchText.normalizeReference($1.name) }
        legacySortSamples.append(milliseconds(since: start))
    }
    print("  ordinamento, metodo precedente (\(legacySortSamples.count) giri): \(format(legacySortSamples)) ms")

    var newSortSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        var decorated = records.map { (key: SearchText.normalize($0.name), exercise: $0) }
        decorated.sort { $0.key < $1.key }
        _ = decorated.map(\.exercise)
        newSortSamples.append(milliseconds(since: start))
    }
    print("  ordinamento, decorate-sort-undecorate (\(newSortSamples.count) giri): \(format(newSortSamples)) ms")

    // 2c. Il normalizzatore da solo, sui campi che finiscono nell'indice.
    let texts = records.flatMap { [$0.name, $0.category, $0.equipment, $0.target] }
    var fastNormalize: [Double] = []
    var referenceNormalize: [Double] = []
    for _ in 0..<3 {
        var start = DispatchTime.now()
        for text in texts { _ = SearchText.normalize(text) }
        fastNormalize.append(milliseconds(since: start))
        start = DispatchTime.now()
        for text in texts { _ = SearchText.normalizeReference(text) }
        referenceNormalize.append(milliseconds(since: start))
    }
    print("  \(texts.count) normalizzazioni, fast-path ASCII: \(format(fastNormalize)) ms")
    print("  \(texts.count) normalizzazioni, percorso precedente: \(format(referenceNormalize)) ms")

    // 3. Cento ricerche con query italiane realistiche.
    let queries = [
        "panca piana", "trazioni", "alzate laterali manubri", "squat", "stacco da terra",
        "curl bicipiti", "french press", "leg press", "addominali", "affondi",
    ]
    var searchSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        for round in 0..<100 {
            _ = repository.search(ExerciseFilter(query: queries[round % queries.count]), limit: 50)
        }
        searchSamples.append(milliseconds(since: start))
    }
    print("  100 ricerche (\(searchSamples.count) giri): \(format(searchSamples)) ms")

    // 4. Aggiunta di un esercizio personalizzato: indice separato vs fusione completa.
    let customs = (0..<3).map { Exercise.custom(name: "Personalizzato \($0)", category: "chest", target: "pectorals") }
    var splitSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        _ = ExerciseLibraryIndex(library: repository, custom: ExerciseRepository(exercises: customs))
        splitSamples.append(milliseconds(since: start))
    }
    print("  indice separato dei personalizzati (\(splitSamples.count) giri): \(format(splitSamples)) ms")

    var mergeSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        _ = ExerciseRepository(exercises: repository.all + customs)
        mergeSamples.append(milliseconds(since: start))
    }
    print("  vecchia fusione in un indice unico (\(mergeSamples.count) giri): \(format(mergeSamples)) ms")

    // 4b. La proprietà di compatibilità `searchableLibrary`: fusione a freddo di due
    //     indici già costruiti (copia, nessuna rinormalizzazione).
    var compatSamples: [Double] = []
    for _ in 0..<3 {
        let directory = TempDirectory.make()
        defer { TempDirectory.remove(directory) }
        let store = AppStore(store: JSONFileStore(directory: directory), exercises: repository)
        await store.load()
        for custom in customs { store.createCustomExercise(name: custom.name, category: custom.category) }
        let start = DispatchTime.now()
        _ = store.searchableLibrary
        compatSamples.append(milliseconds(since: start))
    }
    print("  searchableLibrary a freddo, fusione di due indici pronti (\(compatSamples.count) giri): \(format(compatSamples)) ms")

    // 5. Presentazione: pre-calcolata vs ricostruita a ogni riga.
    let visible = Array(repository.all.prefix(60)) // una schermata abbondante di righe
    let ids = visible.map(\.id)
    var cachedSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        for _ in 0..<100 { for id in ids { _ = repository.presentation(for: id) } }
        cachedSamples.append(milliseconds(since: start))
    }
    print("  100 ridisegni di 60 righe, presentazione pre-calcolata: \(format(cachedSamples)) ms")

    var computedSamples: [Double] = []
    for _ in 0..<3 {
        let start = DispatchTime.now()
        for _ in 0..<100 {
            for exercise in visible {
                _ = exercise.shortDisplayName
                _ = ExercisePresentation.subtitle(for: exercise)
            }
        }
        computedSamples.append(milliseconds(since: start))
    }
    print("  100 ridisegni di 60 righe, presentazione ricalcolata: \(format(computedSamples)) ms")
    print("")
}

private func milliseconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}

/// "min 1,23 · mediana 1,31" con due decimali, senza dipendere dal locale.
private func format(_ samples: [Double]) -> String {
    guard !samples.isEmpty else { return "n/d" }
    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]
    return "min \(rounded(sorted[0])) · mediana \(rounded(median))"
}

private func rounded(_ value: Double) -> String {
    String(format: "%.2f", value)
}
