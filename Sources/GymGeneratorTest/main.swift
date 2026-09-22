import Foundation
import GymCore

// Banco di prova del generatore di schede: chiama OpenRouter per davvero con
// gli scenari della batteria e dice, per ogni modello, quanto costa, quanto ci
// mette e se la scheda che produce sta in piedi.
//
//   swift run GymGeneratorTest --fallback                 (senza chiave, solo il generatore deterministico)
//   swift run GymGeneratorTest --fallback --replay        (rivaluta le risposte già salvate, senza chiave)
//   swift run GymGeneratorTest --quick --tier all         (3 scenari, fascia veloce e fascia accurata)
//   swift run GymGeneratorTest --quick                    (3 scenari, sola fascia veloce)
//   swift run GymGeneratorTest                            (tutti gli scenari, fascia veloce)
//   swift run GymGeneratorTest --model google/gemini-2.5-flash --scenario 3g-fullbody
//
// La chiave non viene MAI stampata, salvata o inclusa nei rapporti.
//
// Il rapporto si riscrive dopo OGNI prova: se si interrompe la batteria a metà
// (o se un modello resta appeso) quel che è stato misurato resta su disco.

// MARK: - Argomenti

struct Options {
    var models: [String] = []
    var scenarios: [String] = []
    var tier: ModelPricing.Tier = .fast
    var runs = 1
    var fallbackOnly = false
    var replay = false
    var quick = false
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
        case "--tier":
            guard let raw = value("--tier"), let tier = ModelPricing.Tier(rawValue: raw) else {
                return .invalid("--tier vuole fast, smart o all")
            }
            options.tier = tier
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
        case "--replay":
            options.replay = true
        case "--fallback":
            options.fallbackOnly = true
        case "--quick":
            options.quick = true
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

