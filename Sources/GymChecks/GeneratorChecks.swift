import Foundation
import GymCore

/// Verifica il motore di generazione: candidati, scheda di riserva, prompt,
/// validatore, riparazione e conversione in ``Program``.
///
/// La parte grossa è un prodotto cartesiano su tutte le risposte ragionevoli del
/// wizard: giorni × divisioni ammesse × esperienza × attrezzatura × tempo, con e
/// senza priorità e zone da proteggere. Se una sola di queste combinazioni non
/// produce una scheda valida, l'utente si troverebbe davanti un errore: meglio
/// scoprirlo qui.
@MainActor
func runGeneratorChecks(_ harness: Harness, repository: ExerciseRepository?) {
    guard let repository else {
        harness.section("generatore")
        harness.fail("repository non caricato")
        return
    }
    runGeneratorCombinationChecks(harness, repository: repository)
    runGeneratorValidatorChecks(harness, repository: repository)
    runGeneratorSchemaChecks(harness)
}

/// Le varianti di risposta aggiunte a ogni combinazione base.
private enum AnswerVariant: CaseIterable {
    case plain
    case focus
    case protectAll
    case cardio

    var label: String {
        switch self {
        case .plain: "base"
        case .focus: "con priorità"
        case .protectAll: "con zone protette"
        case .cardio: "con cardio"
        }
    }

    var focusGroups: Set<MuscleGroup> {
        self == .focus ? [.glutes, .quads] : []
    }

    var protectedZones: Set<StressZone> {
        self == .protectAll ? [.shoulders, .lowerBack, .knees, .wristsElbows] : []
    }

    var includeCardio: Bool { self == .cardio }
}

