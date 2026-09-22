import Foundation
import GymCore

/// Il rapporto della batteria di prova.
///
/// Si ricostruisce da zero a ogni chiamata, a partire dalle prove fatte finora:
/// costa niente (sono decine di righe) e rende l'interruzione innocua. Chi lancia
/// la batteria e la ferma a metà trova su disco tutto quel che era già misurato.
///
/// - Important: non contiene la chiave, e nemmeno la richiesta che la porta.
enum Report {

    // MARK: - Tempi per modello

    /// Quanto ci mette un modello: mediana e massimo, sulle sole chiamate vere.
    struct Timing {
        let model: String
        let seconds: [Double]
        let succeeded: Int
        let failed: Int
        /// Costi delle sole chiamate che hanno prodotto una scheda.
        let costs: [Double]
        /// Punteggi 0-100 delle bozze grezze.
        let scores: [Int]
        /// Quante riparazioni sono servite, prova per prova.
        let repairCounts: [Int]

        var averageCost: Double? {
            guard !costs.isEmpty else { return nil }
            return costs.reduce(0, +) / Double(costs.count)
        }

        /// Il verdetto del PM sul prezzo: una scheda sta in un centesimo?
        var withinCostCeiling: Bool? {
            guard let averageCost else { return nil }
            return averageCost <= ModelPricing.costCeiling
        }

        var averageScore: Int? {
            guard !scores.isEmpty else { return nil }
            return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        }

        var averageRepairs: Double? {
            guard !repairCounts.isEmpty else { return nil }
            return Double(repairCounts.reduce(0, +)) / Double(repairCounts.count)
        }

        var median: Double {
            guard !seconds.isEmpty else { return 0 }
            let sorted = seconds.sorted()
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }

        var worst: Double { seconds.max() ?? 0 }

        /// Il verdetto che interessa al PM: la mediana sta nei 15 secondi?
        var withinComfort: Bool {
            !seconds.isEmpty && median <= OpenRouterClient.comfortableSeconds
        }

        /// Nessuna chiamata ha sforato il tetto rigido.
        var withinBudget: Bool {
            !seconds.isEmpty && worst <= OpenRouterClient.totalBudget
        }
    }

    static func timings(attempts: [Attempt], models: [String]) -> [Timing] {
        models.compactMap { model in
            let ofModel = attempts.filter { $0.model == model }
            guard !ofModel.isEmpty else { return nil }
            let good = ofModel.filter { $0.error == nil }
            return Timing(
                model: model,
                // Le riletture non hanno un tempo: sono risposte già salvate.
                seconds: good.filter { !$0.isReplay }.map(\.seconds),
                succeeded: ofModel.filter(\.succeeded).count,
                failed: ofModel.filter { !$0.succeeded }.count,
                costs: good.compactMap(\.cost),
                scores: good.compactMap { $0.score?.total },
                repairCounts: good.map { $0.repairs.count }
            )
        }
    }

    /// Stima dei token della risposta compatta per quella scheda.
    static func expectedReplyTokens(parameters: GeneratorPlanParameters) -> Int {
        let items = parameters.days.count * parameters.targetExercisesPerDay
        // `"0025",` sono circa 5 token; il resto è il nome e le parentesi.
        return items * 5 + 25
    }

    // MARK: - Tabelle

