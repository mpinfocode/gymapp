import Foundation
import GymCore

/// Uno scenario di prova: un profilo di utente realistico.
struct Scenario: Sendable {
    let name: String
    let title: String
    let answers: GeneratorAnswers
}

enum Scenarios {

    /// La batteria di prova: dodici profili che coprono tutte le scelte del
    /// wizard e i casi che rompono di più (casa senza attrezzi, zone da
    /// proteggere, sei giorni, forza).
    static let all: [Scenario] = [
        Scenario(
            name: "2g-fullbody-principiante",
            title: "2 giorni total body, principiante, 45 minuti, palestra",
            answers: GeneratorAnswers(
                goal: .generalFitness,
                daysPerWeek: 2,
                split: .fullBody,
                experience: .beginner,
                sessionLength: .short45,
                equipment: .fullGym,
                weeks: 8
            )
        ),
        Scenario(
            name: "3g-fullbody",
            title: "3 giorni total body, principiante, 60 minuti, palestra",
            answers: GeneratorAnswers(
                goal: .muscleGain,
                daysPerWeek: 3,
                split: .fullBody,
                experience: .beginner,
                sessionLength: .medium60,
                equipment: .fullGym,
                weeks: 8
            )
        ),
        Scenario(
            name: "3g-ppl-intermedio",
            title: "3 giorni spinta/tirata/gambe, intermedio, 60 minuti",
            answers: GeneratorAnswers(
                goal: .muscleGain,
                daysPerWeek: 3,
                split: .pushPullLegs,
                experience: .intermediate,
                sessionLength: .medium60,
                equipment: .fullGym,
                weeks: 8
            )
        ),
        Scenario(
            name: "4g-upperlower-spalle",
            title: "4 giorni sopra/sotto, intermedio, spalle da proteggere",
            answers: GeneratorAnswers(
                goal: .muscleGain,
                daysPerWeek: 4,
                split: .upperLower,
                experience: .intermediate,
                sessionLength: .medium60,
                equipment: .fullGym,
                protectedZones: [.shoulders],
                weeks: 8
            )
        ),
        Scenario(
            name: "4g-priorita-glutei",
            title: "4 giorni, priorità glutei e gambe",
            answers: GeneratorAnswers(
                goal: .muscleGain,
                daysPerWeek: 4,
                split: .upperLower,
                experience: .intermediate,
                sessionLength: .long90,
                equipment: .fullGym,
                focusGroups: [.glutes, .quads],
                weeks: 8
            )
        ),
        Scenario(
            name: "5g-gruppi-avanzato",
            title: "5 giorni per gruppi muscolari, avanzato, 75-90 minuti",
            answers: GeneratorAnswers(
                goal: .muscleGain,
                daysPerWeek: 5,
                split: .muscleGroups,
                experience: .advanced,
                sessionLength: .long90,
                equipment: .fullGym,
                weeks: 10
            )
        ),
        Scenario(
            name: "6g-ppl-doppio",
            title: "6 giorni spinta/tirata/gambe ripetuta, avanzato",
            answers: GeneratorAnswers(
                goal: .muscleGain,
                daysPerWeek: 6,
                split: .pushPullLegs,
                experience: .advanced,
                sessionLength: .medium60,
                equipment: .fullGym,
                weeks: 10
            )
        ),
        Scenario(
            name: "casa-manubri",
            title: "Casa con manubri e panca, 3 giorni total body",
            answers: GeneratorAnswers(
                goal: .muscleGain,
                daysPerWeek: 3,
                split: .fullBody,
                experience: .intermediate,
                sessionLength: .medium60,
                equipment: .dumbbellsBench,
                weeks: 8
            )
        ),
        Scenario(
            name: "corpo-libero",
            title: "Corpo libero ed elastici, 4 giorni sopra/sotto",
            answers: GeneratorAnswers(
                goal: .generalFitness,
                daysPerWeek: 4,
                split: .upperLower,
                experience: .beginner,
                sessionLength: .short45,
                equipment: .bodyweightBands,
                weeks: 6
            )
        ),
        Scenario(
            name: "schiena-ginocchia",
            title: "Schiena bassa e ginocchia da proteggere, 3 giorni",
            answers: GeneratorAnswers(
                goal: .generalFitness,
                daysPerWeek: 3,
                split: .fullBody,
                experience: .beginner,
                sessionLength: .medium60,
                equipment: .fullGym,
                protectedZones: [.lowerBack, .knees],
                weeks: 8
            )
        ),
        Scenario(
            name: "dimagrimento-cardio",
            title: "Dimagrimento con cardio a fine seduta, 4 giorni",
            answers: GeneratorAnswers(
                goal: .fatLoss,
                daysPerWeek: 4,
                split: .upperLower,
                experience: .beginner,
                sessionLength: .medium60,
                equipment: .fullGym,
                includeCardio: true,
                weeks: 8
            )
        ),
        Scenario(
            name: "forza",
            title: "Forza, 4 giorni sopra/sotto, avanzato",
            answers: GeneratorAnswers(
                goal: .strength,
                daysPerWeek: 4,
                split: .upperLower,
                experience: .advanced,
                sessionLength: .long90,
                equipment: .fullGym,
                weeks: 12
            )
        ),
    ]