@MainActor
private func runGeneratorCombinationChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · combinazioni")

    var combinations = 0
    var emptyPatterns: [String] = []
    var invalidFallbacks: [String] = []
    var oversizedPrompts: [String] = []
    var thinDays: [String] = []
    var maxTokens = 0
    var minCandidates = Int.max
    var maxCandidates = 0

    let promptLimit = 3_500

    for days in GeneratorAnswers.daysRange {
        for split in GeneratorAnswers.availableSplits(forDays: days) {
            for experience in TrainingExperience.allCases {
                for equipment in EquipmentAvailability.allCases {
                    for length in SessionLength.allCases {
                        for variant in AnswerVariant.allCases {
                            combinations += 1
                            let answers = GeneratorAnswers(
                                goal: .muscleGain,
                                daysPerWeek: days,
                                split: split,
                                experience: experience,
                                sessionLength: length,
                                equipment: equipment,
                                focusGroups: variant.focusGroups,
                                protectedZones: variant.protectedZones,
                                includeCardio: variant.includeCardio,
                                weeks: 8
                            )
                            let label = "\(days)g \(split.rawValue) \(experience.rawValue) \(equipment.rawValue) \(length.rawValue) \(variant.label)"
                            let parameters = GeneratorPlanParameters(answers: answers)
                            let candidates = GeneratorCandidates.make(
                                answers: answers,
                                library: repository,
                                parameters: parameters
                            )
                            minCandidates = min(minCandidates, candidates.count)
                            maxCandidates = max(maxCandidates, candidates.count)

                            // Ogni schema motorio obbligatorio deve avere almeno un candidato.
                            for day in parameters.days {
                                for pattern in Set(day.requiredPatterns) where candidates.items(pattern: pattern).isEmpty {
                                    emptyPatterns.append("\(label): \(day.name) senza candidati per \(pattern.displayName)")
                                }
                            }

                            // La scheda di riserva deve superare il validatore, con ogni seme.
                            for seed in [0, 1, 2] {
                                let draft = FallbackProgramGenerator.makeDraft(
                                    answers: answers,
                                    parameters: parameters,
                                    candidates: candidates,
                                    seed: seed
                                )
                                let result = GeneratorValidator.validate(
                                    draft,
                                    answers: answers,
                                    parameters: parameters,
                                    candidates: candidates
                                )
                                if !result.isValid {
                                    invalidFallbacks.append("\(label) seme \(seed): \(result.errors.first ?? "")")
                                }
                                if seed == 0 {
                                    for day in draft.days where day.items.count < parameters.exercisesPerDay.lowerBound {
                                        thinDays.append("\(label): \(day.name) con \(day.items.count) esercizi")
                                    }
                                }
                            }

                            let tokens = GeneratorPrompt.estimatedTokens(
                                answers: answers,
                                parameters: parameters,
                                candidates: candidates
                            )
                            maxTokens = max(maxTokens, tokens)
                            if tokens > promptLimit { oversizedPrompts.append("\(label): \(tokens) token") }
                        }
                    }
                }
            }
        }
    }

    harness.check("provate almeno 500 combinazioni di risposte (\(combinations))", combinations >= 500)
    harness.check(
        "ogni schema motorio obbligatorio ha candidati (\(emptyPatterns.prefix(3).joined(separator: "; ")))",
        emptyPatterns.isEmpty
    )
    harness.check(
        "la scheda di riserva è sempre valida (\(invalidFallbacks.prefix(3).joined(separator: "; ")))",
        invalidFallbacks.isEmpty
    )
    harness.check(
        "nessun giorno sotto il minimo di esercizi (\(thinDays.prefix(3).joined(separator: "; ")))",
        thinDays.isEmpty
    )
    harness.check(
        "il prompt resta sotto \(promptLimit) token stimati (massimo \(maxTokens))",
        oversizedPrompts.isEmpty
    )
    harness.check("i candidati non sono mai meno di 30 (minimo \(minCandidates))", minCandidates >= 30)
    harness.check(
        "i candidati non superano il tetto (massimo \(maxCandidates))",
        maxCandidates <= GeneratorCandidates.defaultLimitTotal
    )

    // Divisioni: coerenza fra giorni e struttura.
    harness.section("generatore · divisioni")
    for days in GeneratorAnswers.daysRange {
        let splits = GeneratorAnswers.availableSplits(forDays: days)
        harness.check("\(days) giorni: almeno due divisioni possibili", splits.count >= 2)
        let recommended = GeneratorAnswers.recommendedSplit(days: days, experience: .intermediate)
        harness.check("\(days) giorni: la divisione consigliata è fra quelle possibili", splits.contains(recommended))
        for split in splits {
            let blueprints = GeneratorPlanParameters.blueprints(split: split, days: days)
            harness.check("\(days) giorni, \(split.rawValue): \(blueprints.count) giorni previsti", blueprints.count == days)
            let names = Set(blueprints.map(\.name))
            harness.check("\(days) giorni, \(split.rawValue): nomi dei giorni tutti diversi", names.count == days)
            let hasDash = blueprints.contains { $0.name.contains("—") || $0.name.contains("–") }
            harness.check("\(days) giorni, \(split.rawValue): nessun trattino lungo nei nomi", !hasDash)
        }
    }

    // Una risposta incoerente (PPL a 4 giorni) ricade sulla consigliata.
    let inconsistent = GeneratorAnswers(daysPerWeek: 4, split: .pushPullLegs, experience: .intermediate)
    harness.check("una divisione impossibile ricade su quella consigliata", inconsistent.split == .upperLower)
    harness.check("le risposte risultano sempre coerenti", inconsistent.isConsistent)
    let clamped = GeneratorAnswers(daysPerWeek: 99, weeks: 1)
    harness.check("i giorni fuori scala vengono riportati nell'intervallo", clamped.daysPerWeek == 6)
    harness.check("le settimane fuori scala vengono riportate nell'intervallo", clamped.weeks == 4)
}

