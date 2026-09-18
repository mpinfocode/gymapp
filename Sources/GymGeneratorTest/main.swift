import Foundation
import GymCore

// Banco di prova del generatore di schede: chiama OpenRouter per davvero con
// gli scenari della batteria e dice, per ogni modello, quanto costa, quanto ci
// mette e se la scheda che produce sta in piedi.
//
//   swift run GymGeneratorTest --fallback                 (senza chiave, solo il generatore deterministico)
//   swift run GymGeneratorTest                            (tutti gli scenari, modelli di default)
//   swift run GymGeneratorTest --model openai/gpt-5-nano --scenario 3g-ppl-intermedio
//
// La chiave non viene MAI stampata, salvata o inclusa nei rapporti.

// MARK: - Argomenti

struct Options {
    var models: [String] = []
    var scenarios: [String] = []
    var runs = 1
    var fallbackOnly = false
    var outputDirectory: String?
    var keyFile: String?
    var showPool = false
    var help = false
}

enum OptionParsing {
    case parsed(Options)
    case invalid(String)
}

func parseOptions(_ arguments: [String]) -> OptionParsing {
    var options = Options()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        func value(_ name: String) -> String? {
            index += 1
            guard index < arguments.count else { return nil }
            return arguments[index]
        }
        switch argument {
        case "--model":
            guard let model = value("--model") else { return .invalid("--model vuole un identificativo") }
            options.models.append(model)
        case "--scenario":
            guard let scenario = value("--scenario") else { return .invalid("--scenario vuole un nome") }
            options.scenarios.append(scenario)
        case "--runs":
            guard let raw = value("--runs"), let count = Int(raw), count > 0 else {
                return .invalid("--runs vuole un numero maggiore di zero")
            }
            options.runs = count
        case "--out":
            guard let path = value("--out") else { return .invalid("--out vuole una cartella") }
            options.outputDirectory = path
        case "--key-file":
            guard let path = value("--key-file") else { return .invalid("--key-file vuole un percorso") }
            options.keyFile = path
        case "--fallback":
            options.fallbackOnly = true
        case "--pool":
            options.showPool = true
        case "--help", "-h":
            options.help = true
        default:
            return .invalid("argomento sconosciuto: \(argument)")
        }
        index += 1
    }
    return .parsed(options)
}

let usage = """
GymGeneratorTest · banco di prova del generatore di schede

  --model <id>       modello OpenRouter da provare, ripetibile
                     (default: \(ModelPricing.defaultModels.joined(separator: ", ")))
  --scenario <nome>  scenario da provare, ripetibile (default: tutti)
  --runs <n>         ripetizioni per ogni coppia scenario/modello (default 1)
  --fallback         solo il generatore deterministico, senza rete e senza chiave
  --pool             stampa la composizione della selezione curata ed esce
  --out <cartella>   dove scrivere rapporto.md e le risposte grezze
                     (default: docs/preview/generator)
  --key-file <path>  file alternativo con la chiave
  --help             questo testo

Scenari disponibili:
\(Scenarios.all.map { "  \($0.name.padding(toLength: 24, withPad: " ", startingAt: 0))\($0.title)" }.joined(separator: "\n"))
"""

// MARK: - Esito di una prova

struct Attempt {
    let scenario: Scenario
    let model: String
    let run: Int
    let seconds: Double
    let usage: OpenRouterClient.Usage?
    let cost: Double?
    let validation: GeneratorValidation?
    let repairs: [String]
    let quality: QualityReport?
    let draftLines: [String]
    let error: String?
    let usedSchema: Bool

    var succeeded: Bool { error == nil && validation?.isValid == true }
}

// MARK: - Avvio

let options: Options
switch parseOptions(Array(CommandLine.arguments.dropFirst())) {
case .parsed(let parsed): options = parsed
case .invalid(let message):
    print("Errore: \(message)\n")
    print(usage)
    exit(2)
}