    static func named(_ name: String) -> Scenario? {
        all.first { $0.name == name }
    }

    /// I nomi della batteria rapida (`--quick`): tre profili che coprono i casi
    /// che contano davvero e che, a tre chiamate per modello, devono stare sotto
    /// il minuto.
    ///
    /// Uno facile (total body in palestra), uno con un vincolo che restringe i
    /// candidati (spalle da proteggere) e uno con pochissimi candidati e poco
    /// tempo (corpo libero, 45 minuti): se un modello regge questi tre, regge.
    static let quickNames = [
        "3g-fullbody",
        "4g-upperlower-spalle",
        "corpo-libero",
    ]

    static var quick: [Scenario] { quickNames.compactMap(named) }
}

/// Prezzi e note sui modelli. **Sono indicativi**: cambiano con il fornitore e
/// con il tempo, servono a dare l'ordine di grandezza del costo di una scheda e
/// a scegliere chi provare per primo.
///
/// I prezzi della fascia veloce e di quella accurata sono stati ricontrollati su
/// openrouter.ai il 22/09/2026 (pagine `openrouter.ai/<slug>`):
/// `google/gemini-2.5-flash-lite` $0,10/$0,40, `google/gemini-2.5-flash`
/// $0,30/$2,50, `anthropic/claude-haiku-4.5` $1,00/$5,00, `openai/gpt-5-mini`
/// $0,25/$2,00, `mistralai/mistral-small-2603` (Mistral Small 4) $0,15/$0,60.
///
/// La colonna che conta davvero è `reasoning`: dopo la prima prova reale (quattro
/// risposte vuote su quattro con `openai/gpt-5-nano`) i modelli che ragionano per
/// forza si provano solo con il ragionamento al minimo, e con un tetto di token
/// più alto (``GeneratorPrompt/outputTokenBudget(parameters:model:)``).
enum ModelPricing {

    /// La fascia di modelli da provare.
    enum Tier: String, CaseIterable, Sendable {
        /// Veloci ed economicissimi: è quello che gira sul telefono.
        case fast
        /// Più bravi, ancora entro un centesimo di dollaro a scheda.
        case smart
        /// Tutti e due, la veloce per prima.
        case all

        var displayName: String {
            switch self {
            case .fast: "veloce"
            case .smart: "accurata"
            case .all: "tutte"
            }
        }
    }

    /// Come si comporta il modello rispetto al ragionamento interno.
    enum Reasoning: String, Sendable {
        /// Non ragiona affatto: il parametro viene ignorato.
        case never = "no"
        /// Ragiona, ma si spegne (`enabled: false` o `effort: "none"`).
        case optional = "spegnibile"
        /// Ragiona per forza: si può solo chiedere `effort: "minimal"`.
        case mandatory = "obbligatorio"
    }

    struct Price: Sendable {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let reasoning: Reasoning
        /// Nota breve per il rapporto.
        let note: String
    }