@MainActor
private func runGeneratorValidatorChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · validatore")

    let answers = GeneratorAnswers(
        goal: .muscleGain,
        daysPerWeek: 3,
        split: .pushPullLegs,
        experience: .intermediate,
        sessionLength: .medium60,
        equipment: .fullGym,
        weeks: 8
    )
    let parameters = GeneratorPlanParameters(answers: answers)
    let candidates = GeneratorCandidates.make(answers: answers, library: repository, parameters: parameters)
    let good = FallbackProgramGenerator.makeDraft(answers: answers, parameters: parameters, candidates: candidates)

    let positive = GeneratorValidator.validate(good, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("la scheda di riserva passa il validatore (\(positive.errors.first ?? ""))", positive.isValid)
    harness.check("la scheda di riserva non ha nemmeno rilievi", positive.warnings.isEmpty)

    // Caso negativo: numero di giorni sbagliato.
    var wrongDays = good
    wrongDays.days.removeLast()
    harness.check(
        "un numero di giorni sbagliato viene rifiutato",
        !GeneratorValidator.validate(wrongDays, answers: answers, parameters: parameters, candidates: candidates).isValid
    )

    // Caso negativo: id inventato.
    var unknownID = good
    unknownID.days[0].items[0].id = "9999"
    harness.check(
        "un id fuori dai candidati viene rifiutato",
        !GeneratorValidator.validate(unknownID, answers: answers, parameters: parameters, candidates: candidates).isValid
    )

    // Caso negativo: doppione nello stesso giorno.
    var duplicated = good
    duplicated.days[0].items[1].id = duplicated.days[0].items[0].id
    harness.check(
        "un doppione nello stesso giorno viene rifiutato",
        !GeneratorValidator.validate(duplicated, answers: answers, parameters: parameters, candidates: candidates).isValid
    )

    // Caso negativo: valori fuori scala.
    var outOfRange = good
    outOfRange.days[0].items[0].sets = 12
    outOfRange.days[0].items[0].rest = 900
    outOfRange.days[0].items[0].repsMin = 40
    harness.check(
        "serie, recupero e ripetizioni fuori scala vengono rifiutati",
        !GeneratorValidator.validate(outOfRange, answers: answers, parameters: parameters, candidates: candidates).isValid
    )

    // Caso negativo: nota troppo lunga o con trattino lungo.
    var badNote = good
    badNote.days[0].items[0].note = String(repeating: "a", count: 90)
    harness.check(
        "una nota troppo lunga viene rifiutata",
        !GeneratorValidator.validate(badNote, answers: answers, parameters: parameters, candidates: candidates).isValid
    )
    badNote.days[0].items[0].note = "presa larga — schiena ferma"
    harness.check(
        "una nota con il trattino lungo viene rifiutata",
        !GeneratorValidator.validate(badNote, answers: answers, parameters: parameters, candidates: candidates).isValid
    )

    // Caso negativo: ordine sbagliato (isolamento prima del multiarticolare).
    var badOrder = good
    if let compoundIndex = badOrder.days[0].items.firstIndex(where: { candidates.candidate(id: $0.id)?.kind == .compound }),
       let isolationIndex = badOrder.days[0].items.firstIndex(where: { candidates.candidate(id: $0.id)?.kind == .isolation }) {
        badOrder.days[0].items.swapAt(compoundIndex, isolationIndex)
        harness.check(
            "un isolamento messo prima di un multiarticolare viene rifiutato",
            !GeneratorValidator.validate(badOrder, answers: answers, parameters: parameters, candidates: candidates).isValid
        )
    } else {
        harness.fail("la scheda di prova non ha sia multiarticolari sia isolamenti")
    }

    // Caso negativo: esercizio su una zona da proteggere.
    let protective = GeneratorAnswers(
        daysPerWeek: 3,
        split: .pushPullLegs,
        experience: .intermediate,
        equipment: .fullGym,
        protectedZones: [.lowerBack]
    )
    let protectiveParameters = GeneratorPlanParameters(answers: protective)
    let protectiveCandidates = GeneratorCandidates.make(
        answers: protective,
        library: repository,
        parameters: protectiveParameters
    )
    harness.check(
        "con la schiena bassa da proteggere lo stacco sparisce dai candidati",
        !protectiveCandidates.contains(id: "0032")
    )
    harness.check(
        "con la schiena bassa da proteggere resta comunque una spinta d'anca",
        !protectiveCandidates.items(pattern: .hinge).isEmpty
    )

    // Riparazione
    harness.section("generatore · riparazione")

    var broken = good
    broken.name = "Scheda — prova con un nome davvero molto ma molto più lungo del consentito"
    broken.days[0].items[0].sets = 0
    broken.days[0].items[0].rest = 5
    broken.days[0].items[0].repsMin = 14
    broken.days[0].items[0].repsMax = 6
    broken.days[0].items[1].id = broken.days[0].items[0].id
    broken.days[0].items.append(GeneratedProgramDraft.Item(id: "9999", sets: 3, repsMin: 8, repsMax: 12, rest: 90))
    if let isolationIndex = broken.days[0].items.firstIndex(where: { candidates.candidate(id: $0.id)?.kind == .isolation }) {
        let item = broken.days[0].items.remove(at: isolationIndex)
        broken.days[0].items.insert(item, at: 0)
    }

    let (repaired, repairs) = GeneratorValidator.repair(
        broken,
        answers: answers,
        parameters: parameters,
        candidates: candidates
    )
    harness.check("la riparazione dichiara quello che ha corretto (\(repairs.count) correzioni)", repairs.count >= 5)
    harness.check("il nome riparato non ha trattini lunghi", !repaired.name.contains("—"))
    harness.check("il nome riparato sta nel limite", repaired.name.count <= GeneratorValidator.maxNameLength)
    harness.check("l'id inventato è sparito", !repaired.days[0].items.contains { $0.id == "9999" })
    let repairedIDs = repaired.days[0].items.map(\.id)
    harness.check("i doppioni sono spariti", Set(repairedIDs).count == repairedIDs.count)
    let allInRange = repaired.days.allSatisfy { day in
        day.items.allSatisfy { item in
            GeneratorValidator.setsRange.contains(item.sets)
                && GeneratorValidator.restRange.contains(item.rest)
                && (item.repsMin == nil || item.repsMin! <= item.repsMax!)
        }
    }
    harness.check("i valori sono tornati nei limiti", allInRange)
    var sawIsolation = false
    var orderOK = true
    for item in repaired.days[0].items {
        guard let candidate = candidates.candidate(id: item.id) else { continue }
        if candidate.kind == .isolation { sawIsolation = true } else if sawIsolation { orderOK = false }
    }
    harness.check("i multiarticolari sono tornati davanti", orderOK)

    // Una scheda riparata che ha perso esercizi può restare invalida: quel che
    // conta è che la riparazione non peggiori mai la situazione.
    let beforeErrors = GeneratorValidator.validate(broken, answers: answers, parameters: parameters, candidates: candidates).errors.count
    let afterErrors = GeneratorValidator.validate(repaired, answers: answers, parameters: parameters, candidates: candidates).errors.count
    harness.check("la riparazione riduce gli errori (\(beforeErrors) → \(afterErrors))", afterErrors < beforeErrors)

    // Conversione in Program
    harness.section("generatore · conversione")

    let now = Fixtures.date(2026, 9, 18)
    let program = GeneratorValidator.program(from: good, answers: answers, candidates: candidates, now: now)
    harness.check("il programma ha i giorni della scheda", program.days.count == good.days.count)
    harness.check("il programma ha la durata richiesta", program.plannedWeeks == answers.weeks)
    harness.check("il programma parte oggi", program.normalizedStart() == Fixtures.calendar.startOfDay(for: now))
    harness.check("il programma è a rotazione", program.mode == .rotation)
    harness.check("nessun carico impostato", program.days.allSatisfy { $0.items.allSatisfy { $0.targetWeightKg == nil } })
    harness.check("il numero di voci coincide", program.totalSets > 0 && program.exerciseIDs.count > 0)
    let allKnown = program.exerciseIDs.allSatisfy { repository.exercise(id: $0) != nil }
    harness.check("tutti gli esercizi del programma esistono nella libreria", allKnown)
    let restsOK = program.days.allSatisfy { $0.items.allSatisfy { GeneratorValidator.restRange.contains($0.restSeconds) } }
    harness.check("i recuperi del programma sono nei limiti", restsOK)

    // Lettura di una risposta sporca del modello
    harness.section("generatore · lettura risposta")
    let dirty = """
    Certo! Ecco la scheda:
    ```json
    {"name":"Prova","days":[{"name":"Giorno A","items":[{"id":"0025","sets":4,"repsMin":6,"repsMax":10,"rest":120,"note":null}]}]}
    ```
    Buon allenamento.
    """
    if let parsed = try? GeneratedProgramDraft.decode(fromModelOutput: dirty) {
        harness.check("il JSON si legge anche dentro un blocco di codice", parsed.days.count == 1)
        harness.check("le voci si leggono correttamente", parsed.days[0].items.first?.id == "0025")
        harness.check("i campi nulli restano nulli", parsed.days[0].items.first?.note == nil)
    } else {
        harness.fail("il JSON dentro un blocco di codice non si legge")
    }
    harness.check("una risposta senza JSON viene rifiutata", (try? GeneratedProgramDraft.decode(fromModelOutput: "non lo so")) == nil)

    // Determinismo e varietà della scheda di riserva
    harness.section("generatore · riserva")
    let first = FallbackProgramGenerator.makeDraft(answers: answers, parameters: parameters, candidates: candidates, seed: 0)
    let again = FallbackProgramGenerator.makeDraft(answers: answers, parameters: parameters, candidates: candidates, seed: 0)
    harness.check("con lo stesso seme la scheda è identica", first == again)
    let other = FallbackProgramGenerator.makeDraft(answers: answers, parameters: parameters, candidates: candidates, seed: 3)
    harness.check("con un seme diverso la scheda cambia", other != first)
    let otherValid = GeneratorValidator.validate(other, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("anche la scheda rigenerata è valida", otherValid.isValid)

    // Il cardio finisce in fondo al giorno, non in mezzo.
    let cardioAnswers = GeneratorAnswers(
        goal: .fatLoss,
        daysPerWeek: 3,
        split: .fullBody,
        experience: .beginner,
        sessionLength: .medium60,
        equipment: .fullGym,
        includeCardio: true
    )
    let cardioParameters = GeneratorPlanParameters(answers: cardioAnswers)
    let cardioCandidates = GeneratorCandidates.make(
        answers: cardioAnswers,
        library: repository,
        parameters: cardioParameters
    )
    let cardioDraft = FallbackProgramGenerator.makeDraft(
        answers: cardioAnswers,
        parameters: cardioParameters,
        candidates: cardioCandidates
    )
    let cardioAtEnd = cardioDraft.days.allSatisfy { day in
        guard let last = day.items.last else { return false }
        return cardioCandidates.candidate(id: last.id)?.pattern == .cardio
    }
    harness.check("il cardio chiude ogni giorno", cardioAtEnd)
    let cardioIsTimed = cardioDraft.days.allSatisfy { $0.items.last?.seconds != nil }
    harness.check("il cardio è a tempo", cardioIsTimed)
    harness.check(
        "senza cardio richiesto i candidati non ne contengono",
        candidates.items(pattern: .cardio).isEmpty
    )
}

@MainActor
private func runGeneratorSchemaChecks(_ harness: Harness) {
    harness.section("generatore · prompt e schema")

    let schema = GeneratorPrompt.jsonSchemaObject()
    harness.check("lo schema JSON è interpretabile", !schema.isEmpty)
    harness.check("lo schema è un oggetto", schema["type"] as? String == "object")
    harness.check("lo schema vieta le proprietà in più", schema["additionalProperties"] as? Bool == false)
    let required = schema["required"] as? [String] ?? []
    harness.check("lo schema richiede il nome e gli elenchi di id", required.sorted() == ["d", "n"])

    // Stabilità: lo schema è parte del contratto con il servizio di inferenza,
    // un cambio silenzioso romperebbe le chiamate in produzione.
    let normalized = GeneratorPrompt.jsonSchema
        .split(whereSeparator: \.isWhitespace)
        .joined()
    harness.check(
        "lo schema chiede elenchi di stringhe, uno per giorno",
        normalized.contains("\"d\":{\"type\":\"array\",\"items\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}")
    )
    harness.check("il nome della scheda è una stringa", normalized.contains("\"n\":{\"type\":\"string\"}"))
    // La modalità stretta dei fornitori accetta pochi costrutti: niente unioni
    // con null, niente vincoli di cardinalità, niente descrizioni.
    harness.check(
        "lo schema resta banale (nessun costrutto che i fornitori rifiutano)",
        !normalized.contains("null") && !normalized.contains("minItems") && !normalized.contains("description")
    )
    harness.check("lo schema ha un nome stabile", GeneratorPrompt.schemaName == "gym_program")

    // Una bozza reale deve essere accettata dalla forma dichiarata.
    let draft = GeneratedProgramDraft(
        name: "Prova",
        days: [.init(name: "Giorno A", items: [.init(id: "0025", sets: 4, repsMin: 6, repsMax: 10, rest: 120)])]
    )
    let text = draft.jsonString()
    harness.check("la bozza si serializza", text.contains("\"0025\""))
    if let roundTrip = try? GeneratedProgramDraft.decode(fromModelOutput: text) {
        harness.check("la bozza fa round-trip", roundTrip == draft)
    } else {
        harness.fail("la bozza non fa round-trip")
    }

    harness.check("il prompt di sistema è in italiano e vieta il testo libero", GeneratorPrompt.system.contains("SOLO con un oggetto JSON"))
    // Il nome della scheda lo decide il telefono (vedi `GeneratorValidator.defaultName`):
    // il prompt non chiede più un titolo e quindi non parla più di trattini lunghi.
    // Al suo posto le regole che la prova reale ha mostrato mancanti.
    harness.check("il prompt di sistema impone il numero esatto di esercizi", GeneratorPrompt.system.contains("ESATTAMENTE"))
    harness.check("il prompt di sistema vieta i giorni gemelli", GeneratorPrompt.system.contains("al massimo due esercizi in comune"))
    harness.check("il prompt di sistema chiede la copertura dei gruppi grandi", GeneratorPrompt.system.contains("lavoro diretto"))
    harness.check("il prompt di sistema chiede spinta e tirata", GeneratorPrompt.system.contains("almeno una spinta e almeno una tirata"))
    harness.check("il prompt di sistema dice l'ordine della seduta", GeneratorPrompt.system.contains("cardio per ultimo"))
    harness.check(
        "il prompt di sistema non contiene trattini lunghi",
        !GeneratorPrompt.system.contains("—") && !GeneratorPrompt.system.contains("–")
    )
    harness.check(
        "il prompt di sistema dice che i numeri non li scrive il modello",
        GeneratorPrompt.system.contains("li calcola l'app")
    )
}