if options.help {
    print(usage)
    exit(0)
}

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = URL(
    fileURLWithPath: (options.outputDirectory ?? "docs/preview/generator" as String).expandingTilde,
    relativeTo: repositoryRoot
).standardizedFileURL
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let chosenScenarios: [Scenario]
if options.scenarios.isEmpty {
    chosenScenarios = Scenarios.all
} else {
    var collected: [Scenario] = []
    for name in options.scenarios {
        guard let scenario = Scenarios.named(name) else {
            print("Scenario sconosciuto: \(name)")
            print("Disponibili: \(Scenarios.all.map(\.name).joined(separator: ", "))")
            exit(2)
        }
        collected.append(scenario)
    }
    chosenScenarios = collected
}

print("GymGeneratorTest · \(chosenScenarios.count) scenari")

let repository: ExerciseRepository
do {
    repository = try await ExerciseRepository.loadFromBundle()
} catch {
    print("Non si riesce a caricare la libreria esercizi: \(error)")
    exit(1)
}
let exercisesByID = repository.exercisesByID()
print("Libreria: \(repository.count) esercizi · selezione curata: \(CuratedExercisePool.count)")

if options.showPool {
    let resolved = CuratedExercisePool.resolved(in: repository)
    print("\nPer gruppo muscolare (totale, e quanti restano con ogni attrezzatura):")
    print("  gruppo         totale  palestra  manubri+panca  corpo libero")
    for group in MuscleGroup.displayOrder where group != .other {
        let ofGroup = resolved.filter { $0.group == group }
        guard !ofGroup.isEmpty else { continue }
        let gym = ofGroup.count
        let home = ofGroup.filter { $0.equipmentClass.rank <= EquipmentClass.dumbbellBench.rank }.count
        let body = ofGroup.filter { $0.equipmentClass == .bodyweightBands }.count
        print("  " + group.displayName.padding(toLength: 15, withPad: " ", startingAt: 0)
            + String(format: "%5d", ofGroup.count)
            + String(format: "%10d", gym)
            + String(format: "%15d", home)
            + String(format: "%14d", body))
    }
    print("\nPer classe di attrezzatura (minima richiesta):")
    for equipmentClass in EquipmentClass.allCases {
        print("  \(equipmentClass.displayName): \(resolved.filter { $0.equipmentClass == equipmentClass }.count)")
    }
    print("\nPer schema motorio:")
    for pattern in MovementPattern.allCases {
        print("  " + pattern.displayName.padding(toLength: 24, withPad: " ", startingAt: 0)
            + String(format: "%3d", resolved.filter { $0.pattern == pattern }.count))
    }
    print("\nPer livello: "
        + TrainingLevel.allCases.map { level in
            "\(level.displayName) \(resolved.filter { $0.level == level }.count)"
        }.joined(separator: " · "))
    exit(0)
}

// La chiave: si cerca solo se serve davvero.
var apiKey: APIKey?
if !options.fallbackOnly {
    let outcome = APIKeyLookup.find(filePath: options.keyFile, repositoryRoot: repositoryRoot)
    for warning in outcome.warnings { print("Attenzione: \(warning)") }
    apiKey = outcome.key
    if let apiKey {
        print("Chiave: trovata (\(apiKey.origin.displayName))")
    } else {
        print("Chiave: assente\n")
        print(APIKeyLookup.missingKeyHelp)
        exit(1)
    }
}

let models = options.models.isEmpty ? ModelPricing.defaultModels : options.models
let client = OpenRouterClient()
var attempts: [Attempt] = []

// MARK: - Il generatore deterministico, sempre

