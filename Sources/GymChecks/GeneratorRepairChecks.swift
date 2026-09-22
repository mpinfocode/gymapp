import Foundation
import GymCore

/// I difetti che la prova reale del 18/09/2026 ha mostrato, uno per uno, con la
/// scheda sbagliata in ingresso e la scheda giusta pretesa in uscita.
///
/// Ogni blocco qui sotto è un difetto vero visto in una scheda vera, non un caso
/// inventato: seduta corta, giorni gemelli, addome mai allenato, scheda
/// sbilanciata, zone protette prese alla leggera, principiante mandato sotto un
/// bilanciere, nome della scheda da volantino.
@MainActor
func runGeneratorRepairChecks(_ harness: Harness, repository: ExerciseRepository?) {
    guard let repository else {
        harness.section("generatore · riparazione delle regole")
        harness.fail("repository non caricato")
        return
    }
    runShortDayChecks(harness, repository: repository)
    runTwinDayChecks(harness, repository: repository)
    runCoverageChecks(harness, repository: repository)
    runBalanceChecks(harness, repository: repository)
    runProtectedZoneChecks(harness, repository: repository)
    runBeginnerChecks(harness, repository: repository)
    runNameChecks(harness, repository: repository)
    runCandidateSupplyChecks(harness, repository: repository)
    runRoutingChecks(harness)
}

// MARK: - 0. Instradamento e vincoli