    static func attemptRows(_ attempts: [Attempt]) -> [String] {
        var rows = [
            "scenario".padding(toLength: 26, withPad: " ", startingAt: 0)
                + "modello".padding(toLength: 32, withPad: " ", startingAt: 0)
                + "esito".padding(toLength: 26, withPad: " ", startingAt: 0)
                + "fine".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "in".padding(toLength: 7, withPad: " ", startingAt: 0)
                + "out".padding(toLength: 7, withPad: " ", startingAt: 0)
                + "ragion.".padding(toLength: 9, withPad: " ", startingAt: 0)
                + "costo".padding(toLength: 12, withPad: " ", startingAt: 0)
                + "secondi".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "qualità".padding(toLength: 9, withPad: " ", startingAt: 0)
                + "ripar.",
        ]
        for attempt in attempts {
            let outcome: String
            if attempt.error != nil {
                outcome = attempt.failureKind.rawValue
            } else if attempt.validation?.isValid == true {
                outcome = attempt.repairs.isEmpty ? "valida" : "valida (\(attempt.repairs.count) ripar.)"
            } else {
                outcome = "scheda non valida"
            }
            rows.append(
                attempt.scenario.name.padding(toLength: 26, withPad: " ", startingAt: 0)
                    + attempt.model.padding(toLength: 32, withPad: " ", startingAt: 0)
                    + outcome.padding(toLength: 26, withPad: " ", startingAt: 0)
                    + (attempt.finishReason ?? "-").padding(toLength: 10, withPad: " ", startingAt: 0)
                    + String(attempt.usage?.promptTokens ?? 0).padding(toLength: 7, withPad: " ", startingAt: 0)
                    + String(attempt.usage?.completionTokens ?? 0).padding(toLength: 7, withPad: " ", startingAt: 0)
                    + String(attempt.usage?.reasoningTokens ?? 0).padding(toLength: 9, withPad: " ", startingAt: 0)
                    + ModelPricing.formatCost(attempt.cost).padding(toLength: 12, withPad: " ", startingAt: 0)
                    + (attempt.isReplay ? "rilettura" : String(format: "%.2f", attempt.seconds))
                        .padding(toLength: 10, withPad: " ", startingAt: 0)
                    + (attempt.score.map { "\($0.total)/100" } ?? "-").padding(toLength: 9, withPad: " ", startingAt: 0)
                    + (attempt.error == nil ? String(attempt.repairs.count) : "-")
            )
        }
        return rows
    }

    /// La tabella che decide: costo, tempo e qualità della bozza grezza.
    ///
    /// Sono le tre cose che servono a scegliere un modello, e nient'altro:
    /// quanto costa una scheda, quanto aspetta l'utente, e quanto era già
    /// giusta la bozza prima che il telefono la sistemasse.
    static func verdictRows(attempts: [Attempt], models: [String]) -> [String] {
        var rows = [
            "modello".padding(toLength: 32, withPad: " ", startingAt: 0)
                + "valide".padding(toLength: 8, withPad: " ", startingAt: 0)
                + "fallite".padding(toLength: 9, withPad: " ", startingAt: 0)
                + "costo medio".padding(toLength: 13, withPad: " ", startingAt: 0)
                + "entro 0,01 $".padding(toLength: 14, withPad: " ", startingAt: 0)
                + "mediana".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "massimo".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "entro \(Int(OpenRouterClient.comfortableSeconds)) s".padding(toLength: 12, withPad: " ", startingAt: 0)
                + "qualità".padding(toLength: 9, withPad: " ", startingAt: 0)
                + "riparazioni",
        ]
        for timing in timings(attempts: attempts, models: models) {
            var verdict = timing.withinComfort ? "sì" : "no"
            if timing.seconds.isEmpty { verdict = "n/d" }
            else if !timing.withinBudget { verdict += " (oltre \(Int(OpenRouterClient.totalBudget)) s)" }
            let cost = timing.averageCost.map { String(format: "$%.5f", $0) } ?? "n/d"
            let withinCost = timing.withinCostCeiling.map { $0 ? "sì" : "no" } ?? "n/d"
            rows.append(
                timing.model.padding(toLength: 32, withPad: " ", startingAt: 0)
                    + String(timing.succeeded).padding(toLength: 8, withPad: " ", startingAt: 0)
                    + String(timing.failed).padding(toLength: 9, withPad: " ", startingAt: 0)
                    + cost.padding(toLength: 13, withPad: " ", startingAt: 0)
                    + withinCost.padding(toLength: 14, withPad: " ", startingAt: 0)
                    + (timing.seconds.isEmpty ? "n/d" : String(format: "%.2f s", timing.median))
                        .padding(toLength: 10, withPad: " ", startingAt: 0)
                    + (timing.seconds.isEmpty ? "n/d" : String(format: "%.2f s", timing.worst))
                        .padding(toLength: 10, withPad: " ", startingAt: 0)
                    + verdict.padding(toLength: 12, withPad: " ", startingAt: 0)
                    + (timing.averageScore.map { "\($0)/100" } ?? "n/d").padding(toLength: 9, withPad: " ", startingAt: 0)
                    + (timing.averageRepairs.map { String(format: "%.1f", $0) } ?? "n/d")
            )
        }
        return rows
    }

    // MARK: - Uscite

