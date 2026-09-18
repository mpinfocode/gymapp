import Foundation
import GymCore

/// Check sulle correzioni del dataset (SPEC §2, punti 1-4): target corretti,
/// zone colpite "da palestra", ordinamento delle varianti ridondanti.
@MainActor
func runCorrectionChecks(_ h: Harness, repository: ExerciseRepository?) async {
    guard let repository else {
        h.section("correzioni")
        h.fail("repository non caricato")
        return
    }
    // Stesso JSON, senza lo strato di correzione: serve a misurare cosa cambia.
    guard let raw = try? await ExerciseRepository.loadFromBundle(applyingCorrections: false) else {
        h.section("correzioni")
        h.fail("dataset grezzo non caricato")
        return
    }
    let verbose = ProcessInfo.processInfo.environment["GYMCHECKS_VERBOSE"] == "1"

    // MARK: Conteggi complessivi

    h.section("correzioni · gambe")

    let upperLegs = repository.all.filter { $0.category == "upper legs" }
    let quads = upperLegs.filter { $0.target == "quads" }
    let hamstrings = upperLegs.filter { $0.target == "hamstrings" }
    let glutes = upperLegs.filter { $0.target == "glutes" }

    h.check("upper legs invariati (227)", upperLegs.count == 227)
    h.check("glutes scesi da 144 a 66 (ottenuto \(glutes.count))", glutes.count == 66)
    h.check("quads saliti da 44 a 111 (ottenuto \(quads.count))", quads.count == 111)
    h.check("hamstrings saliti da 28 a 39 (ottenuto \(hamstrings.count))", hamstrings.count == 39)
    h.check("totale gambe invariato", quads.count + hamstrings.count + glutes.count == 144 + 44 + 28)

    h.check("il JSON grezzo ha ancora 144 glutes",
            raw.all.filter { $0.target == "glutes" }.count == 144)
    h.check("correzione idempotente", ExerciseRepository(exercises: repository.all).all == repository.all)

    if verbose {
        for change in ExerciseCorrections.changes(in: raw.all) where change.newTarget == "quads" {
            print("   quads · \(change.exerciseID) \(change.name)")
        }
        for exercise in repository.all where exercise.category == "upper legs" && exercise.target == "glutes" {
            print("   glutes · \(exercise.id) \(exercise.name)")
        }
    }

    // MARK: Casi indicati dalla SPEC

    h.section("correzioni · casi puntuali")

    func target(_ id: String) -> String { repository.exercise(id: id)?.target ?? "?" }
    func secondaries(_ id: String) -> [String] { repository.exercise(id: id)?.secondaryMuscles ?? [] }

    // → quads
    for (id, name) in [
        ("0043", "barbell full squat"),
        ("0042", "barbell front squat"),
        ("0054", "barbell lunge"),
        ("0336", "dumbbell lunge"),
        ("0739", "sled 45 leg press"),
        ("0740", "sled 45 leg wide press"),
        ("0760", "smith leg press"),
        ("0114", "barbell step-up"),
        ("0743", "sled hack squat"),
        ("0534", "kettlebell goblet squat"),
        ("1460", "walking lunge"),
        ("0624", "march sit (wall)"),
    ] {
        h.check("\(name) → quads (ottenuto \(target(id)))", target(id) == "quads")
    }
    h.check("squat: glutes passa in testa ai secondari", secondaries("0043").first == "glutes")
    h.check("squat: quadriceps sparisce dai secondari", !secondaries("0043").contains("quadriceps"))
    h.check("squat: gli altri secondari restano", secondaries("0043").contains("hamstrings") && secondaries("0043").contains("calves"))

    // → hamstrings
    for (id, name) in [
        ("0085", "barbell romanian deadlift"),
        ("1459", "dumbbell romanian deadlift"),
        ("0432", "dumbbell stiff leg deadlift"),
        ("0434", "dumbbell straight leg deadlift"),
        ("1009", "band stiff leg deadlift"),
        ("0090", "barbell seated good morning"),
        ("3759", "lever seated good morning"),
        ("0749", "smith bent knee good morning"),
    ] {
        h.check("\(name) → hamstrings (ottenuto \(target(id)))", target(id) == "hamstrings")
    }
    h.check("stacco rumeno: glutes in testa ai secondari", secondaries("0085").first == "glutes")
    h.check("stacco rumeno: hamstrings non è più secondario", !secondaries("0085").contains("hamstrings"))

    // restano glutes
    for (id, name) in [
        ("3236", "resistance band hip thrusts"),
        ("1409", "barbell glute bridge"),
        ("3013", "low glute bridge on floor"),
        ("0032", "barbell deadlift"),
        ("0117", "barbell sumo deadlift"),
        ("0811", "trap bar deadlift"),
        ("0991", "band pull through"),
        ("0196", "cable pull through (with rope)"),
        ("0228", "cable standing hip extension"),
        ("0549", "kettlebell swing"),
        ("0551", "kettlebell turkish get up (squat style)"),
        ("3132", "potty squat with support"),
        ("3642", "weighted stretch lunge"),
        ("1424", "seated glute stretch"),
    ] {
        h.check("\(name) resta glutes (ottenuto \(target(id)))", target(id) == "glutes")
    }

    // MARK: Regole pure, senza repository

    h.section("correzioni · regole")

    h.check("regola: solo i glutes vengono toccati",
            ExerciseCorrections.correctedTarget(id: "x", name: "barbell squat", target: "quads") == nil)
    h.check("regola: squat → quads",
            ExerciseCorrections.correctedTarget(id: "x", name: "barbell squat", target: "glutes") == "quads")
    h.check("regola: gli stretch non si toccano",
            ExerciseCorrections.correctedTarget(id: "x", name: "squat stretch", target: "glutes") == nil)
    h.check("regola: good morning → hamstrings",
            ExerciseCorrections.correctedTarget(id: "x", name: "good morning", target: "glutes") == "hamstrings")
    h.check("regola: hip thrust non è toccato",
            ExerciseCorrections.correctedTarget(id: "x", name: "barbell hip thrust", target: "glutes") == nil)
    h.check("regola: le eccezioni per id vincono sul pattern",
            ExerciseCorrections.correctedTarget(id: "0551", name: "kettlebell turkish get up (squat style)", target: "glutes") == nil)
    h.check("regola: gli esercizi personalizzati non si correggono", {
        let custom = Exercise.custom(name: "barbell squat", category: "upper legs", target: "glutes")
        return ExerciseCorrections.corrected(custom).target == "glutes"
    }())

    let changes = ExerciseCorrections.changes(in: raw.all)
    h.check("78 correzioni in totale (ottenuto \(changes.count))", changes.count == 78)
    h.check("67 verso quads", changes.filter { $0.newTarget == "quads" }.count == 67)
    h.check("11 verso hamstrings", changes.filter { $0.newTarget == "hamstrings" }.count == 11)
    h.check("tutte partono da glutes", changes.allSatisfy { $0.previousTarget == "glutes" })
    h.check("tutte finiscono su quads o hamstrings", changes.allSatisfy { ["quads", "hamstrings"].contains($0.newTarget) })

    // MARK: Zone colpite

    h.section("correzioni · zone colpite")

    h.check("13 zone previste", MuscleGroup.allCases.count == 13)
    h.check("nomi italiani attesi", MuscleGroup.displayOrder.map(\.displayName) == [
        "Petto", "Dorso", "Spalle", "Bicipiti", "Tricipiti", "Avambracci",
        "Addome", "Quadricipiti", "Femorali", "Glutei", "Polpacci", "Cardio", "Altro",
    ])
    h.check("nessun trattino lungo nei nomi delle zone", MuscleGroup.allCases.allSatisfy {
        !$0.displayName.contains("\u{2014}") && !$0.displayName.contains("\u{2013}")
    })
    h.check("ogni target del dataset ha una zona", repository.allTargets.allSatisfy {
        MuscleGroup.targetGroups[$0] != nil
    })
    h.check("squat → Quadricipiti", repository.exercise(id: "0043")?.muscleGroupKind == .quads)
    h.check("stacco rumeno → Femorali", repository.exercise(id: "0085")?.muscleGroupKind == .hamstrings)
    h.check("hip thrust → Glutei", repository.exercise(id: "3236")?.muscleGroupKind == .glutes)
    h.check("panca piana → Petto", repository.exercise(id: "0025")?.muscleGroupKind == .chest)
    h.check("trazioni → Dorso", repository.exercise(id: "0652")?.muscleGroupKind == .back)
    h.check("scrollate → Dorso", repository.exercise(id: "0095")?.muscleGroupKind == .back)
    h.check("ripiego sulla categoria quando il target è ignoto",
            MuscleGroup.forTarget("muscolo inventato", category: "chest") == .chest)
    h.check("target e categoria ignoti → Altro",
            MuscleGroup.forTarget("boh", category: "boh") == .other)

    let groupCounts = Dictionary(grouping: repository.all, by: \.muscleGroupKind).mapValues(\.count)
    h.check("somma delle zone = libreria", groupCounts.values.reduce(0, +) == repository.count)
    h.check("Quadricipiti conta 111", groupCounts[.quads] == 111)
    h.check("Femorali conta 39", groupCounts[.hamstrings] == 39)
    h.check("Glutei conta 71 (66 upper legs + 5 abductors)", groupCounts[.glutes] == 71)

    // MARK: Facet "zona colpita"

    h.section("correzioni · facet zona colpita")

    let facets = repository.facets(for: ExerciseFilter())
    h.check("facet zone: somma = libreria", facets.muscleGroups.reduce(0) { $0 + $1.count } == repository.count)
    h.check("facet zone: etichette italiane", facets.muscleGroups.allSatisfy { $0.label == $0.group.displayName })
    h.check("facet zone: ordine anatomico stabile", facets.muscleGroups.map(\.group) == MuscleGroup.displayOrder.filter { group in
        facets.muscleGroups.contains { $0.group == group }
    })

    let onlyQuads = repository.search(ExerciseFilter(muscleGroups: [.quads]))
    h.check("filtro per zona", !onlyQuads.isEmpty && onlyQuads.allSatisfy { $0.muscleGroupKind == .quads })
    h.check("filtro per zona = conteggio del facet", onlyQuads.count == facets.muscleGroups.first { $0.group == .quads }?.count)
    let quadsAndChest = repository.search(ExerciseFilter(muscleGroups: [.quads, .chest]))
    h.check("più zone sono in OR", quadsAndChest.count == onlyQuads.count + repository.search(ExerciseFilter(muscleGroups: [.chest])).count)
    h.check("zona + attrezzo in AND", repository.search(ExerciseFilter(equipment: ["barbell"], muscleGroups: [.quads]))
        .allSatisfy { $0.equipment == "barbell" && $0.muscleGroupKind == .quads })

    var filter = ExerciseFilter()
    filter.toggleMuscleGroup(.glutes)
    h.check("toggle zona accende", filter.muscleGroups == [.glutes] && filter.activeFacetCount == 1)
    filter.toggleMuscleGroup(.glutes)
    h.check("toggle zona spegne", filter.muscleGroups.isEmpty && filter.isEmpty)

    // MARK: Varianti ridondanti

    h.section("correzioni · ordine delle varianti")

    func firstIndex(_ query: String, _ id: String) -> Int? {
        repository.search(ExerciseFilter(query: query)).firstIndex { $0.id == id }
    }

    for (query, base, variant, label) in [
        ("barbell rear lunge", "0078", "0077", "barbell rear lunge v. 2"),
        ("barbell full squat", "0043", "1461", "barbell full squat (back pov)"),
        ("barbell full squat", "0043", "1462", "barbell full squat (side pov)"),
        ("jump squat", "0514", "0513", "jump squat v. 2"),
        ("sled 45 leg press", "0739", "1463", "sled 45° leg press (side pov)"),
        ("glute bridge two legs on bench", "3523", "3562", "barbell glute bridge two legs on bench (male)"),
    ] {
        guard let basePosition = firstIndex(query, base), let variantPosition = firstIndex(query, variant) else {
            h.fail("\(label): base o variante assenti dai risultati di \"\(query)\"")
            continue
        }
        h.check("\"\(query)\": la base precede \(label)", basePosition < variantPosition)
    }

    h.check("riconosce v. 2", Exercise.isRedundantVariantName("barbell rear lunge v. 2"))
    h.check("riconosce v. 3", Exercise.isRedundantVariantName("barbell upright row v. 3"))
    h.check("riconosce (male)", Exercise.isRedundantVariantName("forward lunge (male)"))
    h.check("riconosce (female)", Exercise.isRedundantVariantName("resistance band hip thrusts on knees (female)"))
    h.check("riconosce (back pov)", Exercise.isRedundantVariantName("barbell full squat (back pov)"))
    h.check("riconosce (side pov)", Exercise.isRedundantVariantName("barbell full squat (side pov)"))
    h.check("non marca la variante base", !Exercise.isRedundantVariantName("barbell full squat"))
    h.check("non marca un nome con numeri legittimi", !Exercise.isRedundantVariantName("3/4 sit-up"))

    // La penalità deve essere solo un criterio di spareggio, non deve spostare
    // un risultato più pertinente sotto uno meno pertinente.
    let squats = repository.search(ExerciseFilter(query: "squat"), limit: 5)
    h.check("la penalità non stravolge la rilevanza", squats.allSatisfy { SearchText.normalize($0.name).contains("squat") })

    // MARK: muscle_group fuori dall'uso interno

    h.section("correzioni · muscle_group non usato")

    // `muscle_group` è la copia del primo secondario: se fosse ancora indicizzato,
    // toglierlo cambierebbe i risultati. Verifichiamo che i due insiemi coincidano.
    h.check("muscle_group è sempre il primo secondario del JSON",
            raw.all.allSatisfy { $0.muscleGroup == ($0.secondaryMuscles.first ?? "") })
    let byMuscleGroupOnly = raw.all.filter {
        !$0.muscleGroup.isEmpty
            && $0.muscleGroup != $0.target
            && !$0.secondaryMuscles.contains($0.muscleGroup)
    }
    h.check("nessun esercizio dipende solo da muscle_group", byMuscleGroupOnly.isEmpty)
    h.check("gli aggregati non guardano muscle_group",
            Stats.setsByMuscleGroup(in: [], exercisesByID: [:]).isEmpty)
}