/// I due modelli OpenAI della prova reale sono stati rifiutati in un decimo di
/// secondo con "non esiste o non è disponibile". Un id inesistente non si
/// risolve in 0,1 s per caso: era un 404 di instradamento, cioè "nessun
/// fornitore serve questo modello con i vincoli che hai chiesto".
@MainActor
private func runRoutingChecks(_ harness: Harness) {
    harness.section("generatore · instradamento")

    func read(_ body: String, status: Int) -> OpenRouterClient.Failure? {
        do {
            _ = try OpenRouterClient.read(
                OpenRouterClient.RawResponse(data: Data(body.utf8), status: status),
                model: "x/y"
            )
            return nil
        } catch let failure as OpenRouterClient.Failure {
            return failure
        } catch {
            return nil
        }
    }

    harness.check(
        "un 404 con \"No endpoints found\" è un problema di vincoli",
        read(#"{"error":{"message":"No endpoints found that support structured outputs."}}"#, status: 404)
            == .noEndpointsForConstraints("x/y")
    )
    harness.check(
        "anche \"No allowed providers\"",
        read(#"{"error":{"message":"No allowed providers are available for the selected model."}}"#, status: 404)
            == .noEndpointsForConstraints("x/y")
    )
    harness.check(
        "un 404 senza spiegazioni resta un modello inesistente",
        read("{}", status: 404) == .modelNotFound("x/y")
    )
    harness.check(
        "e un 400 che dice \"not a valid model id\" anche",
        read(#"{"error":{"message":"xyz is not a valid model id"}}"#, status: 400) == .modelNotFound("x/y")
    )
    harness.check(
        "il riconoscimento del messaggio non è sensibile alle maiuscole",
        OpenRouterClient.isNoEndpoints("NO ENDPOINTS FOUND matching your data policy")
    )
    harness.check(
        "e non scatta su un messaggio qualunque",
        !OpenRouterClient.isNoEndpoints("rate limit exceeded")
    )

    // Il secondo tentativo: nessun vincolo di fornitore, e json_object.
    let client = OpenRouterClient()
    func payload(relaxed: Bool, format: OpenRouterClient.ResponseFormat) -> [String: Any] {
        guard
            let data = try? client.body(
                system: "s", user: "u", model: "x/y",
                responseFormat: format, temperature: 0.1, maxTokens: 600,
                reasoning: .off, relaxConstraints: relaxed
            ),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    let strict = payload(relaxed: false, format: .jsonSchema)
    let provider = strict["provider"] as? [String: Any]
    harness.check("al primo tentativo si chiede lo schema garantito", provider?["require_parameters"] as? Bool == true)
    harness.check("e si preferisce chi risponde presto", provider?["preferred_max_latency"] != nil)

    let relaxed = payload(relaxed: true, format: .jsonObject)
    harness.check("al secondo tentativo non c'è nessun vincolo di fornitore", relaxed["provider"] == nil)
    harness.check(
        "e si chiede solo un oggetto JSON",
        (relaxed["response_format"] as? [String: Any])?["type"] as? String == "json_object"
    )

    // I modelli Anthropic partono già da json_object: con lo schema stretto non
    // troverebbero nessun fornitore e sprecherebbero un giro.
    harness.check(
        "i modelli Anthropic partono da json_object",
        OpenRouterClient.prefersJSONObject(forModel: "anthropic/claude-haiku-4.5")
    )
    harness.check(
        "gli altri no",
        !OpenRouterClient.prefersJSONObject(forModel: "google/gemini-2.5-flash")
    )

    // Chi ragiona per forza ha bisogno di più token, altrimenti finisce i token
    // pensando e consegna una risposta vuota.
    let parameters = GeneratorPlanParameters(
        answers: GeneratorAnswers(daysPerWeek: 3, split: .fullBody, experience: .beginner)
    )
    let plain = GeneratorPrompt.outputTokenBudget(parameters: parameters, model: "google/gemini-2.5-flash-lite")
    let thinking = GeneratorPrompt.outputTokenBudget(parameters: parameters, model: "openai/gpt-5-mini")
    harness.check("chi non ragiona tiene il budget stretto (\(plain))", plain == GeneratorPrompt.outputTokenBudget(parameters: parameters))
    harness.check("chi ragiona per forza ne riceve di più (\(thinking))", thinking > plain)
    harness.check(
        "a gpt-5-mini si chiede il ragionamento minimo",
        OpenRouterClient.recommendedReasoning(forModel: "openai/gpt-5-mini") == .minimal
    )

    // Dopo la prova del 22/09/2026 il predefinito è il Flash: bozze quasi già
    // giuste a $0,0014. Il Flash Lite resta come alternativa economica.
    harness.check(
        "il modello predefinito è il consigliato della prova reale",
        ProgramGenerationService.defaultModel == "google/gemini-2.5-flash"
    )
    harness.check(
        "l'alternativa economica è il Flash Lite",
        ProgramGenerationService.economyModel == "google/gemini-2.5-flash-lite"
    )
    harness.check(
        "i due non coincidono",
        ProgramGenerationService.defaultModel != ProgramGenerationService.economyModel
    )
    harness.check(
        "nessuno dei due parte da json_object: reggono lo schema stretto",
        !OpenRouterClient.prefersJSONObject(forModel: ProgramGenerationService.defaultModel)
            && !OpenRouterClient.prefersJSONObject(forModel: ProgramGenerationService.economyModel)
    )
}

/// Prepara risposte, parametri e candidati in una riga sola.
@MainActor
private func setUp(
    _ answers: GeneratorAnswers,
    _ repository: ExerciseRepository
) -> (GeneratorAnswers, GeneratorPlanParameters, GeneratorCandidates) {
    let parameters = GeneratorPlanParameters(answers: answers)
    let candidates = GeneratorCandidates.make(answers: answers, library: repository, parameters: parameters)
    return (answers, parameters, candidates)
}

/// Costruisce una bozza dai soli id, come fa il formato compatto.
private func draft(_ dayIDs: [[String]], name: String = "Prova") -> GeneratedProgramDraft {
    GeneratedProgramDraft(
        name: name,
        days: dayIDs.map { ids in
            GeneratedProgramDraft.Day(name: "", items: ids.map(GeneratedProgramDraft.Item.idOnly))
        }
    )
}

// MARK: - 1. La seduta corta

/// Il caso che ha fatto arrabbiare il PM: full body da 60 minuti, previsti 6
/// esercizi al giorno, il modello ne ha mandati 4 e il validatore ha detto
/// "valido". Adesso il validatore dice di no e la riparazione completa.
@MainActor
private func runShortDayChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · seduta corta")

    let (answers, parameters, candidates) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 3, split: .fullBody, experience: .beginner,
            sessionLength: .medium60, equipment: .fullGym
        ),
        repository
    )
    let target = parameters.targetExercisesPerDay
    harness.check("una full body da 60 minuti punta a 6 esercizi (\(target))", target == 6)
    harness.check(
        "l'intervallo ammesso è il bersaglio più o meno uno (\(parameters.allowedExercisesPerDay))",
        parameters.allowedExercisesPerDay == 5...7
    )

    // La scheda vera del 18/09/2026: quattro id per giorno.
    let short = draft([
        ["0770", "0289", "0293", "0294"],
        ["1459", "0405", "0198", "0200"],
        ["0336", "0577", "0861", "0178"],
    ])
    let before = GeneratorValidator.validate(short, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("quattro esercizi al giorno non passano più il validatore", !before.isValid)
    harness.check(
        "il validatore dice quanti ne servono",
        before.errors.contains { $0.contains("esercizi, ne servono da 5 a 7") }
    )

    let (repaired, repairs) = GeneratorValidator.repair(
        short, answers: answers, parameters: parameters, candidates: candidates
    )
    harness.check(
        "la riparazione porta ogni giorno a \(target) esercizi",
        repaired.days.allSatisfy { $0.items.count == target }
    )
    harness.check(
        "la riparazione dice quali esercizi ha aggiunto",
        repairs.contains { $0.contains("aggiunti") }
    )
    let after = GeneratorValidator.validate(repaired, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("la scheda completata è valida (\(after.errors.first ?? ""))", after.isValid)
    harness.check(
        "gli esercizi scelti dal modello non sono stati buttati via",
        ["0770", "0289", "0293", "0294"].allSatisfy { id in repaired.days[0].items.contains { $0.id == id } }
    )

    // Anche il caso opposto: una seduta troppo lunga si accorcia.
    let long = draft([
        ["0770", "0289", "0293", "0294", "0178", "0276", "0194", "0605", "0175"],
        ["1459", "0405", "0198", "0200", "0334", "0274", "0594", "0233", "0868"],
        ["0336", "0577", "0861", "0178", "0585", "0243", "0207", "0596", "0212"],
    ])
    let (trimmed, _) = GeneratorValidator.repair(
        long, answers: answers, parameters: parameters, candidates: candidates
    )
    harness.check(
        "una seduta da nove esercizi viene riportata a \(target)",
        trimmed.days.allSatisfy { $0.items.count == target }
    )
    harness.check(
        "accorciando si tengono i multiarticolari",
        trimmed.days[0].items.contains { candidates.candidate(id: $0.id)?.id == "0289" }
    )
}

// MARK: - 2. I giorni gemelli

/// Parte alta A e Parte alta B con quattro esercizi su sette identici, e a corpo
/// libero undici ripetizioni su quindici: era la stessa seduta due volte.
@MainActor
private func runTwinDayChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · giorni gemelli")

    let (answers, parameters, candidates) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .intermediate,
            sessionLength: .medium60, equipment: .fullGym
        ),
        repository
    )
    harness.check(
        "parte alta A e parte alta B sono giorni dello stesso tipo",
        GeneratorValidator.areSimilar(0, 2, parameters: parameters)
    )
    harness.check(
        "parte alta A e parte bassa A non lo sono",
        !GeneratorValidator.areSimilar(0, 1, parameters: parameters)
    )

    // Due giorni di parte alta identici.
    let upper = ["0577", "0861", "0603", "0017", "0178", "0294"]
    let lower = ["0739", "1459", "0336", "0586", "0594", "0276"]
    let twins = draft([upper, lower, upper, lower])
    let before = GeneratorValidator.validate(twins, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("due giorni identici non passano il validatore", !before.isValid)
    harness.check(
        "il validatore li chiama con il loro nome",
        before.errors.contains { $0.contains("sono lo stesso giorno due volte") }
    )

    let (repaired, repairs) = GeneratorValidator.repair(
        twins, answers: answers, parameters: parameters, candidates: candidates
    )
    let sharedUpper = Set(repaired.days[0].items.map(\.id)).intersection(repaired.days[2].items.map(\.id))
    harness.check(
        "dopo la riparazione i giorni di parte alta hanno al massimo due esercizi in comune (\(sharedUpper.count))",
        sharedUpper.count <= GeneratorRepair.maxSharedBetweenSimilarDays
    )
    let sharedLower = Set(repaired.days[1].items.map(\.id)).intersection(repaired.days[3].items.map(\.id))
    harness.check(
        "lo stesso vale per la parte bassa (\(sharedLower.count))",
        sharedLower.count <= GeneratorRepair.maxSharedBetweenSimilarDays
    )
    harness.check(
        "la riparazione spiega le sostituzioni",
        repairs.contains { $0.contains("tornava da un giorno uguale") }
    )
    // I sostituti devono restare dello stesso schema motorio: una tirata
    // verticale si sostituisce con un'altra tirata verticale, non con un curl.
    let patternsA = repaired.days[0].items.compactMap { candidates.candidate(id: $0.id)?.pattern }
    let patternsB = repaired.days[2].items.compactMap { candidates.candidate(id: $0.id)?.pattern }
    harness.check(
        "i due giorni di parte alta coprono gli stessi schemi motori",
        Set(patternsA).intersection(patternsB).count >= 4
    )
    let after = GeneratorValidator.validate(repaired, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("la scheda con i gemelli separati è valida (\(after.errors.first ?? ""))", after.isValid)
}

// MARK: - 3. La copertura

/// "Addome: mai allenato" in una full body da tre giorni, e glutei a zero.
@MainActor
private func runCoverageChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · copertura settimanale")

    let (answers, parameters, candidates) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 3, split: .fullBody, experience: .intermediate,
            sessionLength: .medium60, equipment: .fullGym
        ),
        repository
    )
    harness.check(
        "con 18 esercizi a settimana l'addome è dovuto",
        GeneratorRepair.requiredDirectGroups(parameters: parameters).contains(.abs)
    )

    // Sei esercizi al giorno, nemmeno uno per l'addome.
    let noAbs = draft([
        ["0739", "0577", "0861", "0603", "0178", "0294"],
        ["1459", "1299", "0017", "0405", "0233", "0200"],
        ["0336", "2144", "0198", "0585", "0334", "0868"],
    ])
    let before = GeneratorValidator.validate(noAbs, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("una scheda senza addome non è valida", !before.isValid)
    harness.check(
        "il validatore nomina il gruppo mancante",
        before.errors.contains { $0.contains("Addome") }
    )

    let (repaired, repairs) = GeneratorValidator.repair(
        noAbs, answers: answers, parameters: parameters, candidates: candidates
    )
    let groups = Set(repaired.days.flatMap { $0.items.compactMap { candidates.candidate(id: $0.id)?.group } })
    harness.check("dopo la riparazione l'addome c'è", groups.contains(.abs))
    harness.check(
        "la riparazione dice perché lo ha aggiunto",
        repairs.contains { $0.contains("non era allenato in tutta la settimana") }
    )
    harness.check(
        "i giorni restano della lunghezza giusta",
        repaired.days.allSatisfy { parameters.allowedExercisesPerDay.contains($0.items.count) }
    )
    let after = GeneratorValidator.validate(repaired, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("la scheda con l'addome è valida (\(after.errors.first ?? ""))", after.isValid)

    // I glutei si accontentano del lavoro indiretto di squat, affondi e stacchi.
    harness.check(
        "squat, affondi e stacchi valgono come lavoro per i glutei",
        GeneratorRepair.posteriorPatterns.isSuperset(of: [.squat, .lunge, .hinge])
    )
}

// MARK: - 4. L'equilibrio

/// Petto al 5% contro dorso e spalle al 13-16%: un gruppo grande sotto la metà
/// del volume previsto mentre un altro lo supera della metà.
@MainActor
private func runBalanceChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · equilibrio")

    harness.check(
        "femorali e glutei sono un blocco solo",
        GeneratorRepair.BigGroup.of(.hamstrings) == .posterior && GeneratorRepair.BigGroup.of(.glutes) == .posterior
    )
    let skewed: [GeneratorRepair.BigGroup: Int] = [.chest: 3, .back: 30, .shoulders: 12, .quads: 12, .posterior: 12]
    let found = GeneratorRepair.imbalance(skewed, among: GeneratorRepair.BigGroup.allCases)
    harness.check("uno squilibrio marcato si riconosce", found?.low.group == .chest && found?.high.group == .back)
    let sane: [GeneratorRepair.BigGroup: Int] = [.chest: 8, .back: 16, .shoulders: 14, .quads: 19, .posterior: 11]
    harness.check(
        "una sopra/sotto normale non viene scambiata per sbilanciata",
        GeneratorRepair.imbalance(sane, among: GeneratorRepair.BigGroup.allCases) == nil
    )

    let (answers, parameters, candidates) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .intermediate,
            sessionLength: .medium60, equipment: .fullGym
        ),
        repository
    )
    // Due giorni di parte alta fatti solo di tirate: il petto sparisce.
    let noChest = draft([
        ["0861", "0017", "0603", "0581", "0233", "0294"],
        ["0739", "1459", "0336", "0586", "0594", "0276"],
        ["0198", "1350", "0219", "0245", "0602", "0313"],
        ["0743", "0196", "0381", "0599", "0605", "0274"],
    ])
    let before = GeneratorValidator.validate(noChest, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("una scheda senza petto non è valida", !before.isValid)

    let (repaired, _) = GeneratorValidator.repair(
        noChest, answers: answers, parameters: parameters, candidates: candidates
    )
    let chest = repaired.days.flatMap { $0.items }.filter { candidates.candidate(id: $0.id)?.group == .chest }
    harness.check("dopo la riparazione il petto c'è (\(chest.count) esercizi)", !chest.isEmpty)
    let after = GeneratorValidator.validate(repaired, answers: answers, parameters: parameters, candidates: candidates)
    harness.check("la scheda riequilibrata è valida (\(after.errors.first ?? ""))", after.isValid)
    harness.check(
        "e non porta più il rilievo di squilibrio",
        !after.warnings.contains { $0.contains("sbilanciata") }
    )
    harness.check(
        "il petto è finito in un giorno di parte alta, non fra le gambe",
        repaired.days[0].items.contains { candidates.candidate(id: $0.id)?.group == .chest }
            || repaired.days[2].items.contains { candidates.candidate(id: $0.id)?.group == .chest }
    )
}