print("\n=== Generatore deterministico (nessuna AI) ===")
for scenario in chosenScenarios {
    let parameters = GeneratorPlanParameters(answers: scenario.answers)
    let candidates = GeneratorCandidates.make(
        answers: scenario.answers,
        library: repository,
        parameters: parameters
    )
    let draft = FallbackProgramGenerator.makeDraft(
        answers: scenario.answers,
        parameters: parameters,
        candidates: candidates
    )
    let validation = GeneratorValidator.validate(
        draft,
        answers: scenario.answers,
        parameters: parameters,
        candidates: candidates
    )
    let quality = QualityReport.make(
        draft: draft,
        answers: scenario.answers,
        parameters: parameters,
        candidates: candidates,
        exercisesByID: exercisesByID
    )
    let promptTokens = GeneratorPrompt.estimatedTokens(
        answers: scenario.answers,
        parameters: parameters,
        candidates: candidates
    )

    print("\n--- \(scenario.name): \(scenario.title)")
    print("Candidati: \(candidates.count) · prompt stimato: \(promptTokens) token")
    print(DraftFormatter.lines(draft: draft, candidates: candidates).joined(separator: "\n"))
    print("Validatore: \(validation.isValid ? "valido" : "NON valido")")
    for error in validation.errors { print("  ! \(error)") }
    for warning in validation.warnings { print("  ~ \(warning)") }
    print("Qualità:")
    for finding in quality.findings { print("  \(finding.line)") }
    print("Distribuzione muscolare:")
    print(quality.distributionLines.joined(separator: "\n"))

    attempts.append(
        Attempt(
            scenario: scenario,
            model: "fallback",
            run: 1,
            seconds: 0,
            usage: nil,
            cost: 0,
            validation: validation,
            repairs: [],
            quality: quality,
            draftLines: DraftFormatter.lines(draft: draft, candidates: candidates),
            error: nil,
            usedSchema: false
        )
    )
}

// MARK: - Le chiamate vere

if !options.fallbackOnly, let apiKey {
    for model in models {
        print("\n=== Modello \(model) ===")
        for scenario in chosenScenarios {
            for run in 1...options.runs {
                let parameters = GeneratorPlanParameters(answers: scenario.answers)
                let candidates = GeneratorCandidates.make(
                    answers: scenario.answers,
                    library: repository,
                    parameters: parameters
                )
                let systemPrompt = GeneratorPrompt.system
                let userPrompt = GeneratorPrompt.user(
                    answers: scenario.answers,
                    parameters: parameters,
                    candidates: candidates
                )

                let started = Date()
                var completion: OpenRouterClient.Completion?
                var failure: String?
                var usedSchema = true

                do {
                    completion = try await client.complete(
                        system: systemPrompt,
                        user: userPrompt,
                        model: model,
                        apiKey: apiKey.value
                    )
                } catch let error as OpenRouterClient.Failure {
                    if OpenRouterClient.shouldRetryWithoutSchema(error) {
                        usedSchema = false
                        print("  (il modello non accetta lo schema stretto, si riprova con json_object)")
                        do {
                            completion = try await client.complete(
                                system: systemPrompt,
                                user: userPrompt,
                                model: model,
                                apiKey: apiKey.value,
                                responseFormat: .jsonObject
                            )
                        } catch {
                            failure = String(describing: error)
                        }
                    } else {
                        failure = error.description
                    }
                } catch {
                    failure = "errore inatteso: \(error.localizedDescription)"
                }

                let elapsed = Date().timeIntervalSince(started)
                let label = "\(scenario.name) · \(model) · prova \(run)"
                print("\n--- \(label)")
                print(String(format: "Tempo: %.2f s", elapsed))

                guard let completion else {
                    print("Errore: \(failure ?? "sconosciuto")")
                    attempts.append(
                        Attempt(
                            scenario: scenario, model: model, run: run, seconds: elapsed,
                            usage: nil, cost: nil, validation: nil, repairs: [], quality: nil,
                            draftLines: [], error: failure, usedSchema: usedSchema
                        )
                    )
                    continue
                }

                let cost = ModelPricing.cost(model: model, usage: completion.usage)
                if let usage = completion.usage {
                    print("Token: \(usage.promptTokens) in, \(usage.completionTokens) out · costo stimato \(ModelPricing.formatCost(cost))")
                } else {
                    print("Token: non dichiarati")
                }

                // La risposta grezza si salva: non contiene la chiave, solo il JSON.
                let rawURL = outputDirectory.appendingPathComponent(
                    "\(scenario.name)__\(model.replacingOccurrences(of: "/", with: "_"))__\(run).json"
                )
                try? completion.rawBody.write(to: rawURL, atomically: true, encoding: .utf8)

                let draft: GeneratedProgramDraft
                do {
                    draft = try GeneratedProgramDraft.decode(fromModelOutput: completion.text)
                } catch {
                    print("Errore: \(error)")
                    attempts.append(
                        Attempt(
                            scenario: scenario, model: model, run: run, seconds: elapsed,
                            usage: completion.usage, cost: cost, validation: nil, repairs: [],
                            quality: nil, draftLines: [], error: String(describing: error),
                            usedSchema: usedSchema
                        )
                    )
                    continue
                }

                let (repaired, repairs) = GeneratorValidator.repair(
                    draft,
                    answers: scenario.answers,
                    parameters: parameters,
                    candidates: candidates
                )
                let validation = GeneratorValidator.validate(
                    repaired,
                    answers: scenario.answers,
                    parameters: parameters,
                    candidates: candidates
                )
                let quality = QualityReport.make(
                    draft: repaired,
                    answers: scenario.answers,
                    parameters: parameters,
                    candidates: candidates,
                    exercisesByID: exercisesByID
                )
                let lines = DraftFormatter.lines(draft: repaired, candidates: candidates)

                print(lines.joined(separator: "\n"))
                print("Riparazioni: \(repairs.isEmpty ? "nessuna" : String(repairs.count))")
                for repair in repairs { print("  · \(repair)") }
                print("Validatore: \(validation.isValid ? "valido" : "NON valido")")
                for error in validation.errors { print("  ! \(error)") }
                for warning in validation.warnings { print("  ~ \(warning)") }
                print("Qualità:")
                for finding in quality.findings { print("  \(finding.line)") }
                print("Distribuzione muscolare:")
                print(quality.distributionLines.joined(separator: "\n"))

                attempts.append(
                    Attempt(
                        scenario: scenario, model: model, run: run, seconds: elapsed,
                        usage: completion.usage, cost: cost, validation: validation,
                        repairs: repairs, quality: quality, draftLines: lines, error: nil,
                        usedSchema: usedSchema
                    )
                )
            }
        }
    }
}

