import Foundation
import GymCore

@MainActor
func runModelChecks(_ h: Harness) {

    // MARK: Decodifica tollerante

    h.section("modelli · decodifica tollerante")

    let decoder = JSONDecoder()

    if let minimal = try? decoder.decode(Exercise.self, from: Data(#"{"id":"9999","name":"test move"}"#.utf8)) {
        h.check("Exercise minimale: id", minimal.id == "9999")
        h.check("Exercise minimale: name", minimal.name == "test move")
        h.check("Exercise minimale: campi assenti → default", minimal.category.isEmpty && minimal.equipment.isEmpty && minimal.secondaryMuscles.isEmpty)
        h.check("Exercise minimale: steps vuoti", minimal.steps.isEmpty)
        h.check("Exercise minimale: attribuzione di default", minimal.attribution == Exercise.defaultAttribution)
        h.check("Exercise minimale: nessun URL media", minimal.imageURL == nil && minimal.gifURL == nil)
    } else {
        h.fail("Exercise minimale non decodificato")
    }

    if let nullFields = try? decoder.decode(Exercise.self, from: Data(#"{"id":"1","name":"x","category":null,"secondary_muscles":null,"instruction_steps":null}"#.utf8)) {
        h.check("Exercise con null espliciti → default", nullFields.category.isEmpty && nullFields.secondaryMuscles.isEmpty && nullFields.steps.isEmpty)
    } else {
        h.fail("Exercise con null non decodificato")
    }

    h.check("Exercise senza id → errore", (try? decoder.decode(Exercise.self, from: Data(#"{"name":"x"}"#.utf8))) == nil)

    // body_part assente ricade sulla categoria
    if let noBodyPart = try? decoder.decode(Exercise.self, from: Data(#"{"id":"1","name":"x","category":"chest"}"#.utf8)) {
        h.check("Exercise senza body_part → usa category", noBodyPart.bodyPart == "chest")
    } else {
        h.fail("Exercise senza body_part non decodificato")
    }

    // MARK: Istruzioni italiane con fallback inglese

    h.section("modelli · istruzioni (solo italiano)")

    let bothLanguages = #"{"id":"1","name":"x","instruction_steps":{"it":["Passo uno"],"en":["Step one"]}}"#
    if let exercise = try? decoder.decode(Exercise.self, from: Data(bothLanguages.utf8)) {
        h.check("steps usa l'italiano quando c'è", exercise.steps == ["Passo uno"])
    } else {
        h.fail("decodifica it+en fallita")
    }

    let onlyEnglish = #"{"id":"1","name":"x","instruction_steps":{"en":["Step one","Step two"]}}"#
    if let exercise = try? decoder.decode(Exercise.self, from: Data(onlyEnglish.utf8)) {
        h.check("steps ricade su en se manca it", exercise.steps == ["Step one", "Step two"])
    } else {
        h.fail("decodifica solo-en fallita")
    }

    let emptyItalian = #"{"id":"1","name":"x","instruction_steps":{"it":[],"en":["Step one"]}}"#
    if let exercise = try? decoder.decode(Exercise.self, from: Data(emptyItalian.utf8)) {
        h.check("steps ricade su en se it è vuoto", exercise.steps == ["Step one"])
    } else {
        h.fail("decodifica it vuoto fallita")
    }

    // MARK: Helper di presentazione

    h.section("modelli · presentazione")

    let sample = Exercise(
        id: "0025",
        name: "barbell bench press",
        category: "chest",
        equipment: "barbell",
        target: "pectorals",
        imagePath: "images/0025-abc.jpg",
        gifPath: "videos/0025-abc.gif"
    )
    h.check("displayName capitalizza ogni parola", sample.displayName == "Barbell Bench Press")
    h.check(
        "displayName non altera il resto della parola",
        Exercise(id: "1", name: "3/4 sit-up").displayName == "3/4 Sit-up"
    )
    h.check(
        "imageURL sul repository del dataset",
        sample.imageURL?.absoluteString == "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/images/0025-abc.jpg"
    )
    h.check(
        "gifURL sul repository del dataset",
        sample.gifURL?.absoluteString == "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/videos/0025-abc.gif"
    )
    h.check("traduzioni sull'esercizio", sample.localizedCategory == "Petto" && sample.localizedEquipment == "Bilanciere" && sample.localizedTarget == "Pettorali")

    // Round-trip Codable
    if let data = try? JSONEncoder().encode(sample),
       let restored = try? JSONDecoder().decode(Exercise.self, from: data) {
        h.check("Exercise round-trip Codable", restored == sample)
    } else {
        h.fail("Exercise round-trip fallito")
    }

    // MARK: Weekday

    h.section("modelli · Weekday")

    h.check("7 giorni", Weekday.allCases.count == 7)
    h.check("lunedì è il primo", Weekday.allCases.first == .monday)
    h.check("domenica è l'ultima", Weekday.allCases.last == .sunday)
    h.check("ordine 1…7", Weekday.allCases.map(\.order) == Array(1...7))
    h.check("nomi italiani", Weekday.allCases.map(\.italianName) == ["lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica"])
    h.check("displayName maiuscolo", Weekday.monday.displayName == "Lunedì" && Weekday.sunday.displayName == "Domenica")
    h.check("abbreviazioni", Weekday.allCases.map(\.shortName) == ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"])
    h.check("iniziali L-D", Weekday.allCases.map(\.letter) == ["L", "M", "M", "G", "V", "S", "D"])
    h.check("indice Calendar: domenica = 1", Weekday.sunday.calendarWeekday == 1)
    h.check("indice Calendar: lunedì = 2", Weekday.monday.calendarWeekday == 2)
    h.check("indice Calendar: sabato = 7", Weekday.saturday.calendarWeekday == 7)
    h.check("from(calendarWeekday:) inverte", Weekday.allCases.allSatisfy { Weekday.from(calendarWeekday: $0.calendarWeekday) == $0 })
    h.check("from(calendarWeekday:) fuori range → nil", Weekday.from(calendarWeekday: 9) == nil)
    // 2025-01-06 è un lunedì, 2025-01-12 una domenica
    h.check("from(date:) lunedì", Weekday.from(date: Fixtures.date(2025, 1, 6), calendar: Fixtures.calendar) == .monday)
    h.check("from(date:) domenica", Weekday.from(date: Fixtures.date(2025, 1, 12), calendar: Fixtures.calendar) == .sunday)
    h.check("ordinamento Comparable", Weekday.monday < Weekday.sunday)

    // MARK: Unità di misura

    h.section("modelli · WeightUnit")

    h.checkClose("100 kg → lb", WeightUnit.lb.value(fromKilograms: 100), 220.462_262, tolerance: 0.000_1)
    h.checkClose("225 lb → kg", WeightUnit.lb.kilograms(from: 225), 102.058_282_65, tolerance: 0.000_1)
    h.checkClose("kg è identità", WeightUnit.kg.value(fromKilograms: 82.5), 82.5)
    h.checkClose(
        "round-trip kg → lb → kg",
        WeightUnit.lb.kilograms(from: WeightUnit.lb.value(fromKilograms: 137.3)),
        137.3,
        tolerance: 0.000_001
    )
    h.check("format kg intero senza decimali", WeightUnit.kg.format(kilograms: 100) == "100 kg")
    h.check("format kg con mezzo disco (virgola italiana)", WeightUnit.kg.format(kilograms: 82.5) == "82,5 kg")
    h.check("format senza simbolo", WeightUnit.kg.format(kilograms: 82.5, includeSymbol: false) == "82,5")
    h.check("format lb", WeightUnit.lb.format(kilograms: 100, fractionDigits: 1) == "220,5 lb")
    h.check("format arrotonda a 0 decimali", WeightUnit.kg.format(kilograms: 82.4, fractionDigits: 0) == "82 kg")
    h.check("trimmedNumber toglie gli zeri", WeightUnit.trimmedNumber(12.50) == "12.5" && WeightUnit.trimmedNumber(12.0) == "12")
    h.check("trimmedNumber evita -0", WeightUnit.trimmedNumber(-0.001) == "0")
    h.check("simboli", WeightUnit.kg.symbol == "kg" && WeightUnit.lb.symbol == "lb")

    // MARK: Serie e sessioni

    h.section("modelli · serie e sessioni")

    h.check("warmup non conta per il volume", !SetKind.warmup.countsTowardVolume)
    h.check("normal/drop/failure contano", [SetKind.normal, .drop, .failure].allSatisfy(\.countsTowardVolume))

    let completedAt = Date()
    let normalSet = SetLog(kind: .normal, weightKg: 80, reps: 8, completedAt: completedAt)
    h.checkClose("volume serie = kg × reps", normalSet.volumeKg, 640)
    h.check("serie completata è di lavoro", normalSet.isWorkingSet)

    h.checkClose("serie non completata → volume 0", SetLog(kind: .normal, weightKg: 80, reps: 8).volumeKg, 0)
    h.checkClose("warmup → volume 0", SetLog(kind: .warmup, weightKg: 40, reps: 10, completedAt: completedAt).volumeKg, 0)
    h.checkClose("senza carico → volume 0", SetLog(kind: .normal, reps: 10, completedAt: completedAt).volumeKg, 0)
    h.check("senza reps non è serie di lavoro", !SetLog(kind: .normal, weightKg: 80, completedAt: completedAt).isWorkingSet)

    let entry = SessionEntry(
        exerciseID: "0025",
        sets: [
            SetLog(kind: .warmup, weightKg: 40, reps: 10, completedAt: completedAt),
            SetLog(kind: .normal, weightKg: 80, reps: 8, completedAt: completedAt),
            SetLog(kind: .normal, weightKg: 80, reps: 6, completedAt: completedAt),
            SetLog(kind: .normal, weightKg: 80, reps: 6),
        ]
    )
    h.checkClose("volume esercizio esclude warmup e serie aperte", entry.volumeKg, 80 * 8 + 80 * 6)
    h.check("serie completate contate", entry.completedSets == 3)
    h.check("serie di lavoro escludono warmup", entry.workingSets.count == 2)

    let start = Fixtures.date(2025, 3, 10, 18, 0)
    var session = WorkoutSession(name: "Push", startedAt: start, entries: [entry])
    h.check("sessione senza fine è attiva", session.isActive)
    h.checkClose("durata di una sessione aperta è 0", session.duration, 0)
    h.checkClose("elapsed misura dal via", session.elapsed(asOf: start.addingTimeInterval(1_800)), 1_800)
    session.endedAt = start.addingTimeInterval(3_600)
    h.check("sessione chiusa non è attiva", !session.isActive)
    h.checkClose("durata sessione chiusa", session.duration, 3_600)
    h.checkClose("elapsed dopo la fine resta la durata", session.elapsed(asOf: start.addingTimeInterval(99_999)), 3_600)
    h.checkClose("volume totale sessione", session.totalVolumeKg, 1_120)
    h.check("serie completate sessione", session.completedSets == 3)
    h.check("hasLoggedWork", session.hasLoggedWork)
    h.check("sessione vuota non ha lavoro", !WorkoutSession(name: "x").hasLoggedWork)

    if let data = try? JSONCoding.makeEncoder().encode(session),
       let restored = try? JSONCoding.makeDecoder().decode(WorkoutSession.self, from: data) {
        h.check("WorkoutSession round-trip: id e struttura", restored.id == session.id && restored.entries.count == 1)
        h.checkClose("WorkoutSession round-trip: volume", restored.totalVolumeKg, session.totalVolumeKg)
        h.checkClose("WorkoutSession round-trip: data inizio", restored.startedAt, session.startedAt)
    } else {
        h.fail("WorkoutSession round-trip fallito")
    }

    // MARK: Impostazioni

    h.section("modelli · UserSettings")

    var settings = UserSettings()
    h.check("default: kg", settings.unit == .kg)
    h.check("default: recupero 90s", settings.defaultRestSeconds == 90)
    h.check("default: nessun preferito", settings.favoriteExerciseIDs.isEmpty)

    settings.markRecent("0025")
    settings.markRecent("0043")
    settings.markRecent("0025")
    h.check("recenti: il più recente in testa", settings.recentExerciseIDs.first == "0025")
    h.check("recenti: nessun duplicato", settings.recentExerciseIDs == ["0025", "0043"])

    for index in 0..<40 { settings.markRecent("ex-\(index)") }
    h.check("recenti: tetto a 20", settings.recentExerciseIDs.count == UserSettings.maxRecentExercises)
    h.check("recenti: tiene gli ultimi", settings.recentExerciseIDs.first == "ex-39")
    settings.markRecent("")
    h.check("recenti: ignora id vuoto", !settings.recentExerciseIDs.contains(""))

    settings.favoriteExerciseIDs.insert("0025")
    if let data = try? JSONCoding.makeEncoder().encode(settings),
       let restored = try? JSONCoding.makeDecoder().decode(UserSettings.self, from: data) {
        h.check("UserSettings round-trip", restored == settings)
    } else {
        h.fail("UserSettings round-trip fallito")
    }

    if let partial = try? JSONDecoder().decode(UserSettings.self, from: Data(#"{"unit":"lb"}"#.utf8)) {
        h.check("UserSettings parziale: campo letto", partial.unit == .lb)
        h.check("UserSettings parziale: resto ai default", partial.defaultRestSeconds == 90 && partial.hapticsEnabled)
    } else {
        h.fail("UserSettings parziale non decodificato")
    }

}