// MARK: - 5. Le zone da proteggere

/// Con "spalle" da proteggere il modello aveva messo la panca piana con il
/// bilanciere due volte e il lento avanti, e il validatore aveva detto di sì.
@MainActor
private func runProtectedZoneChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · zone da proteggere")

    let (answers, parameters, candidates) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .intermediate,
            sessionLength: .medium60, equipment: .fullGym, protectedZones: [.shoulders]
        ),
        repository
    )

    // Gli esercizi vietati non sono nemmeno fra i candidati.
    let banned = ["0025", "0047", "0033", "0091", "1456", "0086", "0251", "0814", "0129", "1451", "0246", "0375"]
    for id in banned {
        harness.check(
            "con le spalle da proteggere \(id) non è fra i candidati",
            !candidates.contains(id: id)
        )
    }
    // Quelli ammessi ci sono, e restano scelte sensate.
    for id in ["0577", "1299", "2144", "0289", "0314", "0662", "0603", "0219", "0997", "0405", "0596", "0233"] {
        harness.check("con le spalle da proteggere \(id) resta disponibile", candidates.contains(id: id))
    }
    // I delicati portano l'etichetta giusta nella selezione. In palestra
    // completa restano poi fuori dall'elenco mandato al modello, perché a
    // parità di tutto si preferisce sempre un esercizio pulito: è il
    // comportamento voluto, non un effetto collaterale.
    for id in ["0748", "0757", "0426", "0766", "0308", "0319", "0301", "0652"] {
        harness.check(
            "\(id) è etichettato delicato per le spalle, non vietato",
            CuratedExercisePool.byID[id]?.caution.contains(.shoulders) == true
                && CuratedExercisePool.byID[id]?.avoid.contains(.shoulders) != true
        )
    }
    let careful = candidates.items.filter(candidates.needsCare)
    harness.check(
        "con la palestra completa i delicati per le spalle non entrano nemmeno nell'elenco (\(careful.count))",
        careful.isEmpty
    )

    // Un esercizio vietato che il modello mette lo stesso non si toglie e
    // basta: si sostituisce con uno dello stesso schema motorio, altrimenti il
    // giorno resta senza la spinta verticale che quell'esercizio copriva.
    // È la risposta reale del 18/09/2026: `0091`, lento avanti con il
    // bilanciere, in due giorni su quattro con le spalle da proteggere.
    let forbidden = draft([
        ["0289", "0027", "0091", "0017", "0406", "0294", "0200"],
        ["0043", "0085", "0336", "0585", "0594", "2135"],
        ["0091", "0017", "0289", "0027", "0383", "0201", "0313"],
        ["1459", "0381", "0739", "0586", "0594", "0175"],
    ])
    harness.check("0091 è vietato con le spalle da proteggere", !candidates.contains(id: "0091"))
    let (fixed, forbiddenRepairs) = GeneratorValidator.repair(
        forbidden, answers: answers, parameters: parameters, candidates: candidates
    )
    harness.check(
        "la riparazione dichiara la sostituzione, non solo la rimozione",
        forbiddenRepairs.contains { $0.contains("0091") && $0.contains("al suo posto") }
    )
    for index in [0, 2] {
        let patterns = fixed.days[index].items.compactMap { candidates.candidate(id: $0.id)?.pattern }
        harness.check(
            "\(fixed.days[index].name): la spinta verticale tolta è stata rimpiazzata da un'altra spinta verticale",
            patterns.contains(.verticalPush)
        )
    }
    harness.check(
        "nessun esercizio vietato sopravvive alla riparazione",
        fixed.days.allSatisfy { day in
            day.items.allSatisfy { item in
                guard let curated = CuratedExercisePool.byID[item.id] else { return true }
                return curated.avoid.isDisjoint(with: answers.protectedZones)
            }
        }
    )
    let fixedValidation = GeneratorValidator.validate(
        fixed, answers: answers, parameters: parameters, candidates: candidates
    )
    harness.check(
        "la scheda ripulita dai vietati è valida (\(fixedValidation.errors.first ?? ""))",
        fixedValidation.isValid
    )
    // E gli esercizi che il titolo breve fa sembrare a bilanciere non lo sono:
    // "Bench Press" qui è 0289, manubri.
    harness.check(
        "0289 è la panca con i manubri, non con il bilanciere",
        repository.exercise(id: "0289")?.equipment.lowercased() == "dumbbell"
    )
    harness.check(
        "0027 è il rematore con il bilanciere, vietato solo dalla schiena bassa",
        CuratedExercisePool.byID["0027"]?.avoid == [.lowerBack]
    )

    // Dove invece servono davvero (schiena bassa: le estensioni lombari sono il
    // lavoro diretto per quella zona) restano, segnati.
    let (backAnswers, backParameters, backCandidates) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .intermediate,
            sessionLength: .medium60, equipment: .fullGym, protectedZones: [.lowerBack]
        ),
        repository
    )
    harness.check("con la schiena bassa restano candidati delicati", backCandidates.hasCautionItems)
    harness.check(
        "l'elenco per il modello li segna con un punto esclamativo",
        backCandidates.compactList.contains("|!")
    )
    let backPrompt = GeneratorPrompt.user(
        answers: backAnswers, parameters: backParameters, candidates: backCandidates
    )
    harness.check("il prompt spiega cosa vuol dire quel segno", backPrompt.contains("al massimo una per giorno"))
    harness.check("e che non devono aprire la seduta", backPrompt.contains("mai come primo esercizio"))

    // Una seduta con tre esercizi delicati, uno dei quali apre.
    let careless = draft([
        ["0489", "0573", "0593", "0861", "0178", "0294"],
        ["0739", "0586", "0599", "0594", "1409", "0276"],
        ["0198", "1350", "0219", "0245", "0602", "0313"],
        ["0743", "0597", "0381", "0582", "0605", "0274"],
    ])
    let before = GeneratorValidator.validate(
        careless, answers: backAnswers, parameters: backParameters, candidates: backCandidates
    )
    harness.check("tre esercizi delicati nello stesso giorno non passano", !before.isValid)
    harness.check(
        "il validatore dice che ce n'è più di uno",
        before.errors.contains { $0.contains("più di un esercizio delicato") }
    )
    harness.check(
        "e che uno apre la seduta",
        before.errors.contains { $0.contains("apre la seduta") }
    )

    let (repaired, _) = GeneratorValidator.repair(
        careless, answers: backAnswers, parameters: backParameters, candidates: backCandidates
    )
    for day in repaired.days {
        let care = day.items.compactMap { backCandidates.candidate(id: $0.id) }.filter(backCandidates.needsCare)
        harness.check("\(day.name): al massimo un esercizio delicato (\(care.count))", care.count <= 1)
        if let first = day.items.first, let candidate = backCandidates.candidate(id: first.id) {
            harness.check(
                "\(day.name): la seduta non si apre con un esercizio delicato",
                !backCandidates.needsCare(candidate)
            )
        }
    }
    let after = GeneratorValidator.validate(
        repaired, answers: backAnswers, parameters: backParameters, candidates: backCandidates
    )
    harness.check("la scheda rispettosa della schiena bassa è valida (\(after.errors.first ?? ""))", after.isValid)

    // E la scheda con le spalle protette resta valida di suo.
    let shoulderSafe = FallbackProgramGenerator.makeDraft(
        answers: answers, parameters: parameters, candidates: candidates
    )
    let shoulderValidation = GeneratorValidator.validate(
        shoulderSafe, answers: answers, parameters: parameters, candidates: candidates
    )
    harness.check(
        "la scheda con le spalle protette è valida (\(shoulderValidation.errors.first ?? ""))",
        shoulderValidation.isValid
    )

    // Le altre tre zone, con gli esercizi che il preparatore toglie per primi.
    let vietati: [StressZone: [String]] = [
        .lowerBack: ["0032", "0044", "0027", "0043", "0085", "0117", "0811"],
        .knees: ["1489", "0514", "0054", "0043", "0042", "1160"],
        .wristsElbows: ["0060", "1749", "0031", "0030", "0251", "0814", "0283"],
    ]
    for (zone, ids) in vietati {
        let (_, _, zoneCandidates) = setUp(
            GeneratorAnswers(
                goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .advanced,
                sessionLength: .long90, equipment: .fullGym, protectedZones: [zone]
            ),
            repository
        )
        for id in ids {
            harness.check("con \(zone.displayName) da proteggere \(id) sparisce", !zoneCandidates.contains(id: id))
        }
    }
    // Pressa, leg curl e hip thrust restano con la schiena bassa da proteggere.
    let (_, _, backSafe) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .advanced,
            sessionLength: .long90, equipment: .fullGym, protectedZones: [.lowerBack]
        ),
        repository
    )
    for id in ["0739", "0586", "0599", "1409", "3013"] {
        harness.check("con la schiena bassa da proteggere \(id) resta", backSafe.contains(id: id))
    }
}

