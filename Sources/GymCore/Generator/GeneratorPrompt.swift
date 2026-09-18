import Foundation

/// Il testo mandato al modello.
///
/// Sta in GymCore, non nella feature: così l'app, i check e il banco di prova
/// usano **lo stesso identico prompt**, e una modifica si vede subito nei test.
///
/// È scritto in italiano. Con i modelli economici la tentazione è l'inglese,
/// ma qui l'output contiene testo per l'utente (nome della scheda, nome dei
/// giorni, note): un prompt italiano riduce di molto le note in inglese o i
/// nomi tradotti a metà. I nomi degli esercizi restano in inglese perché sono
/// gli stessi che l'utente vedrà a schermo (SPEC §0).
///
/// ## Formato compatto (18/09/2026)
/// Prima si chiedeva al modello un JSON con nome della scheda, nome dei giorni e,
/// per ogni esercizio, `sets`, `repsMin`, `repsMax`, `rest` e una nota: circa
/// 1.100 token di risposta per una scheda da sei giorni, cioè quasi tutto il
/// tempo di attesa dell'utente. Ma serie, ripetizioni e recuperi **li calcola già
/// il telefono** (``GeneratorPlanParameters``) e il prompt stesso ordinava di
/// ricopiarli senza cambiarli: erano token spesi per farsi restituire quel che si
/// era appena mandato. Anche i nomi dei giorni sono decisi dal telefono.
///
/// Resta quindi solo la cosa che il modello sa fare meglio del telefono:
/// **scegliere gli esercizi e metterli in ordine**. È anche ciò che chiede
/// SPEC §0 alla lettera, "il modello risponde SOLO con JSON di id".
public enum GeneratorPrompt {

    /// Istruzioni di sistema: chi è, cosa fa, cosa non deve fare.
    public static let system = """
    Sei un preparatore atletico esperto di sala pesi. Scegli gli esercizi di una scheda \
    da palestra, come li sceglieresti per un tuo cliente.

    Regole assolute:
    1. Rispondi SOLO con un oggetto JSON valido, senza testo prima o dopo, senza blocchi \
    di codice, senza commenti.
    2. Usa esclusivamente gli id presenti nell'elenco dei candidati. Non inventare id, \
    non inventare esercizi, non usare nomi al posto degli id.
    3. In ogni giorno metti prima i multiarticolari (M) e poi gli isolamenti (I).
    4. Non ripetere lo stesso id due volte nello stesso giorno.
    5. Serie, ripetizioni, recuperi e carichi non li scrivi tu: li calcola l'app.
    6. Il nome della scheda è in italiano, breve, senza trattini lunghi.
    """

