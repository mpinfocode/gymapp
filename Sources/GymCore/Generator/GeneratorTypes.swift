import Foundation

// Vocabolario comune del generatore di schede (SPEC §0: la scheda resta il cuore
// dell'app; qui si prepara solo il materiale per costruirne una).
//
// Tutti i tipi sono `Sendable` e senza dipendenze da SwiftUI: vivono in GymCore
// così che client e (eventuale) server usino le stesse regole e lo stesso testo.

/// Schema motorio dell'esercizio: è la dimensione con cui si costruisce un giorno
/// di allenamento ("una spinta orizzontale, una tirata verticale, un'anca dominante…").
///
/// Non coincide con il gruppo muscolare: `MuscleGroup` dice *cosa* si allena,
/// il pattern dice *come*. Servono entrambi, perché una scheda equilibrata si
/// costruisce sui pattern e si verifica sui gruppi.
public enum MovementPattern: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// Panca, spinte su panca, piegamenti, dip.
    case horizontalPush
    /// Lento avanti, spinte sopra la testa.
    case verticalPush
    /// Rematori.
    case horizontalPull
    /// Trazioni, lat machine.
    case verticalPull
    /// Squat e ginocchio dominanti bilaterali (compresa la pressa).
    case squat
    /// Anca dominanti: stacchi, ponte per i glutei, swing.
    case hinge
    /// Affondi, split squat, step-up: monolaterali di gamba.
    case lunge
    /// Isolamento di gamba: leg extension, leg curl, abduzioni.
    case legIsolation
    /// Polpacci.
    case calf
    /// Croci e pullover: isolamento del petto.
    case chestIsolation
    /// Pulldown a braccia tese e simili: isolamento del dorso.
    case backIsolation
    /// Estensioni lombari e iperestensioni.
    case backExtension
    /// Scrollate.
    case shrug
    /// Alzate laterali e frontali.
    case lateralRaise
    /// Deltoide posteriore: aperture, face pull.
    case rearDelt
    /// Curl per i bicipiti.
    case bicepsCurl
    /// Estensioni per i tricipiti.
    case tricepsExtension
    /// Polsi e avambracci.
    case forearm
    /// Core anti-estensione: plank, rollout, dead bug.
    case coreAntiExtension
    /// Core in flessione: crunch, sit-up, sollevamento gambe.
    case coreFlexion
    /// Core in rotazione e flessione laterale: russian twist, pallof press, side plank.
    case coreRotation
    /// Lavoro cardiovascolare.
    case cardio

    public var id: String { rawValue }

    /// Nome italiano, usato nella UI e nell'elenco candidati passato al modello.
    public var displayName: String {
        switch self {
        case .horizontalPush: "spinta orizzontale"
        case .verticalPush: "spinta verticale"
        case .horizontalPull: "tirata orizzontale"
        case .verticalPull: "tirata verticale"
        case .squat: "squat"
        case .hinge: "anca dominante"
        case .lunge: "affondo"
        case .legIsolation: "isolamento gambe"
        case .calf: "polpacci"
        case .chestIsolation: "isolamento petto"
        case .backIsolation: "isolamento dorso"
        case .backExtension: "estensione lombare"
        case .shrug: "scrollate"
        case .lateralRaise: "alzate spalle"
        case .rearDelt: "deltoide posteriore"
        case .bicepsCurl: "curl bicipiti"
        case .tricepsExtension: "estensione tricipiti"
        case .forearm: "avambracci"
        case .coreAntiExtension: "core anti-estensione"
        case .coreFlexion: "core in flessione"
        case .coreRotation: "core in rotazione"
        case .cardio: "cardio"
        }
    }

    /// Gruppi muscolari che questo pattern può legittimamente allenare.
    ///
    /// Serve al check di coerenza della selezione: se un id finisse su un gruppo
    /// fuori da questo insieme vuol dire che l'id è sbagliato o che il `target`
    /// del dataset è cambiato sotto i piedi.
    public var plausibleGroups: Set<MuscleGroup> {
        switch self {
        case .horizontalPush: [.chest, .triceps, .shoulders]
        case .verticalPush: [.shoulders, .triceps]
        case .horizontalPull: [.back]
        case .verticalPull: [.back, .biceps]
        case .squat: [.quads, .glutes]
        case .hinge: [.hamstrings, .glutes, .back]
        case .lunge: [.quads, .glutes]
        case .legIsolation: [.quads, .hamstrings, .glutes]
        case .calf: [.calves]
        case .chestIsolation: [.chest]
        case .backIsolation: [.back]
        case .backExtension: [.back, .glutes, .hamstrings]
        case .shrug: [.back]
        case .lateralRaise: [.shoulders]
        case .rearDelt: [.shoulders, .back]
        case .bicepsCurl: [.biceps]
        case .tricepsExtension: [.triceps]
        case .forearm: [.forearms]
        case .coreAntiExtension, .coreFlexion, .coreRotation: [.abs]
        case .cardio: [.cardio]
        }
    }

    /// Gruppo muscolare che ci si aspetta di allenare con questo schema.
    ///
    /// Serve alla scheda di riserva: fra due candidati dello stesso schema si
    /// preferisce quello che colpisce il muscolo per cui lo schema sta lì (una
    /// spinta orizzontale è per il petto, non per i tricipiti), così la
    /// copertura settimanale non dipende dal caso. `nil` quando lo schema serve
    /// onestamente più gruppi insieme.
    public var primaryGroup: MuscleGroup? {
        switch self {
        case .horizontalPush, .chestIsolation: .chest
        case .verticalPush, .lateralRaise, .rearDelt: .shoulders
        case .horizontalPull, .verticalPull, .backIsolation, .backExtension, .shrug: .back
        case .squat, .lunge: .quads
        case .hinge, .legIsolation: nil
        case .calf: .calves
        case .bicepsCurl: .biceps
        case .tricepsExtension: .triceps
        case .forearm: .forearms
        case .coreAntiExtension, .coreFlexion, .coreRotation: .abs
        case .cardio: .cardio
        }
    }

    /// `true` per i pattern che si misurano a tempo invece che a ripetizioni
    /// (plank e cardio).
    public var prefersDuration: Bool {
        self == .cardio
    }
}

