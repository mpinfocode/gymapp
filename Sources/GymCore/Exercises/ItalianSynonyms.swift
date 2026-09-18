import Foundation

/// Dizionario gergo italiano da palestra → termini inglesi del dataset (SPEC §2, punto 6).
///
/// I nomi degli esercizi restano in inglese a schermo: questo strato serve solo a far
/// **trovare** le cose a chi in palestra dice "panca piana", "lat machine" o "stacco".
///
/// ## Come funziona l'espansione
/// La query viene normalizzata (minuscole, senza accenti, punteggiatura → spazio) e
/// letta da sinistra a destra con match **più lungo per primo**, fino a 4 parole: così
/// "panca piana" diventa un'unica voce e non due token separati.
/// Ogni voce si espande in una lista di **alternative in OR**; ogni alternativa può
/// essere una frase di più parole, e in quel caso le parole sono in AND fra loro.
/// I gruppi restano in AND fra loro, esattamente come i token di prima.
///
/// Esempio: `"panca piana manubri"` →
/// `(barbell bench press | bench press) AND (dumbbell)`.
///
/// Un token senza traduzione resta sé stesso: le query in inglese seguono quindi
/// esattamente il percorso di prima e il ranking non cambia.
///
/// ## Ordine delle alternative
/// La prima alternativa è la più specifica (spesso il nome completo dell'esercizio
/// classico): quando coincide col nome di un esercizio questo prende il bonus di
/// match esatto e finisce in cima. Le successive allargano la rete.
public enum ItalianSynonyms {

    /// Numero massimo di parole di una voce multi-parola ("stacco a gambe tese").
    public static let maxPhraseWords = 4

