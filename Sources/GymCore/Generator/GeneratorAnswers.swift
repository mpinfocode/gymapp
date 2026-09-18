import Foundation

// Le risposte del wizard "crea scheda". Tutte domande chiuse: l'utente non
// scrive niente, tocca delle scelte. I nomi italiani stanno in `displayName`
// (sono per la UI), i `rawValue` restano in inglese perché finiscono nel JSON
// e nel prompt e non devono cambiare quando si ritocca una etichetta.

/// Obiettivo dichiarato dall'utente.
public enum TrainingGoal: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case muscleGain
    case strength
    case fatLoss
    case generalFitness

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .muscleGain: "Massa muscolare"
        case .strength: "Forza"
        case .fatLoss: "Dimagrimento"
        case .generalFitness: "Forma fisica generale"
        }
    }

    public var explanation: String {
        switch self {
        case .muscleGain: "Volume medio-alto, ripetizioni da 6 a 15, recuperi medi."
        case .strength: "Poche ripetizioni sui fondamentali, recuperi lunghi."
        case .fatLoss: "Circuiti brevi, ripetizioni alte, recuperi corti e cardio."
        case .generalFitness: "Un po' di tutto, senza esagerare con il volume."
        }
    }
}

/// Come sono divisi i giorni della scheda.
public enum TrainingSplit: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case fullBody
    case upperLower
    case pushPullLegs
    case muscleGroups

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullBody: "Total body"
        case .upperLower: "Sopra e sotto"
        case .pushPullLegs: "Spinta, tirata, gambe"
        case .muscleGroups: "Gruppi muscolari"
        }
    }

    public var explanation: String {
        switch self {
        case .fullBody: "Ogni seduta allena tutto il corpo. La scelta più efficiente con pochi giorni."
        case .upperLower: "Un giorno la parte alta, un giorno la parte bassa."
        case .pushPullLegs: "Un giorno le spinte, uno le tirate, uno le gambe."
        case .muscleGroups: "Un gruppo muscolare per seduta, come nelle schede classiche da palestra."
        }
    }
}

/// Esperienza di allenamento dichiarata.
public enum TrainingExperience: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .beginner: "Principiante"
        case .intermediate: "Intermedio"
        case .advanced: "Avanzato"
        }
    }

    public var explanation: String {
        switch self {
        case .beginner: "Meno di sei mesi di sala pesi, o si ricomincia da zero."
        case .intermediate: "Da sei mesi a due anni, i fondamentali sono già stati imparati."
        case .advanced: "Oltre due anni di allenamento continuativo."
        }
    }

    /// Livello massimo di esercizi che ha senso proporre.
    public var maxExerciseLevel: TrainingLevel {
        switch self {
        case .beginner: .beginner
        case .intermediate: .intermediate
        case .advanced: .advanced
        }
    }
}

/// Tempo a disposizione per seduta.
public enum SessionLength: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case short45
    case medium60
    case long90

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .short45: "45 minuti"
        case .medium60: "60 minuti"
        case .long90: "75-90 minuti"
        }
    }

    /// Minuti indicativi, usati solo per spiegare il vincolo nel prompt.
    public var minutes: Int {
        switch self {
        case .short45: 45
        case .medium60: 60
        case .long90: 85
        }
    }

    /// Quanti esercizi stanno in quella seduta, riscaldamento escluso.
    public var exerciseCount: ClosedRange<Int> {
        switch self {
        case .short45: 4...6
        case .medium60: 5...7
        case .long90: 7...9
        }
    }
}

/// Attrezzatura a disposizione.
public enum EquipmentAvailability: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case fullGym
    case dumbbellsBench
    case bodyweightBands

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullGym: "Palestra completa"
        case .dumbbellsBench: "Casa con manubri e panca"
        case .bodyweightBands: "Corpo libero ed elastici"
        }
    }

    /// Classe massima di attrezzatura utilizzabile.
    public var equipmentClass: EquipmentClass {
        switch self {
        case .fullGym: .gym
        case .dumbbellsBench: .dumbbellBench
        case .bodyweightBands: .bodyweightBands
        }
    }
}

/// Tutte le risposte del wizard.
///
/// È il **solo** ingresso del generatore: da qui si ricavano i parametri
/// numerici (``GeneratorPlanParameters``), i candidati (``GeneratorCandidates``),
/// il prompt e la scheda di riserva.
public struct GeneratorAnswers: Codable, Sendable, Hashable {

    /// Giorni a settimana ammessi.
    public static let daysRange: ClosedRange<Int> = 2...6
    /// Durata della scheda in settimane.
    public static let weeksRange: ClosedRange<Int> = 4...12

    /// Gruppi su cui si può chiedere di insistere: quelli che un utente indica
    /// davvero come punto debole. Fuori avambracci, polpacci e cardio: non sono
    /// mai il motivo per cui si cambia scheda.
    public static let focusableGroups: [MuscleGroup] = [
        .chest, .back, .shoulders, .biceps, .triceps, .abs, .quads, .hamstrings, .glutes,
    ]