    static let table: [String: Price] = [
        // --- fascia veloce ---
        "google/gemini-2.5-flash-lite": Price(
            inputPerMillion: 0.10, outputPerMillion: 0.40, reasoning: .optional,
            note: "provato dal vivo il 18/09/2026: 1,0 s e $0,0004 a scheda, tre schede su tre valide"
        ),
        "mistralai/mistral-small-2603": Price(
            inputPerMillion: 0.15, outputPerMillion: 0.60, reasoning: .optional,
            note: "Mistral Small 4, structured output nativo"
        ),
        "qwen/qwen3-30b-a3b-instruct-2507": Price(
            inputPerMillion: 0.048, outputPerMillion: 0.193, reasoning: .never,
            note: "istruito, non pensante: zero rischio di risposta vuota"
        ),
        // --- fascia accurata, tutti entro un centesimo a scheda ---
        "google/gemini-2.5-flash": Price(
            inputPerMillion: 0.30, outputPerMillion: 2.50, reasoning: .optional,
            note: "il fratello maggiore del predefinito: ~$0,002 a scheda"
        ),
        "anthropic/claude-haiku-4.5": Price(
            inputPerMillion: 1.00, outputPerMillion: 5.00, reasoning: .optional,
            note: "il più caro ammesso, ~$0,0055 a scheda; niente schema stretto, si parte da json_object"
        ),
        "openai/gpt-5-mini": Price(
            inputPerMillion: 0.25, outputPerMillion: 2.00, reasoning: .mandatory,
            note: "ragiona per forza: `effort: minimal` e tetto di token più alto, ~$0,002 a scheda"
        ),
        // --- provati e non più in uso ---
        "openai/gpt-4.1-nano": Price(
            inputPerMillion: 0.10, outputPerMillion: 0.40, reasoning: .never,
            note: "nella prova del 18/09/2026 nessun fornitore lo serviva con i vincoli richiesti"
        ),
        "openai/gpt-5.4-nano": Price(
            inputPerMillion: 0.20, outputPerMillion: 1.25, reasoning: .optional,
            note: "stesso esito di gpt-4.1-nano: 404 in un decimo di secondo"
        ),
        "openai/gpt-5-nano": Price(
            inputPerMillion: 0.05, outputPerMillion: 0.40, reasoning: .mandatory,
            note: "economicissimo ma ragiona per forza: è quello che ha fatto fallire la prima prova"
        ),
        "inception/mercury-2.5": Price(
            inputPerMillion: 0.04, outputPerMillion: 0.15, reasoning: .optional,
            note: "a diffusione, genera i token in parallelo: il più rapido del catalogo"
        ),
    ]

    /// Il costo di una scheda tipo, per decidere chi può stare nella fascia
    /// accurata: circa 4.000 token in entrata e 300 in uscita.
    static let typicalPromptTokens = 4_000
    static let typicalCompletionTokens = 300
    /// Tetto di spesa per scheda dichiarato dal PM.
    static let costCeiling = 0.01

    /// La fascia veloce: il predefinito verificato dal vivo più due alternative.
    ///
    /// I due modelli OpenAI della prima prova non ci sono più: non hanno mai
    /// risposto, e il motivo (nessun fornitore con quei vincoli) adesso si
    /// riconosce dal messaggio invece di scambiarlo per un id inesistente.
    static let fastModels = [
        "google/gemini-2.5-flash-lite",
        "mistralai/mistral-small-2603",
        "qwen/qwen3-30b-a3b-instruct-2507",
    ]

    /// La fascia accurata: modelli di classe superiore che restano sotto il
    /// centesimo a scheda e sotto i 15 secondi.
    static let smartModels = [
        "google/gemini-2.5-flash",
        "anthropic/claude-haiku-4.5",
        "openai/gpt-5-mini",
    ]

    static func models(tier: Tier) -> [String] {
        switch tier {
        case .fast: fastModels
        case .smart: smartModels
        case .all: fastModels + smartModels
        }
    }

    /// I modelli provati per impostazione predefinita: la fascia veloce.
    static let defaultModels = fastModels

    /// Costo stimato di una scheda tipo con quel modello.
    static func typicalCost(model: String) -> Double? {
        guard let price = table[model] else { return nil }
        return Double(typicalPromptTokens) / 1_000_000 * price.inputPerMillion
            + Double(typicalCompletionTokens) / 1_000_000 * price.outputPerMillion
    }

    /// Come si ordinano i modelli quando li sceglie l'utente: prima chi non
    /// ragiona, poi chi si lascia spegnere, infine chi ragiona per forza.
    static func speedRank(_ model: String) -> Int {
        guard let price = table[model] else { return 1 }
        switch price.reasoning {
        case .never: return 0
        case .optional: return 1
        case .mandatory: return 3
        }
    }

    static func sortedBySpeed(_ models: [String]) -> [String] {
        models.enumerated()
            .sorted { lhs, rhs in
                let l = speedRank(lhs.element)
                let r = speedRank(rhs.element)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    /// Il ragionamento da chiedere a quel modello, in chiaro per il rapporto.
    static func reasoningLabel(_ model: String) -> String {
        OpenRouterClient.recommendedReasoning(forModel: model).displayName
    }

    /// Costo stimato in dollari, `nil` se il modello non è in tabella.
    static func cost(model: String, usage: OpenRouterClient.Usage?) -> Double? {
        guard let usage, let price = table[model] else { return nil }
        return Double(usage.promptTokens) / 1_000_000 * price.inputPerMillion
            + Double(usage.completionTokens) / 1_000_000 * price.outputPerMillion
    }

    static func formatCost(_ value: Double?) -> String {
        guard let value else { return "n/d" }
        return String(format: "$%.5f", value)
    }
}