    /// Voci del dizionario: chiave **già normalizzata** (minuscola, senza accenti),
    /// valore = alternative inglesi in OR.
    ///
    /// Le chiavi coprono singolare e plurale e le forme senza accento, perché è così
    /// che la gente digita di fretta con i guanti addosso.
    public static let entries: [String: [String]] = {
        var table: [String: [String]] = [:]

        func add(_ italian: [String], _ english: [String]) {
            for term in italian {
                table[SearchText.normalize(term)] = english
            }
        }

        // MARK: Petto
        add(["panca piana", "panca orizzontale", "distensioni su panca piana"],
            ["barbell bench press", "bench press"])
        add(["panca", "panche"], ["bench press", "bench"])
        // Anche in inglese la forma classica deve restare in testa: senza questa voce
        // "bench press" metterebbe davanti `band bench press` per solo ordine alfabetico.
        add(["bench press"], ["barbell bench press", "bench press"])
        add(["panca inclinata", "inclinata", "panca a 30", "panca 30"],
            ["incline bench press", "incline"])
        add(["panca declinata", "declinata"], ["decline bench press", "decline"])
        add(["panca manubri", "distensioni manubri su panca"],
            ["dumbbell bench press", "dumbbell press"])
        add(["croci", "croce", "aperture"], ["fly", "flye"])
        add(["croci ai cavi", "croci al cavo", "cross over", "crossover"],
            ["cable crossover", "cable fly"])
        add(["croci manubri", "croci con manubri"], ["dumbbell fly"])
        add(["chest press", "pressa petto"], ["chest press"])
        add(["distensioni", "distensione", "spinte", "spinta"], ["press"])
        add(["spinte manubri", "spinte con manubri"], ["dumbbell press"])
        add(["piegamenti", "flessioni", "piegamenti sulle braccia"], ["push-up", "push up"])
        add(["dip", "dips", "parallele", "piegamenti alle parallele"], ["dip"])
        add(["pullover", "pull over"], ["pullover"])
        add(["pettorali", "petto", "pettorale"], ["pectorals"])

        // MARK: Dorso
        add(["trazioni", "trazione", "trazioni alla sbarra"], ["pull-up", "chin-up"])
        add(["trazioni presa inversa", "chin up"], ["chin-up"])
        add(["lat machine", "lat machine avanti", "latmachine"], ["cable pulldown", "lat pulldown", "pulldown"])
        add(["pulldown", "tirate al petto"], ["pulldown"])
        add(["pulley", "pulley basso", "rematore ai cavi"], ["cable seated row", "seated row", "cable row"])
        add(["rematore", "rematori", "remata"], ["row"])
        add(["rematore bilanciere", "rematore con bilanciere"], ["barbell bent over row", "bent over row"])
        add(["rematore manubrio", "rematore con manubrio"], ["dumbbell bent over row", "bent over row"])
        add(["stacco", "stacchi", "stacco da terra", "stacchi da terra"],
            ["barbell deadlift", "deadlift"])
        add(["stacco rumeno", "stacchi rumeni", "rumeno"], ["romanian deadlift"])
        add(["stacco a gambe tese", "stacchi a gambe tese", "gambe tese"],
            ["stiff leg deadlift", "straight leg deadlift"])
        add(["stacco sumo", "stacchi sumo"], ["sumo deadlift"])
        add(["scrollate", "scrollata", "shrug"], ["shrug"])
        add(["iperestensioni", "iperestensione", "lombari"], ["hyperextension"])
        add(["dorsali", "dorsale", "gran dorsale", "schiena", "dorso"], ["lats", "upper back"])

        // MARK: Spalle
        add(["lento avanti", "military press", "military", "lento"],
            ["barbell military press", "military press", "overhead press"])
        add(["lento dietro"], ["behind neck press", "military press"])
        add(["spinte sopra la testa", "distensioni sopra la testa", "overhead"],
            ["overhead press", "shoulder press"])
        add(["shoulder press", "spinte spalle"], ["shoulder press"])
        add(["alzate laterali", "alzata laterale", "laterali"], ["lateral raise"])
        add(["alzate frontali", "alzata frontale", "frontali"], ["front raise"])
        add(["alzate posteriori", "alzate a 90", "posteriori"], ["rear lateral raise", "reverse fly"])
        add(["tirate al mento", "tirata al mento"], ["upright row"])
        add(["arnold", "arnold press"], ["arnold press"])
        add(["spalle", "deltoidi", "deltoide"], ["delts"])

        // MARK: Braccia
        add(["curl", "curl bicipiti"], ["curl"])
        add(["curl bilanciere", "curl con bilanciere"], ["barbell curl"])
        add(["curl manubri", "curl con manubri"], ["dumbbell curl"])
        add(["curl a martello", "martello", "hammer curl"], ["hammer curl"])
        add(["curl concentrato", "concentrato"], ["concentration curl"])
        add(["panca scott", "scott", "curl panca scott"], ["preacher curl"])
        add(["french press", "french", "distensioni francesi"], ["french press"])
        add(["pushdown", "push down", "spinte in basso", "tricipiti ai cavi"], ["pushdown"])
        add(["estensioni tricipiti", "estensione tricipiti"], ["triceps extension"])
        add(["skull crusher", "skullcrusher"], ["skull crusher", "lying triceps extension"])
        add(["kickback", "slanci tricipiti"], ["kickback"])
        add(["bicipiti", "bicipite"], ["biceps"])
        add(["tricipiti", "tricipite"], ["triceps"])
        add(["avambracci", "avambraccio", "polsi"], ["forearms", "wrist"])

        // MARK: Gambe
        add(["squat", "accosciata", "accosciate"], ["barbell full squat", "squat"])
        add(["squat bilanciere", "squat con bilanciere"], ["barbell full squat", "barbell squat"])
        add(["squat frontale", "front squat"], ["front squat"])
        add(["affondi", "affondo"], ["lunge"])
        add(["affondi manubri", "affondi con manubri"], ["dumbbell lunge", "lunge"])
        add(["affondi bilanciere", "affondi con bilanciere"], ["barbell lunge", "lunge"])
        add(["pressa", "pressa 45", "pressa a 45"], ["sled 45 leg press", "leg press"])
        add(["leg press", "pressa orizzontale"], ["leg press"])
        add(["hack squat", "hack"], ["hack squat"])
        add(["sissy squat"], ["sissy squat"])
        add(["leg extension", "estensioni gambe", "estensione gambe", "quadricipiti ai macchinari"],
            ["leg extension"])
        add(["leg curl", "femorali sdraiato", "curl femorali"], ["leg curl"])
        add(["quadricipiti", "quadricipite", "quadri"], ["quads"])
        add(["femorali", "femorale", "bicipite femorale", "ischiocrurali"], ["hamstrings"])
        add(["glutei", "gluteo"], ["glutes"])
        add(["hip thrust", "hip thrusts", "spinte in alto anca"], ["hip thrust"])
        add(["ponte", "ponte glutei", "glute bridge"], ["glute bridge", "bridge"])
        add(["slanci", "slanci glutei"], ["kickback", "hip extension"])
        add(["abduttori", "abduzioni"], ["abduction", "abductors"])
        add(["adduttori", "adduzioni"], ["adduction", "adductors"])
        add(["step up", "salita sul box"], ["step-up", "step up"])
        add(["polpacci", "polpaccio", "calf", "calf raise", "sollevamenti sui talloni"],
            ["calf raise", "calves"])

        // MARK: Addome
        add(["addominali", "addome", "addominale"], ["crunch", "abs"])
        add(["crunch", "crunches"], ["crunch"])
        add(["plank", "planck"], ["plank"])
        add(["obliqui", "obliquo"], ["obliques"])
        add(["sollevamento gambe", "sollevamenti gambe", "alzate gambe"], ["leg raise"])
        add(["russian twist", "torsioni russe"], ["russian twist"])
        add(["sit up", "sit ups"], ["sit-up"])

        // MARK: Cardio
        add(["tapis roulant", "tappeto"], ["treadmill"])
        add(["corsa", "correre"], ["run", "treadmill"])
        add(["cyclette", "bici", "bicicletta"], ["stationary bike", "bike"])
        add(["ellittica"], ["elliptical"])
        add(["vogatore", "rematore a macchina"], ["rowing", "row"])
        add(["salto della corda", "saltare la corda", "corda per saltare"], ["jump rope", "rope"])

        // MARK: Attrezzi
        add(["manubri", "manubrio", "con manubri"], ["dumbbell"])
        add(["bilanciere", "bilancieri", "con bilanciere"], ["barbell"])
        add(["bilanciere ez", "ez"], ["ez barbell", "ez bar"])
        add(["cavi", "cavo", "ai cavi", "al cavo"], ["cable"])
        add(["elastico", "elastici", "banda elastica", "bande elastiche"], ["band"])
        add(["multipower", "smith machine", "castello"], ["smith"])
        add(["macchina", "macchinario", "macchine"], ["leverage machine", "machine"])
        add(["corpo libero", "a corpo libero"], ["body weight"])
        add(["kettlebell", "kettlebells"], ["kettlebell"])
        add(["trap bar"], ["trap bar"])
        add(["palla medica"], ["medicine ball"])
        add(["fitball", "palla svizzera"], ["stability ball"])
        add(["slitta"], ["sled"])

        return table
    }()

