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
}

/// Prezzi indicativi per milione di token, letti dall'API dei modelli di
/// OpenRouter il 18/09/2026. **Sono indicativi**: cambiano con il provider e con
/// il tempo, servono solo a dare l'ordine di grandezza del costo di una scheda.
enum ModelPricing {

    struct Price: Sendable {
        let inputPerMillion: Double
        let outputPerMillion: Double
    }

    static let table: [String: Price] = [
        "openai/gpt-5-nano": Price(inputPerMillion: 0.05, outputPerMillion: 0.40),
        "openai/gpt-5-mini": Price(inputPerMillion: 0.25, outputPerMillion: 2.00),
        "openai/gpt-4.1-nano": Price(inputPerMillion: 0.10, outputPerMillion: 0.40),
        "openai/gpt-4.1-mini": Price(inputPerMillion: 0.40, outputPerMillion: 1.60),
        "google/gemini-2.5-flash-lite": Price(inputPerMillion: 0.10, outputPerMillion: 0.40),
        "google/gemini-2.5-flash": Price(inputPerMillion: 0.30, outputPerMillion: 2.50),
        "qwen/qwen3.5-flash-02-23": Price(inputPerMillion: 0.065, outputPerMillion: 0.26),
        "mistralai/ministral-8b-2512": Price(inputPerMillion: 0.15, outputPerMillion: 0.15),
    ]

    /// I tre modelli provati per impostazione predefinita: i due più economici
    /// con structured output dichiarato, più uno di riserva più capace.
    static let defaultModels = [
        "openai/gpt-5-nano",
        "google/gemini-2.5-flash-lite",
        "openai/gpt-5-mini",
    ]

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
