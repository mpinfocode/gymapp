import Foundation

/// Lo scheletro di un giorno di allenamento: come si chiama e quali schemi
/// motori deve contenere, nell'ordine in cui vanno eseguiti.
///
/// I pattern **si possono ripetere** (un giorno di petto ha due spinte
/// orizzontali): il generatore sceglie ogni volta un esercizio diverso.
public struct GeneratorDayBlueprint: Sendable, Hashable {

    /// Nome italiano del giorno, come finirà nella scheda.
    public let name: String
    /// Schemi motori obbligatori, in ordine (prima i multiarticolari).
    public let requiredPatterns: [MovementPattern]
    /// Schemi con cui riempire la seduta quando c'è più tempo.
    public let optionalPatterns: [MovementPattern]

    public init(_ name: String, _ requiredPatterns: [MovementPattern], _ optionalPatterns: [MovementPattern]) {
        self.name = name
        self.requiredPatterns = requiredPatterns
        self.optionalPatterns = optionalPatterns
    }

    /// Tutti gli schemi previsti dal giorno, senza duplicati e in ordine.
    public var allPatterns: [MovementPattern] {
        var seen: Set<MovementPattern> = []
        return (requiredPatterns + optionalPatterns).filter { seen.insert($0).inserted }
    }

    /// Sequenza di schemi lunga almeno `count`, allungata ripetendo gli
    /// opzionali (e, se serve, gli obbligatori): un giorno da 9 esercizi non può
    /// restare a corto di idee.
    public func patternSequence(count: Int) -> [MovementPattern] {
        var sequence = requiredPatterns + optionalPatterns
        let pool = optionalPatterns.isEmpty ? requiredPatterns : optionalPatterns
        var index = 0
        while sequence.count < count, !pool.isEmpty {
            sequence.append(pool[index % pool.count])
            index += 1
        }
        return sequence
    }
}

/// I numeri della scheda, calcolati dalle risposte **prima** di chiamare il
/// modello: serie, ripetizioni, recuperi, quanti esercizi al giorno, quanto
/// volume a settimana per gruppo, la struttura dei giorni.
///
/// È il pezzo che rende il generatore affidabile anche con un modello economico:
/// al modello si chiede solo di *scegliere gli esercizi*, non di inventare la
/// programmazione.
public struct GeneratorPlanParameters: Sendable, Hashable {

    public let answers: GeneratorAnswers

    /// Ripetizioni per i multiarticolari.
    public let compoundReps: ClosedRange<Int>
    /// Ripetizioni per gli esercizi di isolamento.
    public let isolationReps: ClosedRange<Int>
    /// Recupero in secondi fra le serie dei multiarticolari.
    public let compoundRest: Int
    /// Recupero in secondi fra le serie degli isolamenti.
    public let isolationRest: Int
    /// Serie di lavoro per i multiarticolari.
    public let compoundSets: Int
    /// Serie di lavoro per gli isolamenti.
    public let isolationSets: Int
    /// Quanti esercizi per seduta, cardio compreso.
    public let exercisesPerDay: ClosedRange<Int>
    /// Numero di esercizi a cui puntare.
    public let targetExercisesPerDay: Int
    /// Serie settimanali indicative per gruppo muscolare (solo i gruppi allenati).
    public let weeklySetsByGroup: [MuscleGroup: Int]
    /// Struttura dei giorni.
    public let days: [GeneratorDayBlueprint]
    /// Durata del cardio finale, in secondi; `nil` se non richiesto.
    public let cardioSeconds: Int?

    // MARK: - Costruzione