    /// Numero di voci del dizionario (comodo per i check).
    public static var count: Int { entries.count }

    // MARK: - Espansione della query

    /// Un gruppo della query: alternative in OR, ognuna con i suoi termini in AND.
    public struct Group: Sendable, Hashable {
        /// Testo originale (normalizzato) coperto dal gruppo.
        public let source: String
        /// Alternative in OR; ogni alternativa è una lista di termini in AND.
        public let alternatives: [[String]]

        public init(source: String, alternatives: [[String]]) {
            self.source = source
            self.alternatives = alternatives
        }

        /// `true` se il gruppo ha prodotto alternative inglesi oltre al testo digitato.
        public var isTranslated: Bool { alternatives.count > 1 }
    }

    /// Spezza la query normalizzata in gruppi, espandendo il gergo italiano.
    ///
    /// - Complessità: O(parole × ``maxPhraseWords``) con un lookup di dizionario per
    ///   tentativo; su una query da palestra sono una manciata di operazioni.
    public static func expand(tokens: [String]) -> [Group] {
        var groups: [Group] = []
        var index = 0
        while index < tokens.count {
            var matched = false
            let maxWords = min(maxPhraseWords, tokens.count - index)
            var length = maxWords
            while length >= 1 {
                let phrase = tokens[index..<(index + length)].joined(separator: " ")
                if let english = entries[phrase] {
                    // Le alternative si normalizzano come l'indice ("pull-up" → ["pull","up"]).
                    // Il testo digitato resta **sempre** come ultima alternativa: così
                    // l'espansione può solo allargare i risultati, mai toglierne.
                    var alternatives = english.map(SearchText.tokens).filter { !$0.isEmpty }
                    let original = phrase.split(separator: " ").map(String.init)
                    if !alternatives.contains(original) { alternatives.append(original) }
                    groups.append(Group(source: phrase, alternatives: alternatives))
                    index += length
                    matched = true
                    break
                }
                length -= 1
            }
            if !matched {
                let token = tokens[index]
                groups.append(Group(source: token, alternatives: [[token]]))
                index += 1
            }
        }
        return groups
    }

    /// Espansione a partire dal testo grezzo digitato dall'utente.
    public static func expand(query: String) -> [Group] {
        expand(tokens: SearchText.tokens(query))
    }
}
