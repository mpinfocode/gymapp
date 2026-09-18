import Foundation
import GymCore

/// Cosa ci si aspetta da una query in gergo italiano.
struct ItalianQueryCase: Sendable {
    let query: String
    /// Id che deve comparire fra i primi ``withinTop`` risultati.
    let expected: String
    let withinTop: Int
    /// Promemoria leggibile (compare nel messaggio d'errore).
    let note: String

    init(_ query: String, _ expected: String, top withinTop: Int = 1, _ note: String) {
        self.query = query
        self.expected = expected
        self.withinTop = withinTop
        self.note = note
    }
}

/// Query in gergo italiano con l'esercizio che ci si aspetta di vedere.
///
/// Sono 42 e coprono tutte le famiglie del dizionario ``ItalianSynonyms``:
/// petto, dorso, spalle, braccia, gambe, addome, cardio, attrezzi, comprese le
/// espressioni multi-parola ("panca piana", "stacco da terra", "alzate laterali manubri").
let italianQueryCases: [ItalianQueryCase] = [
    // Petto
    .init("panca piana", "0025", top: 3, "barbell bench press"),
    .init("panca piana bilanciere", "0025", "barbell bench press"),
    .init("panca inclinata", "0047", top: 5, "barbell incline bench press"),
    .init("panca manubri", "0289", top: 5, "dumbbell bench press"),
    .init("spinte manubri", "0289", top: 10, "dumbbell bench press"),
    .init("croci manubri", "0308", top: 5, "dumbbell fly"),
    .init("croci ai cavi", "0158", top: 3, "cable decline fly"),
    .init("piegamenti", "0662", top: 5, "push-up"),
    .init("flessioni", "0662", top: 5, "push-up"),

    // Dorso
    .init("trazioni", "0652", top: 5, "pull-up"),
    .init("lat machine", "0198", "cable pulldown"),
    .init("pulley", "0861", top: 3, "cable seated row"),
    .init("rematore bilanciere", "0027", top: 5, "barbell bent over row"),
    .init("stacco", "0032", "barbell deadlift"),
    .init("stacco da terra", "0032", top: 3, "barbell deadlift"),
    .init("stacco rumeno", "0085", top: 3, "barbell romanian deadlift"),
    .init("stacco a gambe tese", "0432", top: 10, "dumbbell stiff leg deadlift"),
    .init("scrollate", "0095", top: 10, "barbell shrug"),

    // Spalle
    .init("alzate laterali", "0334", top: 10, "dumbbell lateral raise"),
    .init("alzate laterali manubri", "0334", "dumbbell lateral raise"),
    .init("alzate frontali", "0310", top: 10, "dumbbell front raise"),
    .init("lento avanti", "0091", top: 3, "barbell seated overhead press"),
    .init("tirate al mento", "0120", top: 5, "barbell upright row"),

    // Braccia
    .init("curl bilanciere", "0031", top: 3, "barbell curl"),
    .init("curl manubri", "0294", "dumbbell biceps curl"),
    .init("curl a martello", "0313", top: 5, "dumbbell hammer curl"),
    .init("panca scott", "0070", top: 10, "preacher curl"),
    .init("french press", "1749", top: 5, "ez bar standing french press"),
    .init("pushdown", "0201", top: 5, "cable pushdown"),

    // Gambe
    .init("squat", "0043", top: 3, "barbell full squat"),
    .init("squat bilanciere", "0043", top: 2, "barbell full squat"),
    .init("affondi", "0336", top: 10, "dumbbell lunge"),
    .init("affondi manubri", "0336", top: 5, "dumbbell lunge"),
    .init("pressa", "0739", top: 2, "sled 45 leg press"),
    .init("leg extension", "0585", top: 3, "lever leg extension"),
    .init("leg curl", "0586", top: 10, "lever lying leg curl"),
    .init("hip thrust", "3236", top: 3, "resistance band hip thrusts"),

    // Addome e cardio
    .init("addominali", "0274", top: 5, "crunch floor"),
    .init("plank", "0464", top: 5, "front plank with twist"),
    .init("tapis roulant", "3666", top: 3, "walking on incline treadmill"),
    .init("cyclette", "0798", top: 3, "stationary bike walk"),
    .init("multipower squat", "0770", top: 10, "smith squat"),
    .init("bench press", "0025", top: 3, "barbell bench press (query inglese)"),
    .init("lateral raise", "0334", top: 3, "dumbbell lateral raise (query inglese)"),
    .init("leg curl", "0586", top: 5, "lever lying leg curl (query inglese)"),
]

