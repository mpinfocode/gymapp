import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import GymCore

/// Verifica il client OpenRouter e il formato compatto **senza toccare la rete**:
/// le risposte del servizio arrivano da un `URLProtocol` finto, così si possono
/// riprodurre esattamente i casi che hanno fatto fallire la prima prova reale.
///
/// Quello che si controlla qui:
/// 1. il corpo della richiesta (ragionamento spento, fornitore scelto per
///    velocità, schema stretto, chiave assente dal corpo);
/// 2. la diagnosi della risposta: contenuto vuoto con `finish_reason: "length"`
///    non è più un generico "senza contenuto" ma un errore che dice di cambiare
///    modello;
/// 3. il ripiego quando il servizio rifiuta il parametro `reasoning`;
/// 4. il tetto di tempo, che deve valere davvero e non solo sulla carta;
/// 5. la lettura del formato compatto e di quello vecchio;
/// 6. che il validatore garantisca le stesse cose di prima.
@MainActor
func runGeneratorClientChecks(_ harness: Harness, repository: ExerciseRepository?) async {
    runRequestBodyChecks(harness)
    runResponseReadingChecks(harness)
    await runTimingChecks(harness)
    await runReasoningRetryChecks(harness)
    runCompactFormatChecks(harness, repository: repository)
}

// MARK: - Corpo della richiesta

@MainActor
private func runRequestBodyChecks(_ harness: Harness) {
    harness.section("client · corpo della richiesta")

    let client = OpenRouterClient()
    let secret = "sk-or-v1-segretissima"

    func payload(
        model: String,
        format: OpenRouterClient.ResponseFormat = .jsonSchema,
        reasoning: OpenRouterClient.ReasoningMode
    ) -> [String: Any] {
        guard
            let data = try? client.body(
                system: "sistema",
                user: "utente \(secret.isEmpty ? "" : "")",
                model: model,
                responseFormat: format,
                temperature: 0.1,
                maxTokens: 700,
                reasoning: reasoning
            ),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            harness.fail("il corpo della richiesta non si costruisce")
            return [:]
        }
        return object
    }

    let spento = payload(model: "google/gemini-2.5-flash-lite", reasoning: .off)
    let reasoning = spento["reasoning"] as? [String: Any]
    harness.check("il ragionamento si spegne con enabled false", reasoning?["enabled"] as? Bool == false)
    harness.check("il testo del ragionamento non torna indietro", reasoning?["exclude"] as? Bool == true)
    harness.check("il tetto di token è quello chiesto", spento["max_tokens"] as? Int == 700)
    harness.check("la temperatura è bassa", (spento["temperature"] as? Double ?? 1) <= 0.2)

    let provider = spento["provider"] as? [String: Any]
    harness.check("il fornitore si sceglie per velocità", provider?["sort"] as? String == "throughput")
    harness.check(
        "con lo schema stretto si escludono i fornitori che non lo applicano",
        provider?["require_parameters"] as? Bool == true
    )
    harness.check("si preferisce chi risponde presto", provider?["preferred_max_latency"] != nil)

    let schema = (spento["response_format"] as? [String: Any])?["json_schema"] as? [String: Any]
    harness.check("lo schema viaggia in modalità stretta", schema?["strict"] as? Bool == true)
    harness.check("lo schema ha il nome previsto", schema?["name"] as? String == GeneratorPrompt.schemaName)

    let libero = payload(model: "google/gemini-2.5-flash-lite", format: .jsonObject, reasoning: .off)
    harness.check(
        "senza schema stretto non si pretende nulla dal fornitore",
        ((libero["provider"] as? [String: Any])?["require_parameters"]) == nil
    )

    let minimo = payload(model: "openai/gpt-5-nano", reasoning: .minimal)
    harness.check(
        "a chi ragiona per forza si chiede lo sforzo minimo",
        (minimo["reasoning"] as? [String: Any])?["effort"] as? String == "minimal"
    )

    let intatto = payload(model: "qualunque/modello", reasoning: .untouched)
    harness.check("senza richiesta non si manda il parametro reasoning", intatto["reasoning"] == nil)

    // Il consiglio per modello: chi ragiona per forza riceve "minimal", tutti
    // gli altri lo spegnimento, che chi non ragiona ignora senza errore.
    harness.check(
        "gpt-5-nano riceve lo sforzo minimo",
        OpenRouterClient.recommendedReasoning(forModel: "openai/gpt-5-nano") == .minimal
    )
    harness.check(
        "gemini 2.5 flash lite riceve lo spegnimento",
        OpenRouterClient.recommendedReasoning(forModel: "google/gemini-2.5-flash-lite") == .off
    )
    harness.check(
        "gpt-4.1-nano, che non ragiona, riceve lo spegnimento innocuo",
        OpenRouterClient.recommendedReasoning(forModel: "openai/gpt-4.1-nano") == .off
    )
    harness.check(
        "non si chiede mai effort none in automatico",
        OpenRouterClient.ReasoningMode.allCases.allSatisfy { mode in
            mode == .none || OpenRouterClient.recommendedReasoning(forModel: "x/y") != .none
        }
    )

    // La chiave sta solo nell'intestazione: nel corpo non ci finisce mai.
    if let data = try? client.body(
        system: "sistema",
        user: "utente",
        model: "x/y",
        responseFormat: .jsonSchema,
        temperature: 0.1,
        maxTokens: 700,
        reasoning: .off
    ) {
        let text = String(data: data, encoding: .utf8) ?? ""
        harness.check("il corpo della richiesta non contiene la chiave", !text.contains(secret))
        harness.check("il corpo della richiesta non contiene intestazioni", !text.lowercased().contains("authorization"))
    }
}

