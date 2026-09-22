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
    3. Metti in ogni giorno ESATTAMENTE il numero di id richiesto: né uno in più né uno \
    in meno. È il vincolo più importante, viene prima di ogni altra preferenza.
    4. Ordine di ogni giorno: prima i multiarticolari (M), poi gli isolamenti (I), poi \
    addome e polpacci, e il cardio per ultimo.
    5. Non ripetere lo stesso id due volte nello stesso giorno.
    6. Due giorni dello stesso tipo (parte alta A e B, spinta A e B, total body A e B) \
    possono avere al massimo due esercizi in comune, e solo se sono fondamentali: per il \
    resto scegli varianti diverse dello stesso schema motorio (lat machine invece di \
    trazioni assistite, spinte con i manubri invece di chest press, pressa invece di squat).
    7. In una settimana ogni gruppo muscolare grande vuole del lavoro diretto: petto, \
    dorso, spalle, quadricipiti, femorali e glutei, e l'addome quando c'è spazio. Nessun \
    gruppo grande deve avere meno della metà degli esercizi del gruppo più allenato.
    8. In ogni giorno di parte alta o total body metti almeno una spinta e almeno una tirata.
    9. Serie, ripetizioni, recuperi, carichi e nomi dei giorni non li scrivi tu: li calcola l'app.
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
        let target = parameters.targetExercisesPerDay
        blocks.append(
            "GIORNI, in questo ordine\n"
            + structure.joined(separator: "\n")
            + "\nESATTAMENTE \(target) id per giorno, in tutti i \(parameters.days.count) giorni "
            + "(in tutto \(parameters.weeklyExerciseBudget) id). "
            + "Gli schemi motori elencati sono l'ossatura del giorno: seguili finché ci sono "
            + "candidati adatti, poi completa fino a \(target) con quel che manca alla settimana."
        )

        if !answers.focusGroups.isEmpty {
            let names = MuscleGroup.displayOrder.filter(answers.focusGroups.contains).map(\.displayName)
            blocks.append(
                "PRIORITÀ\nDai un esercizio in più a settimana a: \(names.joined(separator: ", ")). "
                + "Mettili a inizio seduta, quando si è freschi."
            )
        }
        if !answers.protectedZones.isEmpty {
            let names = StressZone.displayOrder.filter(answers.protectedZones.contains).map(\.displayName)
            var text = "ZONE DA PROTEGGERE\n\(names.joined(separator: ", ")). "
                + "Gli esercizi vietati sono già stati tolti dai candidati."
            if candidates.hasCautionItems {
                text += " Le righe che finiscono con \"|!\" sono ammesse ma delicate per quelle zone: "
                    + "al massimo una per giorno, e mai come primo esercizio."
            }
            blocks.append(text)
        }
        if parameters.cardioSeconds != nil {
            blocks.append(
                "CARDIO\nChiudi ogni giorno con un esercizio di cardio dall'elenco, come ultimo id. "
                + "Conta fra i \(target)."
            )
        }

        blocks.append(
            "CANDIDATI (\(candidates.count) esercizi)\n"
            + "Formato: id|nome|gruppo muscolare|attrezzo|schema motorio|M multiarticolare o I isolamento"
            + (candidates.hasCautionItems ? "|! se delicato per le zone da proteggere" : "")
            + "\n"
            + candidates.compactList
        )

        blocks.append("RISPOSTA\n" + responseShape(days: parameters.days.count, perDay: target))

        return blocks.joined(separator: "\n\n")
    }

    /// Esempio di forma della risposta, più leggibile dello schema per un
    /// modello piccolo (lo schema resta comunque imposto da `response_format`).
    static func responseShape(days: Int, perDay: Int) -> String {
        let example = (0..<max(1, days))
            .map { _ in "[\"0025\",\"0031\"]" }
            .joined(separator: ",")
        return """
        {"n":"nome breve della scheda","d":[\(example)]}
        "d" ha esattamente \(days) elenchi di id, uno per giorno, nell'ordine dei giorni qui \
        sopra, e ogni elenco ha esattamente \(perDay) id. Nient'altro: niente numeri, niente \
        nomi di esercizi, niente note. Il nome della scheda lo decide l'app: "n" mettilo pure, \
        ma non perderci tempo.
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

    /// Token in uscita per quel modello.
    ///
    /// I modelli che ragionano per forza spendono i primi token a pensare, e
    /// quei token stanno **dentro** `max_tokens`: con il budget stretto escono
    /// con `finish_reason: "length"` e il messaggio vuoto, che è esattamente
    /// come è fallita la prima prova reale. A loro si concede il margine.
    public static func outputTokenBudget(parameters: GeneratorPlanParameters, model: String) -> Int {
        let base = outputTokenBudget(parameters: parameters)
        guard OpenRouterClient.recommendedReasoning(forModel: model) != .off else { return base }
        return min(OpenRouterClient.reasoningMaxTokens, base + OpenRouterClient.reasoningHeadroom)
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