    public init(answers: GeneratorAnswers) {
        self.answers = answers

        switch answers.goal {
        case .strength:
            compoundReps = 3...6
            isolationReps = 6...10
            compoundRest = 180
            isolationRest = 120
            compoundSets = answers.experience == .beginner ? 3 : 5
            isolationSets = 3
        case .muscleGain:
            compoundReps = 6...10
            isolationReps = 10...15
            compoundRest = 120
            isolationRest = 75
            compoundSets = answers.experience == .beginner ? 3 : 4
            isolationSets = 3
        case .fatLoss:
            compoundReps = 10...15
            isolationReps = 12...20
            compoundRest = 60
            isolationRest = 45
            compoundSets = 3
            isolationSets = 3
        case .generalFitness:
            compoundReps = 8...12
            isolationReps = 10...15
            compoundRest = 90
            isolationRest = 60
            compoundSets = 3
            isolationSets = 3
        }

        let blueprints = GeneratorPlanParameters.blueprints(
            split: answers.split,
            days: answers.daysPerWeek
        )
        days = blueprints

        // Il cardio occupa un posto nella seduta: il tempo è quello.
        let range = answers.sessionLength.exerciseCount
        exercisesPerDay = range
        targetExercisesPerDay = (range.lowerBound + range.upperBound + 1) / 2

        cardioSeconds = answers.includeCardio ? (answers.goal == .fatLoss ? 900 : 600) : nil

        // Volume settimanale indicativo: non è una promessa, è il riferimento con
        // cui il validatore e il rapporto dicono se la scheda è equilibrata.
        let base: Int
        switch answers.experience {
        case .beginner: base = 9
        case .intermediate: base = 14
        case .advanced: base = 18
        }
        var volume: [MuscleGroup: Int] = [:]
        for group in MuscleGroup.displayOrder where group != .other && group != .cardio {
            let boosted = answers.focusGroups.contains(group) ? Int((Double(base) * 1.35).rounded()) : base
            volume[group] = boosted
        }
        weeklySetsByGroup = volume
    }

    // MARK: - Uso

    /// Ripetizioni previste per quel tipo di esercizio.
    public func reps(for kind: ExerciseKind) -> ClosedRange<Int> {
        kind == .compound ? compoundReps : isolationReps
    }

    /// Recupero previsto per quel tipo di esercizio.
    public func rest(for kind: ExerciseKind) -> Int {
        kind == .compound ? compoundRest : isolationRest
    }

    /// Serie previste per quel tipo di esercizio.
    public func sets(for kind: ExerciseKind) -> Int {
        kind == .compound ? compoundSets : isolationSets
    }

    /// Nomi dei giorni, nell'ordine.
    public var dayNames: [String] { days.map(\.name) }

    /// Quanti esercizi sono ammessi in una seduta: il numero a cui si punta,
    /// più o meno uno.
    ///
    /// Prima il validatore allargava ancora l'intervallo di un esercizio per
    /// parte, "per non essere pignoli": è così che una full body da 60 minuti
    /// con quattro esercizi al giorno è stata dichiarata valida (prova reale del
    /// 18/09/2026). Il tempo a disposizione è un vincolo vero in tutte e due le
    /// direzioni, e sotto il minimo la scheda non allena, sopra il massimo non
    /// si finisce.
    public var allowedExercisesPerDay: ClosedRange<Int> {
        max(1, targetExercisesPerDay - 1)...(targetExercisesPerDay + 1)
    }

    /// Esercizi previsti in tutta la settimana: serve a decidere quali gruppi
    /// si può pretendere di allenare direttamente.
    public var weeklyExerciseBudget: Int { days.count * targetExercisesPerDay }

    /// Riepilogo in italiano dei vincoli numerici, per il prompt e per i rapporti.
    public var summaryLines: [String] {
        var lines = [
            "Giorni: \(days.count) (\(dayNames.joined(separator: ", ")))",
            "Esercizi per giorno: da \(exercisesPerDay.lowerBound) a \(exercisesPerDay.upperBound)",
            "Multiarticolari: \(compoundSets) serie da \(compoundReps.lowerBound) a \(compoundReps.upperBound) ripetizioni, recupero \(compoundRest) s",
            "Isolamenti: \(isolationSets) serie da \(isolationReps.lowerBound) a \(isolationReps.upperBound) ripetizioni, recupero \(isolationRest) s",
        ]
        if let cardioSeconds {
            lines.append("Cardio a fine seduta: 1 esercizio da \(cardioSeconds / 60) minuti")
        }
        return lines
    }

    // MARK: - Struttura dei giorni

    /// Scheletri dei giorni per ogni combinazione divisione × giorni (2-6).
    public static func blueprints(split: TrainingSplit, days: Int) -> [GeneratorDayBlueprint] {
        let count = days.clamped(to: GeneratorAnswers.daysRange)
        switch split {
        case .fullBody: return Array(fullBody.prefix(max(2, count)))
        case .upperLower: return upperLower(days: count)
        case .pushPullLegs: return pushPullLegs(days: count)
        case .muscleGroups: return muscleGroups(days: count)
        }
    }