    /// Il riepilogo stampato a schermo alla fine.
    static func consoleSummary(attempts: [Attempt], models: [String]) -> String {
        var lines = ["=== Riepilogo ===", ""]
        lines += attemptRows(attempts)
        let verdicts = verdictRows(attempts: attempts, models: models)
        if verdicts.count > 1 {
            lines += ["", "=== Verdetto per modello ===", ""]
            lines += verdicts
        }
        return lines.joined(separator: "\n")
    }

    /// Il rapporto completo su file.
    static func make(attempts: [Attempt], quick: Bool, models: [String]) -> String {
        var report = """
        # Prova del generatore di schede

        Eseguito il \(ISO8601DateFormatter().string(from: Date()))\(quick ? " con la batteria rapida" : "").
        Prezzi dei modelli indicativi (vedi `ModelPricing`), ricontrollati su openrouter.ai il 22/09/2026.
        La chiave OpenRouter non compare in questo file né nei JSON salvati.
        Questo file viene riscritto dopo ogni prova: se la batteria si interrompe, quel che c'è è già buono.

        ## Riepilogo

        ```
        \(attemptRows(attempts).joined(separator: "\n"))
        ```

        """

        let verdicts = verdictRows(attempts: attempts, models: models)
        if verdicts.count > 1 {
            report += """

            ## Verdetto per modello

            Obiettivi: costo medio entro $0,01 a scheda, mediana entro \
            \(Int(OpenRouterClient.comfortableSeconds)) secondi, nessuna chiamata oltre \
            \(Int(OpenRouterClient.totalBudget)) secondi (oltre quel tetto l'app propone la scheda senza AI).

            La colonna **qualità** è il voto da 0 a 100 della bozza **grezza**, quella che il modello \
            ha consegnato prima di ogni riparazione: numero di esercizi giusto, zone protette rispettate \
            senza aiuto, varietà fra giorni gemelli, copertura, equilibrio, adeguatezza a livello e \
            attrezzatura, ordine della seduta. La colonna **riparazioni** dice quanti interventi ha \
            dovuto fare il telefono per rendere quella bozza presentabile.

            ```
            \(verdicts.joined(separator: "\n"))
            ```

            """
        }

        for attempt in attempts {
            report += "\n## \(attempt.scenario.name) · \(attempt.model) · prova \(attempt.run)\n\n"
            report += "\(attempt.scenario.title)\n\n"
            if attempt.isAI {
                var facts = [String(format: "%.2f s", attempt.seconds)]
                facts.append("finish_reason: \(attempt.finishReason ?? "non dichiarato")")
                if let usage = attempt.usage {
                    facts.append("\(usage.promptTokens) token in entrata")
                    facts.append("\(usage.completionTokens) in uscita")
                    if usage.reasoningTokens > 0 { facts.append("\(usage.reasoningTokens) di ragionamento") }
                }
                facts.append("costo \(ModelPricing.formatCost(attempt.cost))")
                if let provider = attempt.provider { facts.append("via \(provider)") }
                if !attempt.usedSchema { facts.append("schema stretto rifiutato, letto con json_object") }
                report += facts.joined(separator: " · ") + "\n\n"
            }
            if let error = attempt.error {
                report += "Errore (\(attempt.failureKind.rawValue)): \(error)\n"
                continue
            }
            if attempt.isAI, attempt.rawDraftLines != attempt.draftLines {
                report += "Bozza grezza del modello\n\n"
                report += "```\n\(attempt.rawDraftLines.joined(separator: "\n"))\n```\n\n"
                report += "Scheda dopo la riparazione\n\n"
            }
            report += "```\n\(attempt.draftLines.joined(separator: "\n"))\n```\n\n"
            if let score = attempt.score {
                report += "Punteggio della bozza grezza: **\(score.total)/\(score.maximum)**\n\n"
                for part in score.parts { report += "- \(part.line)\n" }
                report += "\n"
            }
            if let validation = attempt.validation {
                report += "Validatore: \(validation.isValid ? "valido" : "NON valido")\n\n"
                for error in validation.errors { report += "- errore: \(error)\n" }
                for warning in validation.warnings { report += "- rilievo: \(warning)\n" }
            }
            report += "Riparazioni: \(attempt.repairs.count)\n"
            for repair in attempt.repairs { report += "- riparazione: \(repair)\n" }
            if let quality = attempt.quality {
                report += "\n"
                for finding in quality.findings { report += "- \(finding.line)\n" }
                report += "\n```\n\(quality.distributionLines.joined(separator: "\n"))\n```\n"
            }
        }
        return report
    }
}
