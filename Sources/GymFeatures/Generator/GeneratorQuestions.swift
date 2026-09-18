import Foundation
import GymCore

/// Le dieci domande del wizard, nell'ordine della SPEC §0.
///
/// L'ordine è fisso e non dipende dalle risposte: il wizard è **sempre lo stesso**,
/// così chi lo rifà una seconda volta sa già dove sta andando.
enum GeneratorStep: Int, CaseIterable, Hashable, Identifiable {
    case goal
    case days
    case split
    case experience
    case sessionLength
    case equipment
    case focus
    case protect
    case cardio
    case weeks

    var id: Int { rawValue }

    /// Numero della domanda, da 1.
    var number: Int { rawValue + 1 }

    /// Quante domande in tutto.
    static let count = GeneratorStep.allCases.count

    /// La domanda, come la legge l'utente.
    var title: String {
        switch self {
        case .goal: "Che obiettivo hai?"
        case .days: "Quanti giorni a settimana?"
        case .split: "Come dividiamo i giorni?"
        case .experience: "Da quanto ti alleni?"
        case .sessionLength: "Quanto tempo hai per seduta?"
        case .equipment: "Cosa hai a disposizione?"
        case .focus: "Su cosa vuoi insistere?"
        case .protect: "C'è una zona da proteggere?"
        case .cardio: "Vuoi del cardio?"
        case .weeks: "Per quante settimane?"
        }
    }

    /// Una riga sotto il titolo, solo dove serve davvero.
    var subtitle: String? {
        switch self {
        case .focus: "Al massimo due zone, e puoi anche saltare."
        case .protect: "Gli esercizi che la sollecitano non entreranno in scheda."
        default: nil
        }
    }

    /// Etichetta corta della riga di riepilogo.
    var summaryLabel: String {
        switch self {
        case .goal: "Obiettivo"
        case .days: "Giorni"
        case .split: "Divisione"
        case .experience: "Esperienza"
        case .sessionLength: "Tempo"
        case .equipment: "Attrezzatura"
        case .focus: "Insisti su"
        case .protect: "Proteggi"
        case .cardio: "Cardio"
        case .weeks: "Durata"
        }
    }

    /// `true` per le domande a scelta multipla o facoltative: hanno "Avanti" e
    /// "Salta" invece dell'avanzamento automatico al tocco.
    var isOptional: Bool {
        self == .focus || self == .protect
    }

    var previous: GeneratorStep? {
        GeneratorStep(rawValue: rawValue - 1)
    }

    var next: GeneratorStep? {
        GeneratorStep(rawValue: rawValue + 1)
    }
}

// MARK: - Testi delle risposte che non stanno già in GymCore

/// Spiegazioni delle risposte che il motore non porta con sé.
///
/// Gli enum di `GymCore/Generator` hanno già `displayName` ed `explanation`
/// (obiettivo, divisione, esperienza): quelli si riusano e basta. Qui ci sono
/// solo i valori che in GymCore sono numeri o booleani.
enum GeneratorCopy {

    /// Giorni a settimana: cosa comporta la scelta.
    static func days(_ value: Int) -> (title: String, detail: String) {
        switch value {
        case 2: ("2 giorni", "Due sedute lunghe che allenano tutto il corpo.")
        case 3: ("3 giorni", "Il compromesso migliore fra risultati e tempo.")
        case 4: ("4 giorni", "Si può dividere parte alta e parte bassa.")
        case 5: ("5 giorni", "Più volume per gruppo, serve costanza.")
        default: ("6 giorni", "Da chi si allena da anni e recupera bene.")
        }
    }

    /// Tempo per seduta.
    static func sessionLength(_ value: SessionLength) -> String {
        switch value {
        case .short45: "Da 4 a 6 esercizi, recuperi contenuti."
        case .medium60: "Da 5 a 7 esercizi, la durata più comune."
        case .long90: "Da 7 a 9 esercizi, con recuperi lunghi."
        }
    }

    /// Attrezzatura.
    static func equipment(_ value: EquipmentAvailability) -> String {
        switch value {
        case .fullGym: "Bilancieri, macchine e cavi: nessun limite di scelta."
        case .dumbbellsBench: "Solo manubri, kettlebell e una panca."
        case .bodyweightBands: "Corpo libero ed elastici, niente pesi."
        }
    }

    /// Cardio sì o no.
    static func cardio(_ value: Bool) -> (title: String, detail: String) {
        value
            ? ("Sì", "Un blocco di cardio in coda a ogni seduta.")
            : ("No", "Solo pesi: il cardio lo gestisci per conto tuo.")
    }

    /// Durata della scheda in settimane.
    static func weeks(_ value: Int) -> (title: String, detail: String) {
        switch value {
        case 4: ("4 settimane", "Un ciclo breve, da rivedere presto.")
        case 6: ("6 settimane", "Il tempo giusto per vedere dei progressi.")
        default: ("8 settimane", "Un ciclo lungo, da cambiare a fine percorso.")
        }
    }

    /// Le durate proposte dal wizard (SPEC §0).
    static let weekOptions = [4, 6, 8]

    /// Zone su cui si può insistere, nell'ordine della UI.
    static let focusableGroups = GeneratorAnswers.focusableGroups

    /// Cosa comporta insistere su una zona.
    static func focus(_ group: MuscleGroup) -> String {
        "Un esercizio in più a settimana per \(group.displayName.lowercased())."
    }

    /// Cosa comporta proteggere una zona.
    static func protect(_ zone: StressZone) -> String {
        switch zone {
        case .shoulders: "Niente spinte sopra la testa e distensioni aggressive."
        case .lowerBack: "Niente stacchi e squat liberi con il bilanciere."
        case .knees: "Niente affondi profondi e salti."
        case .wristsElbows: "Niente presa stretta e nessun esercizio che carica i gomiti."
        }
    }

    /// L'avviso obbligatorio della domanda sulle zone da proteggere.
    static let medicalDisclaimer =
        "Non è un parere medico: in caso di dolore o infortunio chiedi a un professionista."

    /// Riga che accompagna l'opzione "Consigliata" della divisione.
    static func recommendedSplitDetail(days: Int, experience: TrainingExperience) -> String {
        let split = GeneratorAnswers.recommendedSplit(days: days, experience: experience)
        return "Con \(days) giorni sceglie \(split.displayName.lowercased())."
    }

    /// Nomi delle zone scelte, separati da virgola; stringa vuota se nessuna.
    static func groupList(_ groups: Set<MuscleGroup>) -> String {
        MuscleGroup.displayOrder.filter(groups.contains).map(\.displayName).joined(separator: ", ")
    }

    /// Nomi delle zone protette, separati da virgola.
    static func zoneList(_ zones: Set<StressZone>) -> String {
        StressZone.displayOrder.filter(zones.contains).map(\.displayName).joined(separator: ", ")
    }
}