/// Query che nominano una zona del corpo: qui non conta *quale* esercizio esce,
/// conta che escano tutti esercizi di quella zona.
let italianMuscleQueryCases: [(query: String, muscles: [String])] = [
    ("pettorali", ["pectorals", "upper chest", "serratus anterior", "chest"]),
    ("petto", ["pectorals", "upper chest", "serratus anterior", "chest"]),
    ("dorsali", ["lats", "latissimus dorsi", "upper back"]),
    ("addominali", ["abs", "abdominals", "obliques", "core", "lower abs"]),
    ("spalle", ["delts", "deltoids", "rear deltoids", "shoulders", "rotator cuff"]),
    ("bicipiti", ["biceps", "brachialis"]),
    ("tricipiti", ["triceps"]),
    ("avambracci", ["forearms", "wrist extensors", "wrist flexors", "wrists"]),
    ("quadricipiti", ["quads", "quadriceps"]),
    ("femorali", ["hamstrings"]),
    ("glutei", ["glutes"]),
    ("polpacci", ["calves", "soleus"]),
]

@MainActor
func runItalianSearchChecks(_ h: Harness, repository: ExerciseRepository?) {
    guard let repository else {
        h.section("ricerca italiana")
        h.fail("repository non caricato")
        return
    }

    // Sonda manuale: `GYMCHECKS_VERBOSE=1 swift run GymChecks` stampa i primi 5
    // risultati di ogni query, comoda quando si allarga il dizionario.
    let verbose = ProcessInfo.processInfo.environment["GYMCHECKS_VERBOSE"] == "1"

    h.section("ricerca italiana · query reali")

    for testCase in italianQueryCases {
        let results = repository.search(ExerciseFilter(query: testCase.query), limit: max(testCase.withinTop, 5))
        if verbose {
            print("   · \(testCase.query) → \(results.prefix(5).map { "\($0.id) \($0.name)" }.joined(separator: " | "))")
        }
        let found = results.prefix(testCase.withinTop).contains { $0.id == testCase.expected }
        h.check(
            "\"\(testCase.query)\" → \(testCase.note) nei primi \(testCase.withinTop) (ottenuto: \(results.prefix(3).map(\.name).joined(separator: ", ")))",
            found
        )
    }

    h.check("almeno 40 query italiane verificate", italianQueryCases.count >= 40)

    h.section("ricerca italiana · zone del corpo")

    for testCase in italianMuscleQueryCases {
        let results = repository.search(ExerciseFilter(query: testCase.query), limit: 20)
        if verbose {
            print("   · \(testCase.query) → \(results.prefix(3).map(\.name).joined(separator: " | "))")
        }
        h.check("\"\(testCase.query)\" dà risultati", !results.isEmpty)
        let offenders = results.filter { exercise in
            let muscles = Set([exercise.target] + exercise.secondaryMuscles)
            return muscles.isDisjoint(with: testCase.muscles)
        }
        h.check("\"\(testCase.query)\": i primi 20 lavorano davvero quella zona (\(offenders.map(\.name).prefix(3)))",
                offenders.isEmpty)
    }

    // MARK: Dizionario

    h.section("ricerca italiana · dizionario")

    h.check("almeno 80 voci nel dizionario (\(ItalianSynonyms.count))", ItalianSynonyms.count >= 80)
    h.check("chiavi già normalizzate", ItalianSynonyms.entries.keys.allSatisfy { SearchText.normalize($0) == $0 })
    h.check("nessuna voce senza traduzione", ItalianSynonyms.entries.values.allSatisfy { !$0.isEmpty })
    h.check("nessuna traduzione vuota", ItalianSynonyms.entries.values.allSatisfy { $0.allSatisfy { !$0.isEmpty } })

    let expansion = ItalianSynonyms.expand(query: "panca piana manubri")
    h.check("le frasi si prendono per intere", expansion.count == 2)
    h.check("prima frase riconosciuta", expansion.first?.source == "panca piana")
    h.check("seconda parola riconosciuta", expansion.last?.source == "manubri")
    h.check("il testo digitato resta fra le alternative",
            expansion.first?.alternatives.contains(["panca", "piana"]) == true)
    h.check("alternative normalizzate come l'indice",
            ItalianSynonyms.expand(query: "trazioni").first?.alternatives.contains(["pull", "up"]) == true)

    // Query inglese senza voci a dizionario: deve restare identica a sé stessa.
    let unknown = ItalianSynonyms.expand(query: "lever seated row")
    h.check("una query inglese resta token per token", unknown.count == 3)
    h.check("una query inglese non viene espansa", unknown.allSatisfy { $0.alternatives == [[$0.source]] })

    h.check("forma singolare e plurale", ItalianSynonyms.entries["affondo"] == ItalianSynonyms.entries["affondi"])
    h.check("forme senza accento", ItalianSynonyms.entries["cyclette"] != nil)

    // MARK: Esercizio canonico

    // A parità di fascia, davanti va il nome con meno parole di troppo.
    h.section("ricerca italiana · esercizio canonico")

    func names(_ query: String, _ count: Int) -> [String] {
        repository.search(ExerciseFilter(query: query), limit: count).map(\.name)
    }

    h.check("\"lat machine\": nessun \"bicep curl\" nei primi 3 (\(names("lat machine", 3)))",
            names("lat machine", 3).allSatisfy { !$0.contains("bicep curl") })
    h.check("\"alzate laterali manubri\": il nome più semplice per primo",
            names("alzate laterali manubri", 1) == ["dumbbell lateral raise"])
    h.check("\"curl manubri\": il nome più semplice per primo",
            names("curl manubri", 1) == ["dumbbell biceps curl"])
    h.check("\"pressa\": la pressa a 45 per prima", names("pressa", 1) == ["sled 45° leg press"])
    h.check("\"stacco\": lo stacco classico per primo", names("stacco", 1) == ["barbell deadlift"])
    h.check("\"squat bilanciere\": lo squat classico per primo", names("squat bilanciere", 1) == ["barbell full squat"])
    h.check("\"bench press\" in inglese: la panca classica resta prima",
            names("bench press", 1) == ["barbell bench press"])
    h.check("\"lateral raise\" in inglese: solo alzate laterali nei primi 3 (\(names("lateral raise", 3)))",
            names("lateral raise", 3).allSatisfy { $0.contains("lateral raise") })
    h.check("\"leg curl\" in inglese: i leg curl da macchina nei primi 5",
            names("leg curl", 5).contains("lever lying leg curl"))

    // MARK: Nessuna regressione sulle query inglesi

    h.section("ricerca italiana · nessuna regressione in inglese")

    h.check("match esatto ancora primo", repository.search(ExerciseFilter(query: "barbell bench press")).first?.id == "0025")
    h.check("pull-up ancora primo", repository.search(ExerciseFilter(query: "pull-up")).first?.id == "0652")
    h.check("prefisso ancora privilegiato",
            repository.search(ExerciseFilter(query: "barbell")).first?.name.hasPrefix("barbell") == true)
    h.check("query vuota = tutta la libreria", repository.search(ExerciseFilter(query: "")).count == repository.count)
    h.check("query vuota in ordine alfabetico",
            repository.search(ExerciseFilter(query: "")).map(\.id) == repository.all.map(\.id))
    h.check("query senza riscontri ancora vuota", repository.search(ExerciseFilter(query: "zzz nessun esercizio")).isEmpty)

    // MARK: Prestazioni

    h.section("ricerca italiana · prestazioni")

    let queries = italianQueryCases.map(\.query)
    let rounds = 10
    let started = Date()
    var produced = 0
    for _ in 0..<rounds {
        for query in queries {
            produced += repository.search(ExerciseFilter(query: query), limit: 50).count
        }
    }
    let averageMs = Date().timeIntervalSince(started) / Double(queries.count * rounds) * 1000
    // Soglia larga perché `swift run` compila in debug (bounds checking ovunque):
    // in release la stessa ricerca sta abbondantemente sotto il millisecondo.
    h.check("una ricerca italiana su 1.324 esercizi sotto i 25 ms in debug (\(String(format: "%.1f", averageMs)) ms)",
            averageMs < 25)
    h.check("le ricerche italiane hanno prodotto risultati", produced > 0)
}