// MARK: - 6. I principianti

/// Un principiante non finisce sotto un bilanciere libero pesante.
@MainActor
private func runBeginnerChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · principianti")

    let resolved = CuratedExercisePool.resolved(in: repository)
    let heavyBarbell = resolved.filter { item in
        item.exercise.equipment.lowercased() == "barbell" && item.kind == .compound
    }
    let tooEasy = heavyBarbell.filter { $0.level == .beginner }
    harness.check(
        "nessun multiarticolare al bilanciere libero è da principiante (\(tooEasy.map(\.shortName).joined(separator: ", ")))",
        tooEasy.isEmpty
    )
    harness.check("i multiarticolari al bilanciere sono tanti (\(heavyBarbell.count))", heavyBarbell.count >= 15)

    // Goblet squat, manubri leggeri e macchine restano da principiante.
    for id in ["1760", "0413", "0534", "0289", "0314", "0405", "0739", "0577"] {
        harness.check(
            "\(id) resta da principiante",
            CuratedExercisePool.byID[id]?.level == .beginner
        )
    }

    for equipment in EquipmentAvailability.allCases {
        let (_, parameters, candidates) = setUp(
            GeneratorAnswers(
                goal: .muscleGain, daysPerWeek: 3, split: .fullBody, experience: .beginner,
                sessionLength: .medium60, equipment: equipment
            ),
            repository
        )
        let barbell = candidates.items.filter { item in
            item.kind == .compound && repository.exercise(id: item.id)?.equipment.lowercased() == "barbell"
        }
        harness.check(
            "\(equipment.displayName): un principiante non vede multiarticolari al bilanciere (\(barbell.map(\.shortName).joined(separator: ", ")))",
            barbell.isEmpty
        )
        // E gli restano abbastanza candidati per costruire la scheda.
        var thin: [String] = []
        for day in parameters.days {
            for pattern in Set(day.requiredPatterns) where candidates.items(pattern: pattern).count < 2 {
                thin.append("\(pattern.displayName) (\(candidates.items(pattern: pattern).count))")
            }
        }
        harness.check(
            "\(equipment.displayName): ogni schema obbligatorio ha almeno due candidati per un principiante (\(thin.joined(separator: ", ")))",
            thin.isEmpty
        )
    }
}