    // Total body: tre giorni diversi fra loro, si prendono i primi N.
    private static let fullBody: [GeneratorDayBlueprint] = [
        .init(
            "Total body A",
            [.squat, .horizontalPush, .horizontalPull, .bicepsCurl],
            [.coreAntiExtension, .lateralRaise, .calf, .coreFlexion, .legIsolation]
        ),
        .init(
            "Total body B",
            [.hinge, .verticalPush, .verticalPull, .tricepsExtension],
            [.coreFlexion, .lunge, .rearDelt, .calf, .coreRotation]
        ),
        .init(
            "Total body C",
            [.lunge, .horizontalPush, .verticalPull, .lateralRaise],
            [.coreRotation, .legIsolation, .bicepsCurl, .tricepsExtension, .calf]
        ),
        .init(
            "Total body D",
            [.squat, .verticalPush, .horizontalPull, .coreAntiExtension],
            [.hinge, .chestIsolation, .rearDelt, .calf, .coreFlexion]
        ),
        .init(
            "Total body E",
            [.hinge, .horizontalPush, .verticalPull, .coreFlexion],
            [.legIsolation, .lateralRaise, .tricepsExtension, .bicepsCurl, .calf]
        ),
        .init(
            "Total body F",
            [.lunge, .verticalPush, .horizontalPull, .coreRotation],
            [.squat, .chestIsolation, .backIsolation, .calf, .coreAntiExtension]
        ),
    ]

    private static let upperA = GeneratorDayBlueprint(
        "Parte alta A",
        [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .lateralRaise, .bicepsCurl, .tricepsExtension],
        [.rearDelt, .chestIsolation, .shrug, .forearm, .coreAntiExtension]
    )
    private static let lowerA = GeneratorDayBlueprint(
        "Parte bassa A",
        [.squat, .hinge, .lunge, .legIsolation, .calf, .coreAntiExtension],
        [.legIsolation, .backExtension, .coreFlexion, .coreRotation]
    )
    private static let upperB = GeneratorDayBlueprint(
        "Parte alta B",
        [.verticalPush, .verticalPull, .horizontalPush, .horizontalPull, .rearDelt, .tricepsExtension, .bicepsCurl],
        [.chestIsolation, .lateralRaise, .backIsolation, .forearm, .coreRotation]
    )
    private static let lowerB = GeneratorDayBlueprint(
        "Parte bassa B",
        [.hinge, .lunge, .squat, .legIsolation, .calf, .coreFlexion],
        [.legIsolation, .backExtension, .coreAntiExtension, .coreRotation]
    )
    private static let armsShoulders = GeneratorDayBlueprint(
        "Spalle e braccia",
        [.verticalPush, .lateralRaise, .rearDelt, .bicepsCurl, .tricepsExtension],
        [.shrug, .forearm, .bicepsCurl, .tricepsExtension, .coreRotation]
    )
    private static let upperC = GeneratorDayBlueprint(
        "Parte alta C",
        [.horizontalPush, .verticalPull, .lateralRaise, .horizontalPull, .bicepsCurl, .tricepsExtension],
        [.chestIsolation, .backIsolation, .rearDelt, .forearm, .coreAntiExtension]
    )
    private static let lowerC = GeneratorDayBlueprint(
        "Parte bassa C",
        [.lunge, .hinge, .legIsolation, .squat, .calf, .coreRotation],
        [.legIsolation, .backExtension, .coreFlexion, .coreAntiExtension]
    )

    private static func upperLower(days: Int) -> [GeneratorDayBlueprint] {
        switch days {
        case 2: [upperA, lowerA]
        case 3: [upperA, lowerA, upperB]
        case 4: [upperA, lowerA, upperB, lowerB]
        case 5: [upperA, lowerA, upperB, lowerB, armsShoulders]
        default: [upperA, lowerA, upperB, lowerB, upperC, lowerC]
        }
    }

    private static let pushA = GeneratorDayBlueprint(
        "Spinta A",
        [.horizontalPush, .verticalPush, .lateralRaise, .tricepsExtension],
        [.chestIsolation, .horizontalPush, .tricepsExtension, .lateralRaise, .coreAntiExtension]
    )
    private static let pullA = GeneratorDayBlueprint(
        "Tirata A",
        [.verticalPull, .horizontalPull, .rearDelt, .bicepsCurl],
        [.backIsolation, .shrug, .bicepsCurl, .forearm, .coreFlexion]
    )
    private static let legsA = GeneratorDayBlueprint(
        "Gambe A",
        [.squat, .hinge, .lunge, .legIsolation, .calf],
        [.coreAntiExtension, .legIsolation, .coreFlexion, .backExtension]
    )
    private static let pushB = GeneratorDayBlueprint(
        "Spinta B",
        [.verticalPush, .horizontalPush, .lateralRaise, .tricepsExtension],
        [.chestIsolation, .horizontalPush, .lateralRaise, .tricepsExtension, .coreRotation]
    )
    private static let pullB = GeneratorDayBlueprint(
        "Tirata B",
        [.horizontalPull, .verticalPull, .rearDelt, .bicepsCurl],
        [.backIsolation, .shrug, .bicepsCurl, .forearm, .coreRotation]
    )
    private static let legsB = GeneratorDayBlueprint(
        "Gambe B",
        [.hinge, .lunge, .squat, .legIsolation, .calf],
        [.coreFlexion, .legIsolation, .backExtension, .coreAntiExtension]
    )