  --quick            batteria rapida: \(Scenarios.quickNames.count) scenari, meno di un minuto per modello
                     (\(Scenarios.quickNames.joined(separator: ", ")))
  --tier <fascia>    fast (default), smart o all
                     fast:  \(ModelPricing.fastModels.joined(separator: ", "))
                     smart: \(ModelPricing.smartModels.joined(separator: ", "))
  --model <id>       modello OpenRouter da provare, ripetibile
                     (se lo usi, la fascia viene ignorata)
  --scenario <nome>  scenario da provare, ripetibile (default: tutti)
  --runs <n>         ripetizioni per ogni coppia scenario/modello (default 1)
  --fallback         solo il generatore deterministico, senza rete e senza chiave
  --replay           rilegge le risposte grezze già salvate nella cartella di uscita
                     e le rivaluta con le regole di oggi: niente rete, niente chiave
  --pool             stampa la composizione della selezione curata ed esce
  --out <cartella>   dove scrivere rapporto.md e le risposte grezze
                     (default: docs/preview/generator)
  --key-file <path>  file alternativo con la chiave
  --help             questo testo

I modelli si provano dal più veloce. Un modello viene abbandonato dopo due
fallimenti consecutivi dello stesso tipo: non ha senso spenderci altri minuti.

Scenari disponibili:
\(Scenarios.all.map { "  \($0.name.padding(toLength: 24, withPad: " ", startingAt: 0))\($0.title)" }.joined(separator: "\n"))
"""

// MARK: - Esito di una prova

/// Come è andata male, quando è andata male. Serve a fermare un modello che
/// sbaglia sempre allo stesso modo.
enum FailureKind: String, Sendable {
    case none
    case timeout = "tempo scaduto"
    case emptyReasoning = "risposta vuota (ha ragionato)"
    case truncated = "risposta troncata"
    case http = "errore del servizio"
    case network = "rete"
    case unreadable = "risposta illeggibile"
    case invalid = "scheda non valida"
    case noEndpoints = "nessun fornitore con quei vincoli"
    case modelMissing = "modello inesistente"

    static func of(_ failure: OpenRouterClient.Failure) -> FailureKind {
        switch failure {
        case .timeout: .timeout
        case .emptyContentReasoningExhausted, .emptyResponse: .emptyReasoning
        case .truncated: .truncated
        case .transport: .network
        case .malformedResponse: .unreadable
        // Distinti fra loro e da un errore generico: "errore del servizio" non
        // dice niente a chi legge il rapporto il giorno dopo.
        case .noEndpointsForConstraints: .noEndpoints
        case .modelNotFound: .modelMissing
        default: .http
        }
    }
}

struct Attempt {
    let scenario: Scenario
    let model: String
    let run: Int
    let seconds: Double
    let usage: OpenRouterClient.Usage?
    let cost: Double?
    let finishReason: String?
    let provider: String?
    let validation: GeneratorValidation?
    let repairs: [String]
    let quality: QualityReport?
    let draftLines: [String]
    /// La bozza come l'ha consegnata il modello, prima di ogni riparazione.
    let rawDraftLines: [String]
    /// Il voto 0-100 di quella bozza grezza.
    let score: DraftScore?
    /// La scheda finale riga per riga, per chi la deve giudicare a mano.
    var auditLines: [String] = []
    let error: String?
    let failureKind: FailureKind
    let usedSchema: Bool
    /// `true` se l'esito viene dalla rilettura di una risposta salvata: i
    /// secondi non sono stati misurati adesso e non vanno nelle statistiche.
    var isReplay = false

    var succeeded: Bool { error == nil && validation?.isValid == true }
    var isAI: Bool { model != "fallback" }
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
if !options.scenarios.isEmpty {
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
} else if options.quick {
    chosenScenarios = Scenarios.quick
} else {
    chosenScenarios = Scenarios.all
}

print("GymGeneratorTest · \(chosenScenarios.count) scenari\(options.quick ? " (batteria rapida)" : "")")

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
        let home = ofGroup.filter { $0.equipmentClass.rank <= EquipmentClass.dumbbellBench.rank }.count
        let body = ofGroup.filter { $0.equipmentClass == .bodyweightBands }.count
        print("  " + group.displayName.padding(toLength: 15, withPad: " ", startingAt: 0)
            + String(format: "%5d", ofGroup.count)
            + String(format: "%10d", ofGroup.count)
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

let models = ModelPricing.sortedBySpeed(
    options.models.isEmpty ? ModelPricing.models(tier: options.tier) : options.models
)
let client = OpenRouterClient()
var attempts: [Attempt] = []

let reportURL = outputDirectory.appendingPathComponent("rapporto.md")

/// Riscrive il rapporto da zero con quello che si sa finora.
///
/// Si chiama dopo ogni singola prova: una batteria interrotta a metà lascia
/// comunque sul disco tutto quel che ha misurato.
@MainActor
func writeReport() {
    let text = Report.make(attempts: attempts, quick: options.quick, models: models)
    try? text.write(to: reportURL, atomically: true, encoding: .utf8)
}

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
    print("Candidati: \(candidates.count) · prompt stimato: \(promptTokens) token"
        + " · risposta attesa: ~\(Report.expectedReplyTokens(parameters: parameters)) token"
        + " (tetto \(GeneratorPrompt.outputTokenBudget(parameters: parameters)))")
    print(DraftFormatter.lines(draft: draft, candidates: candidates).joined(separator: "\n"))
    print("Validatore: \(validation.isValid ? "valido" : "NON valido")")
    for error in validation.errors { print("  ! \(error)") }
    for warning in validation.warnings { print("  ~ \(warning)") }
    let score = DraftScore.make(
        dayIDs: draft.days.map { $0.items.map(\.id) },
        answers: scenario.answers,
        parameters: parameters,
        candidates: candidates
    )
    print("Qualità:")
    for finding in quality.findings { print("  \(finding.line)") }
    print("Punteggio della bozza: \(score.total)/\(score.maximum)")
    print("Distribuzione muscolare:")
    print(quality.distributionLines.joined(separator: "\n"))

    let lines = DraftFormatter.lines(draft: draft, candidates: candidates)
    attempts.append(
        Attempt(
            scenario: scenario,
            model: "fallback",
            run: 1,
            seconds: 0,
            usage: nil,
            cost: 0,
            finishReason: nil,
            provider: nil,
            validation: validation,
            repairs: [],
            quality: quality,
            draftLines: lines,
            rawDraftLines: lines,
            score: score,
            error: nil,
            failureKind: .none,
            usedSchema: false
        )
    )
}
writeReport()

// MARK: - Rilettura delle risposte già salvate

// `--replay` non chiama nessuno: prende i JSON delle prove precedenti, che sono
// risposte vere di modelli veri, e li fa ripassare dalle regole di oggi. È il
// modo più onesto di mostrare cosa cambia una modifica al validatore o alla
// riparazione: stesso identico ingresso, uscita diversa.
if options.replay {
    print("\n=== Rilettura delle risposte già salvate ===")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path))?
        .filter { $0.hasSuffix(".json") }.sorted() ?? []
    for scenario in chosenScenarios {
        let parameters = GeneratorPlanParameters(answers: scenario.answers)
        let candidates = GeneratorCandidates.make(
            answers: scenario.answers, library: repository, parameters: parameters
        )
        for file in files where file.hasPrefix(scenario.name + "__") {
            let url = outputDirectory.appendingPathComponent(file)
            guard
                let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choice = (object["choices"] as? [[String: Any]])?.first,
                let message = choice["message"] as? [String: Any],
                let text = message["content"] as? String,
                let decoded = try? GeneratedProgramDraft.decode(fromModelOutput: text)
            else {
                print("  (\(file): non contiene una risposta rileggibile)")
                continue
            }
            let stem = file.replacingOccurrences(of: ".json", with: "")
                .replacingOccurrences(of: scenario.name + "__", with: "")
            let parts = stem.split(separator: "_")
            let run = Int(parts.last.map(String.init) ?? "1") ?? 1
            let model = parts.dropLast().joined(separator: "_").replacingOccurrences(of: "_", with: "/")

            let rawIDs = decoded.days.map { $0.items.map(\.id) }
            let score = DraftScore.make(
                dayIDs: rawIDs, answers: scenario.answers, parameters: parameters, candidates: candidates
            )
            let rawLines = DraftFormatter.lines(
                draft: DraftFormatter.hydrate(
                    dayIDs: rawIDs, answers: scenario.answers, parameters: parameters, candidates: candidates
                ),
                candidates: candidates
            )
            let (repaired, repairs) = GeneratorValidator.repair(
                decoded, answers: scenario.answers, parameters: parameters, candidates: candidates
            )
            let validation = GeneratorValidator.validate(
                repaired, answers: scenario.answers, parameters: parameters, candidates: candidates
            )
            let quality = QualityReport.make(
                draft: repaired, answers: scenario.answers, parameters: parameters,
                candidates: candidates, exercisesByID: exercisesByID
            )
            let lines = DraftFormatter.lines(draft: repaired, candidates: candidates)

            print("\n--- \(scenario.name) · \(model) · risposta salvata")
            print("Bozza grezza del modello:")
            print(rawLines.joined(separator: "\n"))
            print("Punteggio della bozza grezza: \(score.total)/\(score.maximum)")
            for part in score.parts { print("  \(part.line)") }
            print("Scheda dopo la riparazione:")
            print(lines.joined(separator: "\n"))
            print("Riparazioni: \(repairs.count)")
            for repair in repairs { print("  · \(repair)") }
            print("Validatore: \(validation.isValid ? "valido" : "NON valido")")
            for error in validation.errors { print("  ! \(error)") }
            for warning in validation.warnings { print("  ~ \(warning)") }

            attempts.append(
                Attempt(
                    scenario: scenario, model: model, run: run, seconds: 0,
                    usage: OpenRouterClient.readUsage(object["usage"]),
                    cost: ModelPricing.cost(model: model, usage: OpenRouterClient.readUsage(object["usage"])),
                    finishReason: (choice["finish_reason"] as? String),
                    provider: object["provider"] as? String,
                    validation: validation, repairs: repairs, quality: quality,
                    draftLines: lines, rawDraftLines: rawLines, score: score,
                    auditLines: DraftFormatter.auditLines(
                        draft: repaired, answers: scenario.answers,
                        parameters: parameters, candidates: candidates
                    ),
                    error: nil, failureKind: validation.isValid ? .none : .invalid, usedSchema: true,
                    isReplay: true
                )
            )
            writeReport()
        }
    }
}

// MARK: - Le chiamate vere

if !options.fallbackOnly, let apiKey {
    for model in models {
        let price = ModelPricing.table[model]
        print("\n=== Modello \(model) ===")
        print("Ragionamento richiesto: \(ModelPricing.reasoningLabel(model))"
            + (price.map { " · ragiona di suo: \($0.reasoning.rawValue) · \($0.note)" } ?? ""))

        // Due fallimenti di fila dello stesso tipo e si passa oltre: un modello
        // che risponde vuoto lo farà anche la terza volta, e ogni tentativo
        // costa fino a 25 secondi di attesa.
        var lastFailure = FailureKind.none
        var consecutive = 0

        scenarioLoop: for scenario in chosenScenarios {
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
                let maxTokens = GeneratorPrompt.outputTokenBudget(parameters: parameters, model: model)
                // La scadenza è quella vera dell'app: 40 secondi in tutto,
                // ripiego sullo schema compreso.
                let deadline = OpenRouterClient.Deadline()

                let started = Date()
                var completion: OpenRouterClient.Completion?
                var failure: String?
                var kind = FailureKind.none
                var usedSchema = true

                do {
                    completion = try await client.complete(
                        system: systemPrompt,
                        user: userPrompt,
                        model: model,
                        apiKey: apiKey.value,
                        maxTokens: maxTokens,
                        deadline: deadline
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
                                responseFormat: .jsonObject,
                                maxTokens: maxTokens,
                                deadline: deadline
                            )
                        } catch let second as OpenRouterClient.Failure {
                            failure = second.description
                            kind = FailureKind.of(second)
                        } catch {
                            failure = "errore inatteso: \(error.localizedDescription)"
                            kind = .http
                        }
                    } else {
                        failure = error.description
                        kind = FailureKind.of(error)
                    }
                } catch {
                    failure = "errore inatteso: \(error.localizedDescription)"
                    kind = .http
                }

                let elapsed = Date().timeIntervalSince(started)
                print("\n--- \(scenario.name) · \(model) · prova \(run)")

                guard let completion else {
                    print(String(format: "Tempo: %.2f s · esito: %@", elapsed, kind.rawValue))
                    print("Errore: \(failure ?? "sconosciuto")")
                    // Anche il fallimento si salva: il messaggio del servizio è
                    // l'unica cosa che dice *perché* un modello non va, e senza
                    // di quello il giorno dopo resta solo "errore del servizio".
                    // Non contiene la chiave: è il testo dell'errore, non la richiesta.
                    let errorURL = outputDirectory.appendingPathComponent(
                        "\(scenario.name)__\(model.replacingOccurrences(of: "/", with: "_"))__\(run).errore.txt"
                    )
                    try? "\(kind.rawValue)\n\(failure ?? "sconosciuto")\n"
                        .write(to: errorURL, atomically: true, encoding: .utf8)
                    attempts.append(
                        Attempt(
                            scenario: scenario, model: model, run: run, seconds: elapsed,
                            usage: nil, cost: nil, finishReason: nil, provider: nil,
                            validation: nil, repairs: [], quality: nil,
                            draftLines: [], rawDraftLines: [], score: nil,
                            error: failure, failureKind: kind, usedSchema: usedSchema
                        )
                    )
                    writeReport()

                    consecutive = kind == lastFailure ? consecutive + 1 : 1
                    lastFailure = kind
                    if consecutive >= 2 {
                        print("\n  Due fallimenti di fila dello stesso tipo (\(kind.rawValue)): si abbandona \(model).")
                        break scenarioLoop
                    }
                    continue
                }

                lastFailure = .none
                consecutive = 0

                let cost = ModelPricing.cost(model: model, usage: completion.usage)
                var line = String(format: "Tempo: %.2f s", elapsed)
                line += " · finish_reason: \(completion.finishReason ?? "non dichiarato")"
                if let usage = completion.usage {
                    line += " · token: \(usage.promptTokens) in, \(usage.completionTokens) out"
                    if usage.reasoningTokens > 0 { line += " (di cui \(usage.reasoningTokens) di ragionamento)" }
                } else {
                    line += " · token non dichiarati"
                }
                line += " · costo \(ModelPricing.formatCost(cost))"
                if let provider = completion.provider { line += " · via \(provider)" }
                print(line)

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
                            usage: completion.usage, cost: cost, finishReason: completion.finishReason,
                            provider: completion.provider, validation: nil, repairs: [],
                            quality: nil, draftLines: [], rawDraftLines: [], score: nil,
                            error: String(describing: error),
                            failureKind: .unreadable, usedSchema: usedSchema
                        )
                    )
                    writeReport()
                    consecutive = lastFailure == .unreadable ? consecutive + 1 : 1
                    lastFailure = .unreadable
                    if consecutive >= 2 {
                        print("\n  Due risposte illeggibili di fila: si abbandona \(model).")
                        break scenarioLoop
                    }
                    continue
                }

                // La bozza GREZZA, prima di qualunque riparazione: è quella
                // su cui si giudica il modello, perché dopo la riparazione le
                // schede sono tutte a posto e si assomigliano tutte.
                let rawIDs = draft.days.map { $0.items.map(\.id) }
                let score = DraftScore.make(
                    dayIDs: rawIDs,
                    answers: scenario.answers,
                    parameters: parameters,
                    candidates: candidates
                )
                let rawLines = DraftFormatter.lines(
                    draft: DraftFormatter.hydrate(
                        dayIDs: rawIDs,
                        answers: scenario.answers,
                        parameters: parameters,
                        candidates: candidates
                    ),
                    candidates: candidates
                )

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

                print("Bozza grezza del modello:")
                print(rawLines.joined(separator: "\n"))
                print("Punteggio della bozza grezza: \(score.total)/\(score.maximum)")
                for part in score.parts { print("  \(part.line)") }
                print("Scheda dopo la riparazione:")
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
                        usage: completion.usage, cost: cost, finishReason: completion.finishReason,
                        provider: completion.provider, validation: validation,
                        repairs: repairs, quality: quality, draftLines: lines,
                        rawDraftLines: rawLines, score: score, error: nil,
                        failureKind: validation.isValid ? .none : .invalid, usedSchema: usedSchema
                    )
                )
                writeReport()

                if !validation.isValid {
                    consecutive = lastFailure == .invalid ? consecutive + 1 : 1
                    lastFailure = .invalid
                    if consecutive >= 2 {
                        print("\n  Due schede non valide di fila: si abbandona \(model).")
                        break scenarioLoop
                    }
                }
            }
        }
    }
}

// MARK: - Riepilogo

let summary = Report.make(attempts: attempts, quick: options.quick, models: models)
try? summary.write(to: reportURL, atomically: true, encoding: .utf8)

print("\n" + Report.consoleSummary(attempts: attempts, models: models))
print("\nRapporto: \(reportURL.path)")

let failed = attempts.filter { $0.error != nil || $0.validation?.isValid == false }
if failed.isEmpty {
    print("Tutte le prove hanno prodotto una scheda valida.")
} else {
    print("\(failed.count) prove su \(attempts.count) non hanno prodotto una scheda valida.")
}
exit(0)

extension String {
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
}