    public var goal: TrainingGoal
    /// Giorni a settimana, 2-6.
    public var daysPerWeek: Int
    public var split: TrainingSplit
    public var experience: TrainingExperience
    public var sessionLength: SessionLength
    public var equipment: EquipmentAvailability
    /// Zone su cui insistere (volume maggiorato). Al massimo due: di più non è
    /// una priorità, è un elenco.
    public var focusGroups: Set<MuscleGroup>
    /// Zone da proteggere: gli esercizi che le sollecitano vengono esclusi.
    public var protectedZones: Set<StressZone>
    /// Aggiungere lavoro cardiovascolare a fine seduta.
    public var includeCardio: Bool
    /// Durata prevista della scheda, in settimane.
    public var weeks: Int

    public init(
        goal: TrainingGoal = .muscleGain,
        daysPerWeek: Int = 3,
        split: TrainingSplit = .fullBody,
        experience: TrainingExperience = .beginner,
        sessionLength: SessionLength = .medium60,
        equipment: EquipmentAvailability = .fullGym,
        focusGroups: Set<MuscleGroup> = [],
        protectedZones: Set<StressZone> = [],
        includeCardio: Bool = false,
        weeks: Int = 8
    ) {
        self.goal = goal
        self.daysPerWeek = daysPerWeek.clamped(to: GeneratorAnswers.daysRange)
        self.experience = experience
        self.sessionLength = sessionLength
        self.equipment = equipment
        self.focusGroups = focusGroups.filter(GeneratorAnswers.focusableGroups.contains)
        self.protectedZones = protectedZones
        self.includeCardio = includeCardio
        self.weeks = weeks.clamped(to: GeneratorAnswers.weeksRange)
        // La divisione dipende dai giorni: se la combinazione non esiste si
        // ricade sulla consigliata invece di generare una scheda impossibile.
        let available = GeneratorAnswers.availableSplits(forDays: self.daysPerWeek)
        self.split = available.contains(split)
            ? split
            : GeneratorAnswers.recommendedSplit(days: self.daysPerWeek, experience: experience)
    }

    // MARK: - Compatibilità fra giorni e divisione

    /// Divisioni che hanno senso con quel numero di giorni.
    ///
    /// Regole da preparatore, non da manuale: la push/pull/legs vuole multipli di
    /// tre, la divisione per gruppi muscolari sotto i tre giorni lascerebbe
    /// scoperta mezza settimana, il total body sopra i tre giorni diventa
    /// ingestibile come recupero.
    public static func availableSplits(forDays days: Int) -> [TrainingSplit] {
        switch days.clamped(to: daysRange) {
        case 2: [.fullBody, .upperLower]
        case 3: [.fullBody, .upperLower, .pushPullLegs, .muscleGroups]
        case 4: [.upperLower, .muscleGroups]
        case 5: [.upperLower, .muscleGroups]
        default: [.pushPullLegs, .upperLower, .muscleGroups]
        }
    }

    /// Divisione consigliata per quella combinazione di giorni ed esperienza.
    public static func recommendedSplit(days: Int, experience: TrainingExperience) -> TrainingSplit {
        switch days.clamped(to: daysRange) {
        case 2: .fullBody
        case 3: experience == .beginner ? .fullBody : .pushPullLegs
        case 4: .upperLower
        case 5: experience == .advanced ? .muscleGroups : .upperLower
        default: .pushPullLegs
        }
    }

    /// `true` se giorni e divisione sono compatibili.
    public var isConsistent: Bool {
        GeneratorAnswers.availableSplits(forDays: daysPerWeek).contains(split)
    }

    /// Riepilogo in italiano delle risposte, usato nel prompt e nei rapporti.
    public var summaryLines: [String] {
        var lines = [
            "Obiettivo: \(goal.displayName)",
            "Giorni a settimana: \(daysPerWeek)",
            "Divisione: \(split.displayName)",
            "Esperienza: \(experience.displayName)",
            "Tempo per seduta: \(sessionLength.displayName)",
            "Attrezzatura: \(equipment.displayName)",
        ]
        if !focusGroups.isEmpty {
            let names = MuscleGroup.displayOrder.filter(focusGroups.contains).map(\.displayName)
            lines.append("Zone su cui insistere: \(names.joined(separator: ", "))")
        }
        if !protectedZones.isEmpty {
            let names = StressZone.displayOrder.filter(protectedZones.contains).map(\.displayName)
            lines.append("Zone da proteggere: \(names.joined(separator: ", "))")
        }
        lines.append("Cardio a fine seduta: \(includeCardio ? "sì" : "no")")
        lines.append("Durata della scheda: \(weeks) settimane")
        return lines
    }
}

extension Comparable {
    /// Riporta il valore dentro l'intervallo.
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