    private static func pushPullLegs(days: Int) -> [GeneratorDayBlueprint] {
        days >= 6 ? [pushA, pullA, legsA, pushB, pullB, legsB] : [pushA, pullA, legsA]
    }

    private static let chestTriceps = GeneratorDayBlueprint(
        "Petto e tricipiti",
        [.horizontalPush, .horizontalPush, .tricepsExtension, .tricepsExtension],
        [.chestIsolation, .horizontalPush, .chestIsolation, .tricepsExtension, .coreAntiExtension]
    )
    private static let backBiceps = GeneratorDayBlueprint(
        "Dorso e bicipiti",
        [.verticalPull, .horizontalPull, .bicepsCurl, .bicepsCurl],
        [.backIsolation, .horizontalPull, .shrug, .bicepsCurl, .forearm, .coreFlexion]
    )
    private static let legsShoulders = GeneratorDayBlueprint(
        "Gambe e spalle",
        [.squat, .hinge, .legIsolation, .verticalPush, .lateralRaise],
        [.lunge, .calf, .rearDelt, .legIsolation, .coreRotation]
    )
    private static let legsOnly = GeneratorDayBlueprint(
        "Gambe",
        [.squat, .hinge, .lunge, .legIsolation, .legIsolation, .calf],
        [.legIsolation, .backExtension, .calf, .coreAntiExtension]
    )
    private static let shouldersArms = GeneratorDayBlueprint(
        "Spalle e braccia",
        [.verticalPush, .lateralRaise, .rearDelt, .bicepsCurl, .tricepsExtension],
        [.lateralRaise, .bicepsCurl, .tricepsExtension, .shrug, .forearm]
    )
    private static let chestOnly = GeneratorDayBlueprint(
        "Petto",
        [.horizontalPush, .horizontalPush, .horizontalPush, .horizontalPush],
        [.chestIsolation, .chestIsolation, .tricepsExtension, .coreAntiExtension, .coreFlexion]
    )
    private static let backOnly = GeneratorDayBlueprint(
        "Dorso",
        [.verticalPull, .horizontalPull, .horizontalPull, .verticalPull],
        [.backIsolation, .shrug, .rearDelt, .backExtension, .bicepsCurl, .coreFlexion]
    )
    private static let shouldersOnly = GeneratorDayBlueprint(
        "Spalle",
        [.verticalPush, .lateralRaise, .rearDelt, .lateralRaise],
        [.verticalPush, .rearDelt, .shrug, .coreRotation, .coreAntiExtension]
    )
    private static let armsOnly = GeneratorDayBlueprint(
        "Braccia",
        [.bicepsCurl, .tricepsExtension, .bicepsCurl, .tricepsExtension],
        [.bicepsCurl, .tricepsExtension, .forearm, .forearm, .coreFlexion]
    )
    private static let quadsDay = GeneratorDayBlueprint(
        "Quadricipiti",
        [.squat, .lunge, .squat, .legIsolation, .calf],
        [.lunge, .legIsolation, .calf, .coreAntiExtension]
    )
    private static let posteriorDay = GeneratorDayBlueprint(
        "Femorali e glutei",
        [.hinge, .hinge, .legIsolation, .legIsolation, .calf],
        [.backExtension, .lunge, .calf, .coreFlexion]
    )

    private static func muscleGroups(days: Int) -> [GeneratorDayBlueprint] {
        switch days {
        case 2: [chestTriceps, backBiceps]
        case 3: [chestTriceps, backBiceps, legsShoulders]
        case 4: [chestTriceps, backBiceps, legsOnly, shouldersArms]
        case 5: [chestOnly, backOnly, legsOnly, shouldersOnly, armsOnly]
        default: [chestOnly, backOnly, shouldersOnly, armsOnly, quadsDay, posteriorDay]
        }
    }
}