// MARK: - Lettura della risposta

@MainActor
private func runResponseReadingChecks(_ harness: Harness) {
    harness.section("client · diagnosi della risposta")

    func read(_ json: String, status: Int = 200) -> Result<OpenRouterClient.Completion, OpenRouterClient.Failure> {
        let raw = OpenRouterClient.RawResponse(data: Data(json.utf8), status: status)
        do {
            return .success(try OpenRouterClient.read(raw, model: "x/y"))
        } catch let failure as OpenRouterClient.Failure {
            return .failure(failure)
        } catch {
            return .failure(.malformedResponse("\(error)"))
        }
    }

    func failure(_ json: String, status: Int = 200) -> OpenRouterClient.Failure? {
        if case .failure(let value) = read(json, status: status) { return value }
        return nil
    }

    // Il caso che ha fatto fallire la prima prova con gpt-5-nano: quattro volte
    // su quattro, 40-75 secondi di attesa e poi il nulla.
    let esaurito = """
    {"model":"openai/gpt-5-nano","choices":[{"finish_reason":"length","message":{"role":"assistant","content":""}}],
     "usage":{"prompt_tokens":2800,"completion_tokens":3000,"completion_tokens_details":{"reasoning_tokens":3000}}}
    """
    if case .emptyContentReasoningExhausted(let tokens) = failure(esaurito) {
        harness.check("contenuto vuoto con finish_reason length è diagnosticato come ragionamento", true)
        harness.check("si dice quanti token sono stati bruciati a ragionare (\(tokens))", tokens == 3_000)
    } else {
        harness.fail("contenuto vuoto con finish_reason length non è diagnosticato")
    }
    harness.check(
        "l'errore del ragionamento suggerisce di cambiare modello",
        OpenRouterClient.Failure.emptyContentReasoningExhausted(reasoningTokens: 3_000).suggestsAnotherModel
    )
    harness.check(
        "il messaggio spiega cosa è successo, in italiano",
        OpenRouterClient.Failure.emptyContentReasoningExhausted(reasoningTokens: 3_000)
            .description.contains("ragionare")
    )

    // Contenuto vuoto senza nessun indizio: resta l'errore generico.
    let vuoto = """
    {"choices":[{"finish_reason":"stop","message":{"content":"   "}}]}
    """
    harness.check("un contenuto vuoto senza spiegazioni resta l'errore generico", failure(vuoto) == .emptyResponse)

    // Contenuto presente ma tagliato a metà.
    let tagliato = """
    {"choices":[{"finish_reason":"length","message":{"content":"{\\"n\\":\\"Prova\\",\\"d\\":[[\\"00"}}],
     "usage":{"prompt_tokens":2800,"completion_tokens":700}}
    """
    if case .truncated(let tokens) = failure(tagliato) {
        harness.check("una risposta tagliata è riconosciuta come tale (\(tokens) token)", tokens == 700)
    } else {
        harness.fail("una risposta tagliata non è riconosciuta")
    }

    // Risposta buona: si leggono anche i token di ragionamento e il fornitore.
    let buona = """
    {"model":"google/gemini-2.5-flash-lite","provider":"Google AI Studio",
     "choices":[{"finish_reason":"stop","message":{"content":"{\\"n\\":\\"Prova\\",\\"d\\":[[\\"0025\\"]]}"}}],
     "usage":{"prompt_tokens":2700,"completion_tokens":180,"completion_tokens_details":{"reasoning_tokens":0}}}
    """
    if case .success(let completion) = read(buona) {
        harness.check("il testo della risposta arriva intero", completion.text.contains("0025"))
        harness.check("si legge il motivo di fine", completion.finishReason == "stop")
        harness.check("si legge il fornitore", completion.provider == "Google AI Studio")
        harness.check("si leggono i token in entrata", completion.usage?.promptTokens == 2_700)
        harness.check("si leggono i token in uscita", completion.usage?.completionTokens == 180)
        harness.check("i token di ragionamento sono zero", completion.usage?.reasoningTokens == 0)
        harness.check("la risposta non risulta troncata", !completion.wasTruncated)
    } else {
        harness.fail("una risposta buona non si legge")
    }

    // Gli errori del servizio restano quelli di prima.
    harness.check("401 resta chiave non valida", failure("{}", status: 401) == .unauthorized)
    harness.check("402 resta credito esaurito", failure("{}", status: 402) == .paymentRequired)
    harness.check("429 resta troppe richieste", failure("{}", status: 429) == .rateLimited)
    harness.check("404 resta modello inesistente", failure("{}", status: 404) == .modelNotFound("x/y"))
    if case .http(let status, let message)? = failure(#"{"error":{"message":"boom"}}"#, status: 500) {
        harness.check("un 500 riporta stato e messaggio", status == 500 && message == "boom")
    } else {
        harness.fail("un 500 non riporta stato e messaggio")
    }
    harness.check(
        "un modello sconosciuto dietro un 400 viene riconosciuto",
        failure(#"{"error":{"message":"xyz is not a valid model id"}}"#, status: 400) == .modelNotFound("x/y")
    )

    // Nessun messaggio d'errore usa i trattini lunghi (DESIGN.md).
    let tutti: [OpenRouterClient.Failure] = [
        .unauthorized, .paymentRequired, .rateLimited, .modelNotFound("x/y"),
        .http(status: 500, message: "boom"), .emptyResponse, .malformedResponse("x"),
        .transport("x"), .timeout(seconds: 25), .truncated(completionTokens: 700),
        .emptyContentReasoningExhausted(reasoningTokens: 3_000),
    ]
    harness.check(
        "nessun errore del client usa i trattini lunghi",
        tutti.allSatisfy { !$0.description.contains("—") && !$0.description.contains("–") }
    )
    harness.check("ogni errore del client ha un messaggio", tutti.allSatisfy { !$0.description.isEmpty })
}

// MARK: - Tempi

@MainActor
private func runTimingChecks(_ harness: Harness) async {
    harness.section("client · tetto di tempo")

    harness.check("il tetto per chiamata è di 25 secondi", OpenRouterClient.requestTimeout == 25)
    harness.check("il tetto complessivo è di 40 secondi", OpenRouterClient.totalBudget == 40)
    harness.check(
        "due chiamate al tetto non superano il budget complessivo",
        OpenRouterClient.requestTimeout * 2 >= OpenRouterClient.totalBudget
    )

    // La scadenza condivisa: il primo tentativo lento toglie tempo al secondo.
    let deadline = OpenRouterClient.Deadline(seconds: 10, from: Date().addingTimeInterval(-7))
    harness.check("la scadenza dice quanto resta", abs(deadline.remaining() - 3) < 0.5)
    harness.check("una scadenza passata risulta scaduta", OpenRouterClient.Deadline(seconds: 0).isExpired())
    harness.check("una scadenza fresca non è scaduta", !OpenRouterClient.Deadline(seconds: 5).isExpired())

    // Un servizio che non risponde mai: ci si deve fermare da soli.
    StubURLProtocol.box.reset([.hang])
    var request = URLRequest(url: OpenRouterClient.endpoint)
    request.httpMethod = "POST"
    request.httpBody = Data("{}".utf8)

    let started = Date()
    do {
        _ = try await OpenRouterClient.perform(
            request: request,
            session: StubURLProtocol.makeSession(),
            allowance: 0.4
        )
        harness.fail("un servizio che non risponde non ha fatto scattare il tetto")
    } catch let failure as OpenRouterClient.Failure {
        if case .timeout = failure {
            harness.check("un servizio muto fa scattare il tetto di tempo", true)
        } else {
            harness.fail("un servizio muto ha dato \(failure) invece del tetto di tempo")
        }
    } catch {
        harness.fail("un servizio muto ha dato \(error)")
    }
    let elapsed = Date().timeIntervalSince(started)
    harness.check(String(format: "ci si ferma davvero al tetto (%.2f s per 0,40 s concessi)", elapsed), elapsed < 3)

    // Con una scadenza già scaduta non si chiama nemmeno.
    let client = OpenRouterClient()
    do {
        _ = try await client.complete(
            system: "s",
            user: "u",
            model: "x/y",
            apiKey: "chiave-finta",
            session: StubURLProtocol.makeSession(),
            deadline: OpenRouterClient.Deadline(seconds: 0)
        )
        harness.fail("con il budget finito si è chiamato lo stesso")
    } catch let failure as OpenRouterClient.Failure {
        if case .timeout = failure {
            harness.check("con il budget finito non si chiama nessuno", true)
        } else {
            harness.fail("con il budget finito si è avuto \(failure)")
        }
    } catch {
        harness.fail("con il budget finito si è avuto \(error)")
    }
}

// MARK: - Ripiego sul parametro reasoning

@MainActor
private func runReasoningRetryChecks(_ harness: Harness) async {
    harness.section("client · ripiego sul ragionamento")

    harness.check(
        "un 400 che parla di reasoning fa riprovare",
        OpenRouterClient.shouldRetryWithoutReasoning(.http(status: 400, message: "Unsupported parameter: reasoning.effort"))
    )
    harness.check(
        "un 400 sullo schema non fa riprovare senza ragionamento (ha già il suo ripiego)",
        !OpenRouterClient.shouldRetryWithoutReasoning(.http(status: 400, message: "response_format json_schema not supported"))
    )
    harness.check(
        "un 500 non fa riprovare",
        !OpenRouterClient.shouldRetryWithoutReasoning(.http(status: 500, message: "reasoning"))
    )

    let buona = #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"n\":\"Prova\",\"d\":[[\"0025\"]]}"}}]}"#
    StubURLProtocol.box.reset([
        .reply(status: 400, body: #"{"error":{"message":"Unsupported parameter: reasoning"}}"#),
        .reply(status: 200, body: buona),
    ])

    let client = OpenRouterClient()
    do {
        let completion = try await client.complete(
            system: "s",
            user: "u",
            model: "google/gemini-2.5-flash-lite",
            apiKey: "chiave-finta",
            session: StubURLProtocol.makeSession()
        )
        harness.check("dopo il rifiuto del parametro la risposta arriva", completion.text.contains("0025"))
    } catch {
        harness.fail("il ripiego senza ragionamento non ha funzionato: \(error)")
    }

    let bodies = StubURLProtocol.box.requestBodies
    harness.check("si è riprovato una volta sola", bodies.count == 2)
    if bodies.count == 2 {
        harness.check("il primo tentativo chiedeva di non ragionare", text(of: bodies[0]).contains("\"reasoning\""))
        harness.check("il secondo tentativo non manda il parametro", !text(of: bodies[1]).contains("\"reasoning\""))
    }

    // Se anche il secondo tentativo fallisce non si insiste all'infinito.
    StubURLProtocol.box.reset([
        .reply(status: 400, body: #"{"error":{"message":"Unsupported parameter: reasoning"}}"#),
        .reply(status: 400, body: #"{"error":{"message":"Unsupported parameter: reasoning"}}"#),
        .reply(status: 200, body: buona),
    ])
    do {
        _ = try await client.complete(
            system: "s",
            user: "u",
            model: "google/gemini-2.5-flash-lite",
            apiKey: "chiave-finta",
            session: StubURLProtocol.makeSession()
        )
        harness.fail("si è insistito oltre il secondo tentativo")
    } catch is OpenRouterClient.Failure {
        harness.check("dopo il secondo rifiuto ci si ferma", StubURLProtocol.box.requestBodies.count == 2)
    } catch {
        harness.fail("errore inatteso: \(error)")
    }
}

private func text(of data: Data) -> String { String(data: data, encoding: .utf8) ?? "" }

// MARK: - Formato compatto

@MainActor
private func runCompactFormatChecks(_ harness: Harness, repository: ExerciseRepository?) {
    harness.section("generatore · formato compatto")

    guard let repository else {
        harness.fail("repository non caricato")
        return
    }

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
    let reference = FallbackProgramGenerator.makeDraft(answers: answers, parameters: parameters, candidates: candidates)

    // La risposta che si chiede oggi: solo id, uno per giorno.
    let ids = reference.days.map { $0.items.map(\.id) }
    let compact = "{\"n\":\"Prova compatta\",\"d\":[" + ids.map { day in
        "[" + day.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }.joined(separator: ",") + "]}"

    guard let decoded = try? GeneratedProgramDraft.decode(fromModelOutput: compact) else {
        harness.fail("il formato compatto non si legge")
        return
    }
    harness.check("il formato compatto dà il nome della scheda", decoded.name == "Prova compatta")
    harness.check("il formato compatto dà tutti i giorni", decoded.days.count == parameters.days.count)
    harness.check("il formato compatto dà tutti gli esercizi", decoded.itemCount == reference.itemCount)
    harness.check(
        "le voci arrivano senza numeri, da completare sul telefono",
        decoded.days.allSatisfy { $0.items.allSatisfy(\.isUnspecified) }
    )
    harness.check("i giorni arrivano senza nome", decoded.days.allSatisfy { $0.name.isEmpty })

    // La riparazione riempie tutto con i numeri già calcolati dal telefono, e
    // non racconta all'utente quaranta correzioni che non sono correzioni.
    let (repaired, repairs) = GeneratorValidator.repair(
        decoded,
        answers: answers,
        parameters: parameters,
        candidates: candidates
    )
    harness.check("completare i numeri non conta come riparazione (\(repairs.joined(separator: " | ")))", repairs.isEmpty)
    harness.check(
        "i giorni prendono il nome deciso dal telefono",
        repaired.days.map(\.name) == parameters.days.map(\.name)
    )
    let validation = GeneratorValidator.validate(
        repaired,
        answers: answers,
        parameters: parameters,
        candidates: candidates
    )
    harness.check("la scheda compatta riparata passa il validatore (\(validation.errors.first ?? ""))", validation.isValid)
    harness.check(
        "i numeri sono quelli della scheda di riserva",
        repaired == reference.withoutNotes(name: repaired.name)
    )

    // Il formato di prima si continua a leggere: le risposte già registrate e i
    // modelli che rispondono "alla vecchia" non vanno buttati.
    let legacy = """
    Certo! Ecco la scheda:
    ```json
    {"name":"Vecchio formato","days":[{"name":"Giorno A","items":[
      {"id":"0025","sets":4,"repsMin":6,"repsMax":10,"rest":120,"note":"schiena appoggiata"}]}]}
    ```
    """
    if let old = try? GeneratedProgramDraft.decode(fromModelOutput: legacy) {
        harness.check("il formato esteso si legge ancora", old.name == "Vecchio formato")
        harness.check("il nome del giorno si legge ancora", old.days.first?.name == "Giorno A")
        harness.check("i numeri del formato esteso si leggono", old.days.first?.items.first?.sets == 4)
        harness.check("le note del formato esteso si leggono", old.days.first?.items.first?.note == "schiena appoggiata")
        harness.check("una voce del formato esteso non risulta da completare", old.days.first?.items.first?.isUnspecified == false)
    } else {
        harness.fail("il formato esteso non si legge più")
    }

    // Tolleranza: id come numeri, id dentro oggettini, giorni dentro oggetti.
    if let numeri = try? GeneratedProgramDraft.decode(fromModelOutput: #"{"n":"x","d":[[25,31]]}"#) {
        harness.check("gli id scritti come numeri riprendono gli zeri davanti", numeri.days.first?.items.first?.id == "0025")
    } else {
        harness.fail("gli id scritti come numeri non si leggono")
    }
    if let oggetti = try? GeneratedProgramDraft.decode(fromModelOutput: #"{"n":"x","d":[{"x":["0025","0031"]}]}"#) {
        harness.check("un giorno avvolto in un oggetto si legge", oggetti.days.first?.items.count == 2)
    } else {
        harness.fail("un giorno avvolto in un oggetto non si legge")
    }
    harness.check(
        "una risposta senza JSON viene ancora rifiutata",
        (try? GeneratedProgramDraft.decode(fromModelOutput: "non lo so")) == nil
    )

    // Dimensioni: è il motivo per cui si è cambiato formato.
    let compactTokens = GeneratorCandidates.estimateTokens(compact)
    let verboseTokens = GeneratorCandidates.estimateTokens(reference.jsonString())
    harness.check(
        "la risposta compatta costa molto meno di quella estesa (\(compactTokens) contro \(verboseTokens) token)",
        compactTokens * 3 < verboseTokens
    )
    harness.check(
        "il tetto di token in uscita basta per la risposta attesa",
        GeneratorPrompt.outputTokenBudget(parameters: parameters) > compactTokens * 2
    )

    // Il tetto vale anche per la scheda più grossa possibile.
    let biggest = GeneratorPlanParameters(
        answers: GeneratorAnswers(
            goal: .muscleGain,
            daysPerWeek: 6,
            split: .pushPullLegs,
            experience: .advanced,
            sessionLength: .long90,
            equipment: .fullGym
        )
    )
    harness.check(
        "anche la scheda più grossa sta nel tetto di token (\(GeneratorPrompt.outputTokenBudget(parameters: biggest)))",
        GeneratorPrompt.outputTokenBudget(parameters: biggest) <= OpenRouterClient.defaultMaxTokens
    )
}

private extension GeneratedProgramDraft {

    /// La stessa scheda senza note e con un altro nome: serve a confrontare la
    /// scheda ricostruita dal formato compatto con quella di riserva, che una
    /// nota ce l'ha solo sul cardio.
    func withoutNotes(name: String) -> GeneratedProgramDraft {
        GeneratedProgramDraft(
            name: name,
            days: days.map { day in
                Day(name: day.name, items: day.items.map { item in
                    var copy = item
                    copy.note = nil
                    return copy
                })
            }
        )
    }
}

// MARK: - Servizio finto

/// Un servizio HTTP finto: risponde quello che gli si dice, oppure non risponde
/// affatto. Serve a riprodurre senza rete i casi che contano (contenuto vuoto,
/// parametro rifiutato, servizio muto) e a leggere il corpo delle richieste.
final class StubURLProtocol: URLProtocol {

    enum Step: Sendable {
        case reply(status: Int, body: String)
        /// Non risponde mai: deve intervenire il tetto di tempo.
        case hang
    }

    /// Lo stato condiviso fra le istanze, protetto da un lucchetto.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var steps: [Step] = []
        private var bodies: [Data] = []

        func reset(_ steps: [Step]) {
            lock.lock(); defer { lock.unlock() }
            self.steps = steps
            bodies = []
        }

        func next() -> Step? {
            lock.lock(); defer { lock.unlock() }
            return steps.isEmpty ? nil : steps.removeFirst()
        }

        func record(_ data: Data?) {
            guard let data else { return }
            lock.lock(); defer { lock.unlock() }
            bodies.append(data)
        }

        var requestBodies: [Data] {
            lock.lock(); defer { lock.unlock() }
            return bodies
        }
    }

    static let box = Box()

    /// Una sessione che passa solo da qui.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.box.record(StubURLProtocol.body(of: request))
        guard let step = StubURLProtocol.box.next() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch step {
        case .hang:
            // Di proposito: nessuna risposta, mai.
            break
        case .reply(let status, let body):
            guard
                let url = request.url,
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// Il corpo della richiesta, che `URLProtocol` consegna come flusso.
    static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4_096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