/// Multiarticolare o di isolamento.
///
/// Decide range di ripetizioni, recupero e ordine nel giorno (i multiarticolari
/// vanno per primi, quando si è freschi).
public enum ExerciseKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case compound
    case isolation

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .compound: "Multiarticolare"
        case .isolation: "Isolamento"
        }
    }

    /// Lettera usata nell'elenco compatto passato al modello.
    public var compactCode: String {
        switch self {
        case .compound: "M"
        case .isolation: "I"
        }
    }
}

/// Esperienza minima richiesta da un esercizio.
///
/// Non è "quanto è difficile" in astratto: è "da quando in poi ha senso metterlo
/// in scheda". Lo stacco da terra e lo squat con bilanciere non sono da
/// principiante assoluto; la pressa e le macchine sì.
public enum TrainingLevel: String, Codable, Sendable, Hashable, CaseIterable, Identifiable, Comparable {
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

    /// Ordine crescente di esperienza.
    public var rank: Int {
        switch self {
        case .beginner: 0
        case .intermediate: 1
        case .advanced: 2
        }
    }

    public static func < (lhs: TrainingLevel, rhs: TrainingLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Attrezzatura minima che serve per fare l'esercizio.
///
/// Le tre classi sono **annidate**: chi ha la palestra completa può fare tutto,
/// chi ha manubri e panca può fare anche il corpo libero, chi ha solo corpo
/// libero ed elastici resta alla classe più stretta.
public enum EquipmentClass: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// Corpo libero, elastici, un tappetino.
    case bodyweightBands
    /// Manubri, kettlebell e una panca regolabile.
    case dumbbellBench
    /// Bilancieri, cavi, macchine, multipower.
    case gym

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bodyweightBands: "Corpo libero ed elastici"
        case .dumbbellBench: "Manubri e panca"
        case .gym: "Palestra completa"
        }
    }

    /// Ordine crescente di attrezzatura richiesta.
    public var rank: Int {
        switch self {
        case .bodyweightBands: 0
        case .dumbbellBench: 1
        case .gym: 2
        }
    }

    /// Classe dedotta dall'attrezzo del dataset (campo `equipment`, in inglese).
    ///
    /// Scelte non ovvie:
    /// - `weighted` sta in ``bodyweightBands``: nel nostro elenco compare solo su
    ///   esercizi a corpo libero dove il peso è facoltativo (plank);
    /// - `rope` sta in ``bodyweightBands``: è la corda per saltare;
    /// - kettlebell e palla medica stanno con i manubri (si sostituiscono con un
    ///   manubrio senza cambiare l'esercizio);
    /// - tutto ciò che richiede un telaio, un cavo o un bilanciere è ``gym``.
    public static func forEquipment(_ equipment: String) -> EquipmentClass {
        switch equipment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "body weight", "bodyweight", "band", "resistance band", "rope", "weighted":
            .bodyweightBands
        case "dumbbell", "kettlebell", "medicine ball", "stability ball", "bosu ball", "wheel roller":
            .dumbbellBench
        default:
            .gym
        }
    }
}

/// Zona che l'utente può voler proteggere (spalle, schiena bassa, ginocchia,
/// polsi e gomiti) e che alcuni esercizi sollecitano in modo marcato.
///
/// Non vuol dire "fa male": vuol dire che se quella zona è un punto debole
/// conviene scegliere altro. Le risposte del wizard e le etichette degli
/// esercizi usano lo stesso tipo, così il filtro è una semplice intersezione.
public enum StressZone: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case shoulders
    case lowerBack
    case knees
    case wristsElbows

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shoulders: "Spalle"
        case .lowerBack: "Schiena bassa"
        case .knees: "Ginocchia"
        case .wristsElbows: "Polsi e gomiti"
        }
    }

    /// Ordine stabile per la UI.
    public static let displayOrder: [StressZone] = allCases
}