// MARK: - 7. Il nome della scheda

@MainActor
private func runNameChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · nome della scheda")

    let (answers, parameters, candidates) = setUp(
        GeneratorAnswers(
            goal: .muscleGain, daysPerWeek: 3, split: .fullBody, experience: .beginner,
            sessionLength: .medium60, equipment: .fullGym
        ),
        repository
    )
    harness.check(
        "il nome è italiano e sobrio",
        GeneratorValidator.defaultName(for: answers) == "Total body · 3 giorni"
    )
    let fourDays = GeneratorAnswers(
        goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .intermediate,
        sessionLength: .medium60, equipment: .fullGym
    )
    harness.check(
        "e cambia con la divisione",
        GeneratorValidator.defaultName(for: fourDays) == "Sopra e sotto · 4 giorni"
    )
    for days in GeneratorAnswers.daysRange {
        for split in GeneratorAnswers.availableSplits(forDays: days) {
            let name = GeneratorValidator.defaultName(
                for: GeneratorAnswers(daysPerWeek: days, split: split, experience: .intermediate)
            )
            harness.check("\(days)g \(split.rawValue): nessun trattino lungo nel nome", !name.contains("—") && !name.contains("–"))
            harness.check("\(days)g \(split.rawValue): il nome sta nel limite", name.count <= GeneratorValidator.maxNameLength)
        }
    }

    // Il nome proposto dal modello si legge e si ignora.
    let named = draft([
        ["0739", "0577", "0861", "0603", "0178", "0276"],
        ["1459", "1299", "0017", "0405", "0233", "0274"],
        ["0336", "2144", "0198", "0219", "0334", "0175"],
    ], name: "Massa Total Body — Programma Élite")
    let (repaired, _) = GeneratorValidator.repair(
        named, answers: answers, parameters: parameters, candidates: candidates
    )
    harness.check("il titolo da volantino del modello viene ignorato", repaired.name == "Total body · 3 giorni")
    harness.check("i nomi dei giorni li mette il telefono", repaired.days.map(\.name) == parameters.dayNames)
}