    /// Il messaggio utente, costruito dalle risposte.
    public static func user(
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> String {
        var blocks: [String] = []

        blocks.append("PERSONA\n" + answers.summaryLines.map { "- \($0)" }.joined(separator: "\n"))

        // I vincoli numerici non si ripetono in prosa: non sono più affar suo.
        // L'unico numero che il modello deve rispettare è quanti esercizi mettere.
        let structure = parameters.days.enumerated().map { index, day -> String in
            let patterns = day.requiredPatterns.map(\.displayName).joined(separator: ", ")
            return "\(index + 1). \(day.name): \(patterns)"
        }
        blocks.append(
            "GIORNI, in questo ordine\n"
            + structure.joined(separator: "\n")
            + "\nDa \(parameters.exercisesPerDay.lowerBound) a \(parameters.exercisesPerDay.upperBound) "
            + "esercizi per giorno. Gli schemi motori elencati sono l'ossatura del giorno: "
            + "seguili finché ci sono candidati adatti, poi completa con quel che serve."
        )

        if !answers.focusGroups.isEmpty {
            let names = MuscleGroup.displayOrder.filter(answers.focusGroups.contains).map(\.displayName)
            blocks.append("PRIORITÀ\nDai un esercizio in più a settimana a: \(names.joined(separator: ", ")).")
        }
        if !answers.protectedZones.isEmpty {
            let names = StressZone.displayOrder.filter(answers.protectedZones.contains).map(\.displayName)
            blocks.append(
                "ZONE DA PROTEGGERE\n\(names.joined(separator: ", ")). "
                + "Gli esercizi che le sollecitano sono già stati tolti dai candidati: "
                + "scegli solo dall'elenco e sei a posto."
            )
        }
        if parameters.cardioSeconds != nil {
            blocks.append("CARDIO\nChiudi ogni giorno con un esercizio di cardio dall'elenco, come ultimo id.")
        }

        blocks.append(
            "CANDIDATI (\(candidates.count) esercizi)\n"
            + "Formato: id|nome|gruppo muscolare|attrezzo|schema motorio|M multiarticolare o I isolamento\n"
            + candidates.compactList
        )

        blocks.append("RISPOSTA\n" + responseShape(days: parameters.days.count))

        return blocks.joined(separator: "\n\n")
    }

    /// Esempio di forma della risposta, più leggibile dello schema per un
    /// modello piccolo (lo schema resta comunque imposto da `response_format`).
    static func responseShape(days: Int) -> String {
        let example = (0..<max(1, days))
            .map { _ in "[\"0025\",\"0031\"]" }
            .joined(separator: ",")
        return """
        {"n":"nome breve della scheda","d":[\(example)]}
        "n" è il nome della scheda. "d" ha esattamente \(days) elenchi di id, uno per giorno, \
        nell'ordine dei giorni qui sopra. Nient'altro: niente numeri, niente nomi, niente note.
        """
    }

    // MARK: - Dimensione

    /// Stima dei token del prompt completo (sistema + utente).
    public static func estimatedTokens(
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> Int {
        GeneratorCandidates.estimateTokens(system)
            + GeneratorCandidates.estimateTokens(user(answers: answers, parameters: parameters, candidates: candidates))
    }

    /// Token in uscita da concedere per quella scheda.
    ///
    /// Un id fra virgolette con la virgola costa 4-5 token; si arrotonda per
    /// eccesso e si lascia spazio al nome, alle parentesi e ai pochi token di
    /// ragionamento dei modelli che non si lasciano spegnere del tutto.
    public static func outputTokenBudget(parameters: GeneratorPlanParameters) -> Int {
        let items = parameters.days.count * (parameters.exercisesPerDay.upperBound + 1)
        return min(OpenRouterClient.defaultMaxTokens, max(600, items * 6 + 200))
    }

    // MARK: - JSON Schema

    /// Nome dello schema, per `response_format: { type: "json_schema" }`.
    public static let schemaName = "gym_program"

    /// Lo JSON Schema della risposta, come stringa.
    ///
    /// Scritto a mano e non generato: deve restare **stabile** (un check lo
    /// verifica), perché è parte del contratto con il servizio di inferenza.
    /// `additionalProperties: false` e `required` completi sono obbligatori per
    /// lo "structured output" stretto di OpenAI e compatibili con OpenRouter.
    ///
    /// Due sole chiavi, di una lettera: `n` il nome della scheda, `d` un elenco
    /// di elenchi di id. Niente `description`, niente `minItems`, niente unioni
    /// con `null`: la modalità stretta dei fornitori limita quali costrutti di
    /// JSON Schema accetta, e più lo schema è banale più fornitori lo applicano
    /// davvero invece di trattarlo come un suggerimento.
    public static let jsonSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["n", "d"],
      "properties": {
        "n": { "type": "string" },
        "d": {
          "type": "array",
          "items": {
            "type": "array",
            "items": { "type": "string" }
          }
        }
      }
    }
    """

    /// Lo schema come oggetto, per comporre il corpo della richiesta.
    public static func jsonSchemaObject() -> [String: Any] {
        guard
            let data = jsonSchema.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }
}