// MARK: - Riepilogo

print("\n=== Riepilogo ===")
let header = "scenario".padding(toLength: 26, withPad: " ", startingAt: 0)
    + "modello".padding(toLength: 30, withPad: " ", startingAt: 0)
    + "valida  ripar.  costo       secondi"
print(header)
var summaryRows: [String] = [header]
for attempt in attempts {
    let valid: String
    if attempt.error != nil {
        valid = "errore"
    } else {
        valid = attempt.validation?.isValid == true ? "sì" : "no"
    }
    let row = attempt.scenario.name.padding(toLength: 26, withPad: " ", startingAt: 0)
        + attempt.model.padding(toLength: 30, withPad: " ", startingAt: 0)
        + valid.padding(toLength: 8, withPad: " ", startingAt: 0)
        + String(attempt.repairs.count).padding(toLength: 8, withPad: " ", startingAt: 0)
        + ModelPricing.formatCost(attempt.cost).padding(toLength: 12, withPad: " ", startingAt: 0)
        + String(format: "%.2f", attempt.seconds)
    print(row)
    summaryRows.append(row)
}

// Rapporto su file
var report = """
# Prova del generatore di schede

Eseguito il \(ISO8601DateFormatter().string(from: Date())).
Prezzi dei modelli indicativi (vedi `ModelPricing`).
La chiave OpenRouter non compare in questo file né nei JSON salvati.

## Riepilogo

```
\(summaryRows.joined(separator: "\n"))
```

"""
for attempt in attempts {
    report += "\n## \(attempt.scenario.name) · \(attempt.model) · prova \(attempt.run)\n\n"
    report += "\(attempt.scenario.title)\n\n"
    if let error = attempt.error {
        report += "Errore: \(error)\n"
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

let reportURL = outputDirectory.appendingPathComponent("rapporto.md")
try? report.write(to: reportURL, atomically: true, encoding: .utf8)
print("\nRapporto: \(reportURL.path)")

let failed = attempts.filter { $0.error != nil || $0.validation?.isValid == false }
if failed.isEmpty {
    print("Tutte le prove hanno prodotto una scheda valida.")
    exit(0)
}
print("\(failed.count) prove su \(attempts.count) non hanno prodotto una scheda valida.")
exit(0)

extension String {
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
}
