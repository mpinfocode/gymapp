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
public enum GeneratorPrompt {

    /// Istruzioni di sistema: chi è, cosa fa, cosa non deve fare.
    public static let system = """
    Sei un preparatore atletico esperto di sala pesi. Costruisci schede di allenamento \
    per una palestra commerciale, concrete e sensate, come le scriveresti su carta per \
    un tuo cliente.

    Regole assolute:
    1. Rispondi SOLO con un oggetto JSON valido, senza testo prima o dopo, senza blocchi \
    di codice, senza commenti.
    2. Usa esclusivamente gli id presenti nell'elenco dei candidati. Non inventare id, \
    non inventare esercizi, non usare nomi al posto degli id.
    3. Rispetta alla lettera i numeri che ti vengono dati (giorni, esercizi per giorno, \
    serie, ripetizioni, recuperi): sono già stati calcolati, non sono suggerimenti.
    4. In ogni giorno metti prima i multiarticolari (M) e poi gli isolamenti (I).
    5. Non ripetere lo stesso id due volte nello stesso giorno.
    6. Le note sono in italiano, al massimo 80 caratteri, e servono solo quando dicono \
    qualcosa di utile sull'esecuzione. Non usare mai i trattini lunghi.
    7. Non indicare carichi: li decide la persona in palestra.
    """

    /// Il messaggio utente, costruito dalle risposte.
    public static func user(
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> String {
        var blocks: [String] = []

        blocks.append("PERSONA\n" + answers.summaryLines.map { "- \($0)" }.joined(separator: "\n"))

        var numbers = parameters.summaryLines.map { "- \($0)" }
        numbers.append("- Non indicare carichi.")
        blocks.append("VINCOLI NUMERICI\n" + numbers.joined(separator: "\n"))

        let structure = parameters.days.enumerated().map { index, day -> String in
            let patterns = day.requiredPatterns.map(\.displayName).joined(separator: ", ")
            return "\(index + 1). \"\(day.name)\": \(patterns)"
        }
        blocks.append(
            "STRUTTURA DEI GIORNI (usa questi nomi, in questo ordine)\n"
            + structure.joined(separator: "\n")
            + "\nGli schemi motori elencati sono l'ossatura del giorno: seguili finché ci "
            + "sono candidati adatti, poi completa con quel che serve al giorno."
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
        if let seconds = parameters.cardioSeconds {
            blocks.append(
                "CARDIO\nChiudi ogni giorno con un esercizio di cardio dall'elenco, "
                + "1 serie, \"seconds\": \(seconds), \"rest\": 60."
            )
        }

        blocks.append(
            "CANDIDATI (\(candidates.count) esercizi)\n"
            + "Formato: id|nome|gruppo muscolare|attrezzo|schema motorio|M multiarticolare o I isolamento\n"
            + candidates.compactList
        )

        blocks.append("FORMATO DELLA RISPOSTA\n" + responseShape)

        return blocks.joined(separator: "\n\n")
    }

    /// Esempio di forma della risposta, più leggibile dello schema per un
    /// modello piccolo (lo schema resta comunque imposto da `response_format`).
    static let responseShape = """
    {
      "name": "nome breve della scheda, in italiano",
      "days": [
        {
          "name": "nome del giorno",
          "items": [
            { "id": "0025", "sets": 4, "repsMin": 6, "repsMax": 10, "rest": 120, "note": null }
          ]
        }
      ]
    }
    Per gli esercizi a tempo usa "seconds" al posto di "repsMin" e "repsMax".
    """

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

    // MARK: - JSON Schema

    /// Nome dello schema, per `response_format: { type: "json_schema" }`.
    public static let schemaName = "gym_program"

    /// Lo JSON Schema della risposta, come stringa.
    ///
    /// Scritto a mano e non generato: deve restare **stabile** (un check lo
    /// verifica), perché è parte del contratto con il servizio di inferenza.
    /// `additionalProperties: false` e `required` completi sono obbligatori per
    /// lo "structured output" stretto di OpenAI e compatibili con OpenRouter;
    /// i campi facoltativi si dichiarano come tipo unione con `null`.
    public static let jsonSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "days"],
      "properties": {
        "name": { "type": "string" },
        "days": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["name", "items"],
            "properties": {
              "name": { "type": "string" },
              "items": {
                "type": "array",
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["id", "sets", "repsMin", "repsMax", "seconds", "rest", "note"],
                  "properties": {
                    "id": { "type": "string" },
                    "sets": { "type": "integer" },
                    "repsMin": { "type": ["integer", "null"] },
                    "repsMax": { "type": ["integer", "null"] },
                    "seconds": { "type": ["integer", "null"] },
                    "rest": { "type": "integer" },
                    "note": { "type": ["string", "null"] }
                  }
                }
              }
            }
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