// MARK: - 8. Candidati sufficienti per ogni zona

/// Con una zona da proteggere la scheda deve restare costruibile: per ogni
/// schema motorio obbligatorio, in tutte e tre le classi di attrezzatura, deve
/// restare almeno un candidato, e preferibilmente uno non delicato.
@MainActor
private func runCandidateSupplyChecks(_ harness: Harness, repository: ExerciseRepository) {
    harness.section("generatore · candidati per zona protetta")

    // Gli schemi che qualche giorno pretende davvero.
    var required: Set<MovementPattern> = []
    for days in GeneratorAnswers.daysRange {
        for split in GeneratorAnswers.availableSplits(forDays: days) {
            for blueprint in GeneratorPlanParameters.blueprints(split: split, days: days) {
                required.formUnion(blueprint.requiredPatterns)
            }
        }
    }

    for zone in StressZone.displayOrder {
        for equipment in EquipmentAvailability.allCases {
            let resolved = CuratedExercisePool.resolved(in: repository).filter { item in
                item.curated.suits(equipment: equipment.equipmentClass)
                    && item.group != .other
                    && item.curated.respects(protectedZones: [zone])
            }
            var empty: [String] = []
            var onlyCareful: [String] = []
            for pattern in MovementPattern.allCases where required.contains(pattern) {
                let ofPattern = resolved.filter { $0.pattern == pattern }
                if ofPattern.isEmpty {
                    empty.append(pattern.displayName)
                } else if !ofPattern.contains(where: { $0.curated.caution.isDisjoint(with: [zone]) }) {
                    onlyCareful.append(pattern.displayName)
                }
            }
            harness.check(
                "\(zone.displayName) + \(equipment.displayName): ogni schema obbligatorio ha un candidato (\(empty.joined(separator: ", ")))",
                empty.isEmpty
            )
            harness.check(
                "\(zone.displayName) + \(equipment.displayName): e almeno uno non delicato (\(onlyCareful.joined(separator: ", ")))",
                onlyCareful.isEmpty
            )
        }
    }

    // Una zona da proteggere non deve svuotare l'elenco mandato al modello.
    for zone in StressZone.displayOrder {
        for equipment in EquipmentAvailability.allCases {
            let (_, _, candidates) = setUp(
                GeneratorAnswers(
                    goal: .muscleGain, daysPerWeek: 4, split: .upperLower, experience: .intermediate,
                    sessionLength: .medium60, equipment: equipment, protectedZones: [zone]
                ),
                repository
            )
            harness.check(
                "\(zone.displayName) + \(equipment.displayName): restano almeno 30 candidati (\(candidates.count))",
                candidates.count >= 30
            )
        }
    }
}
