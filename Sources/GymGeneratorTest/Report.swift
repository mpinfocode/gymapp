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
            return Timing(
                model: model,
                seconds: ofModel.filter { $0.error == nil }.map(\.seconds),
                succeeded: ofModel.filter(\.succeeded).count,
                failed: ofModel.filter { !$0.succeeded }.count
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
                + "secondi",
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
                    + String(format: "%.2f", attempt.seconds)
            )
        }
        return rows
    }

    /// La tabella che decide: mediana, massimo e verdetto per ogni modello.
    static func verdictRows(attempts: [Attempt], models: [String]) -> [String] {
        var rows = [
            "modello".padding(toLength: 32, withPad: " ", startingAt: 0)
                + "valide".padding(toLength: 9, withPad: " ", startingAt: 0)
                + "fallite".padding(toLength: 9, withPad: " ", startingAt: 0)
                + "mediana".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "massimo".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "entro \(Int(OpenRouterClient.comfortableSeconds)) s",
        ]
        for timing in timings(attempts: attempts, models: models) {
            var verdict = timing.withinComfort ? "sì" : "no"
            if timing.seconds.isEmpty { verdict = "mai risposto" }
            else if !timing.withinBudget { verdict += " (oltre il tetto di \(Int(OpenRouterClient.totalBudget)) s)" }
            rows.append(
                timing.model.padding(toLength: 32, withPad: " ", startingAt: 0)
                    + String(timing.succeeded).padding(toLength: 9, withPad: " ", startingAt: 0)
                    + String(timing.failed).padding(toLength: 9, withPad: " ", startingAt: 0)
                    + String(format: "%.2f s", timing.median).padding(toLength: 10, withPad: " ", startingAt: 0)
                    + String(format: "%.2f s", timing.worst).padding(toLength: 10, withPad: " ", startingAt: 0)
                    + verdict
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
            lines += ["", "=== Tempi per modello ===", ""]
            lines += verdicts
        }
        return lines.joined(separator: "\n")
    }

    /// Il rapporto completo su file.
    static func make(attempts: [Attempt], quick: Bool, models: [String]) -> String {
        var report = """
        # Prova del generatore di schede

        Eseguito il \(ISO8601DateFormatter().string(from: Date()))\(quick ? " con la batteria rapida" : "").
        Prezzi dei modelli indicativi (vedi `ModelPricing`), letti da OpenRouter il 18/09/2026.
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

            ## Tempi per modello

            Obiettivo: mediana entro \(Int(OpenRouterClient.comfortableSeconds)) secondi, nessuna chiamata oltre \
            \(Int(OpenRouterClient.totalBudget)) secondi (oltre quel tetto l'app propone la scheda senza AI).

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
            report += "```\n\(attempt.draftLines.joined(separator: "\n"))\n```\n\n"
            if let validation = attempt.validation {
                report += "Validatore: \(validation.isValid ? "valido" : "NON valido")\n\n"
                for error in validation.errors { report += "- errore: \(error)\n" }
                for warning in validation.warnings { report += "- rilievo: \(warning)\n" }
            }
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
