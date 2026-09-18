import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client minimo per OpenRouter, usato sia dall'app sia dal banco di prova.
///
/// Sta in GymCore di proposito: il prompt, lo schema e la lettura della
/// risposta devono essere **gli stessi** che gira l'app, altrimenti il banco di
/// prova misura una cosa e l'utente ne vede un'altra.
///
/// ## Perché il ragionamento va spento
/// La prima prova reale (18/09/2026, `openai/gpt-5-nano`) è finita quattro volte
/// su quattro con "il servizio ha risposto senza contenuto" dopo 40-75 secondi:
/// il modello spendeva tutto il budget di token a ragionare fra sé e sé, usciva
/// con `finish_reason: "length"` e `message.content` vuoto. Da qui tre scelte:
/// il ragionamento si disattiva esplicitamente, il tempo è limitato da un tetto
/// vero (non solo dal timeout di `URLSession`), e la risposta vuota non è più un
/// errore generico ma una diagnosi precisa.
///
/// - Important: la chiave arriva come parametro a ogni chiamata e non viene mai
///   memorizzata, stampata o inserita in un messaggio d'errore. Chi costruisce
///   messaggi di log a partire da questo tipo non ha modo di ottenerla.
public struct OpenRouterClient: Sendable {

    /// Endpoint delle chat completions.
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // MARK: - Tempi

    /// Tetto per una singola chiamata, in secondi.
    ///
    /// Non è il timeout di `URLSession` (che si azzera a ogni pacchetto e quindi
    /// non limita nulla con un modello lento): è un tetto di orologio da polso
    /// applicato dal client.
    public static let requestTimeout: TimeInterval = 25

    /// Tetto complessivo della generazione, secondo tentativo compreso.
    ///
    /// Deciso dal PM dopo la prima prova: oltre questo si smette di aspettare e
    /// si propone la scheda senza AI.
    public static let totalBudget: TimeInterval = 40

    /// Tempo entro cui una risposta si considera "immediata" per l'utente.
    public static let comfortableSeconds: TimeInterval = 15

    /// Token in uscita concessi di default.
    ///
    /// Con il formato compatto (solo id) una scheda da sei giorni sta in circa
    /// 250 token: 1.200 è già tre volte il necessario, e serve solo a non
    /// troncare un modello che aggiunge spazi o che ignora la richiesta di non
    /// ragionare.
    public static let defaultMaxTokens = 1_200

    // MARK: - Formato della risposta

    /// Come si chiede al modello di rispondere in JSON.
    public enum ResponseFormat: String, Sendable {
        /// `json_schema` stretto: il modello non può uscire dallo schema.
        case jsonSchema
        /// `json_object`: ripiego per i modelli che non supportano lo schema.
        case jsonObject
    }

    // MARK: - Ragionamento

    /// Quanto ragionamento interno si concede al modello.
    ///
    /// OpenRouter normalizza il parametro `reasoning` su tutte le famiglie:
    /// `effort` per i modelli OpenAI, `enabled`/budget per Gemini e Anthropic.
    /// `exclude: true` chiede comunque di non rimandare indietro il testo del
    /// ragionamento, che sarebbero token pagati e tempo perso.
    public enum ReasoningMode: String, Sendable, CaseIterable {
        /// Non si manda nessun parametro: lo decide il modello.
        case untouched
        /// Spento con `enabled: false`.
        ///
        /// È la forma **sicura**: i fornitori che non sanno cosa farsene la
        /// ignorano senza errore, e sui modelli Gemini 2.5 corrisponde al
        /// `thinkingBudget` a zero.
        case off
        /// Spento con `effort: "none"`.
        ///
        /// Più esplicito di ``off`` ma **rifiutato con 400** dai modelli che
        /// dichiarano il ragionamento obbligatorio (`gpt-5-nano`,
        /// `gemini-3.5-flash-lite`…): si usa solo quando si sa di poterlo fare.
        case none
        /// Il minimo previsto dalla famiglia OpenAI (`effort: "minimal"`),
        /// l'unica cosa che si può chiedere a chi ragiona per forza.
        case minimal
        /// Un filo di ragionamento (`effort: "low"`), da usare solo se il minimo
        /// produce schede scadenti.
        case low

        /// Il pezzo di corpo JSON corrispondente, `nil` per `untouched`.
        ///
        /// `exclude: true` è dichiarato supportato da tutti i modelli e chiede
        /// di non rimandare indietro il testo del ragionamento: sarebbero token
        /// pagati, e tempo di attesa, per qualcosa che nessuno legge.
        var payload: [String: Any]? {
            switch self {
            case .untouched: nil
            case .off: ["enabled": false, "exclude": true]
            case .none: ["effort": "none", "exclude": true]
            case .minimal: ["effort": "minimal", "exclude": true]
            case .low: ["effort": "low", "exclude": true]
            }
        }

        public var displayName: String {
            switch self {
            case .untouched: "come decide il modello"
            case .off: "spento"
            case .none: "nessuno"
            case .minimal: "minimo"
            case .low: "basso"
            }
        }
    }

    /// Modelli che dichiarano il ragionamento **obbligatorio**: si può solo
    /// abbassarlo al minimo, e chiedere di spegnerlo produce un 400.
    ///
    /// Confronto per sottostringa sullo slug, così le varianti di data e i
    /// suffissi di fornitore ricadono nella stessa regola.
    static let mandatoryReasoningModels: [String] = [
        "openai/gpt-5-nano",
        "openai/gpt-5-mini",
        "openai/o1",
        "openai/o3",
        "openai/o4",
        "google/gemini-3.5-flash-lite",
        "google/gemini-3.6-flash",
        "google/gemini-3.7-flash",
        "google/gemini-3.8-flash",
    ]

    /// Il modo di ragionare consigliato per quel modello.
    ///
    /// Regola: ``ReasoningMode/off`` per tutti, perché chi non ragiona lo ignora
    /// senza errore; ``ReasoningMode/minimal`` per i pochi che non si lasciano
    /// spegnere. Non si usa mai `effort: "none"` in automatico: è l'unica forma
    /// documentata che può far fallire la richiesta.
    public static func recommendedReasoning(forModel model: String) -> ReasoningMode {
        let lowered = model.lowercased()
        return mandatoryReasoningModels.contains(where: lowered.contains) ? .minimal : .off
    }

    // MARK: - Scelta del fornitore

    /// Come far scegliere a OpenRouter il fornitore che serve la richiesta.
    public enum ProviderRouting: String, Sendable {
        /// Nessuna preferenza: sceglie OpenRouter (di norma per prezzo).
        case none
        /// Minimo tempo alla prima parola.
        case latency
        /// Massimi token al secondo.
        case throughput
    }

    /// Fornitore preferito di default.
    ///
    /// La documentazione definisce `latency` come "minimo tempo alla prima
    /// parola" (si misura in percentili di secondi) e `throughput` come "massimi
    /// token al secondo". Il tempo che l'utente aspetta è la somma dei due, per
    /// cui si ordina per `throughput` e si aggiunge una **preferenza** (non un
    /// vincolo) di bassa latenza: `preferred_max_latency` deprioritizza senza
    /// escludere, quindi non fa mai fallire la richiesta.
    public static let defaultRouting: ProviderRouting = .throughput

    /// Latenza al 90° percentile oltre la quale un fornitore viene messo in
    /// coda alle preferenze, in secondi.
    public static let preferredMaxLatencyP90 = 3

    // MARK: - Consumo

    /// Consumo dichiarato dal servizio.
    public struct Usage: Sendable, Hashable {
        public let promptTokens: Int
        public let completionTokens: Int
        /// Token spesi in ragionamento interno, quando il servizio li dichiara.
        /// Sono compresi in ``completionTokens`` e si pagano come tali.
        public let reasoningTokens: Int
        public var totalTokens: Int { promptTokens + completionTokens }

        public init(promptTokens: Int, completionTokens: Int, reasoningTokens: Int = 0) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.reasoningTokens = reasoningTokens
        }
    }

    /// Risposta grezza.
    public struct Completion: Sendable {
        /// Testo del messaggio dell'assistente.
        public let text: String
        /// Consumo, se il servizio lo ha dichiarato.
        public let usage: Usage?
        /// Identificativo del modello che ha davvero risposto.
        public let model: String
        /// Corpo JSON originale, utile per i rapporti. Non contiene la chiave.
        public let rawBody: String
        /// `stop`, `length`, `content_filter`… come lo dichiara il servizio.
        public let finishReason: String?
        /// Nome del fornitore che ha servito la richiesta, se dichiarato.
        public let provider: String?
        /// Secondi di orologio spesi nella chiamata.
        public let seconds: Double

        public init(
            text: String,
            usage: Usage?,
            model: String,
            rawBody: String,
            finishReason: String? = nil,
            provider: String? = nil,
            seconds: Double = 0
        ) {
            self.text = text
            self.usage = usage
            self.model = model
            self.rawBody = rawBody
            self.finishReason = finishReason
            self.provider = provider
            self.seconds = seconds
        }

        /// `true` se la risposta è stata tagliata dal tetto di token.
        public var wasTruncated: Bool { finishReason == "length" }
    }

    // MARK: - Errori

    /// Errori della chiamata, tutti con un messaggio in italiano già leggibile.
    ///
    /// - Warning: nessun caso porta con sé la chiave o gli header della richiesta.
    public enum Failure: Error, Sendable, Hashable, CustomStringConvertible {
        case unauthorized
        case paymentRequired
        case rateLimited
        case modelNotFound(String)
        case http(status: Int, message: String)
        case emptyResponse
        case malformedResponse(String)
        case transport(String)
        /// La chiamata ha superato il tetto di tempo e ci si è fermati.
        case timeout(seconds: Double)
        /// Il testo c'è ma è stato tagliato a metà dal tetto di token.
        case truncated(completionTokens: Int)
        /// Il testo è vuoto perché il modello ha speso i token a ragionare.
        /// È il caso che ha fatto fallire la prima prova con `gpt-5-nano`.
        case emptyContentReasoningExhausted(reasoningTokens: Int)

        public var description: String {
            switch self {
            case .unauthorized:
                "Chiave non valida o non autorizzata (401)."
            case .paymentRequired:
                "Credito OpenRouter esaurito (402)."
            case .rateLimited:
                "Troppe richieste, riprovare più tardi (429)."
            case .modelNotFound(let model):
                "Il modello \"\(model)\" non esiste o non è disponibile."
            case .http(let status, let message):
                "Errore HTTP \(status): \(message)"
            case .emptyResponse:
                "Il servizio ha risposto senza contenuto."
            case .malformedResponse(let detail):
                "Risposta non interpretabile: \(detail)"
            case .transport(let detail):
                "Errore di rete: \(detail)"
            case .timeout(let seconds):
                "Il modello non ha risposto entro \(Int(seconds.rounded())) secondi."
            case .truncated(let tokens):
                "Risposta tagliata a metà dopo \(tokens) token: la scheda era troppo lunga."
            case .emptyContentReasoningExhausted(let tokens):
                tokens > 0
                    ? "Il modello ha speso \(tokens) token a ragionare e non ha scritto la scheda. Serve un modello più diretto."
                    : "Il modello ha esaurito i token senza scrivere la scheda. Serve un modello più diretto."
            }
        }

        /// `true` quando cambiare modello è l'unica cosa sensata da fare.
        public var suggestsAnotherModel: Bool {
            switch self {
            case .emptyContentReasoningExhausted, .truncated: true
            default: false
            }
        }
    }

    // MARK: - Configurazione

    /// Titolo e origine dichiarati a OpenRouter (facoltativi, generici).
    public var appTitle: String
    public var referer: String
    /// Tetto di tempo per una singola chiamata, in secondi.
    public var timeout: TimeInterval
    /// Preferenza di fornitore mandata a OpenRouter.
    public var routing: ProviderRouting

    public init(
        appTitle: String = "GymApp",
        referer: String = "https://github.com/gymapp",
        timeout: TimeInterval = OpenRouterClient.requestTimeout,
        routing: ProviderRouting = OpenRouterClient.defaultRouting
    ) {
        self.appTitle = appTitle
        self.referer = referer
        self.timeout = timeout
        self.routing = routing
    }

    // MARK: - Scadenza condivisa

    /// Il momento oltre il quale non si aspetta più, condiviso fra i tentativi.
    ///
    /// Si costruisce una volta sola all'inizio della generazione e si passa a
    /// ogni chiamata: così il primo tentativo lento **toglie** tempo al secondo
    /// invece di sommarcisi, e il totale resta sotto ``totalBudget``.
    public struct Deadline: Sendable, Hashable {

        public let expiry: Date

        public init(seconds: TimeInterval = OpenRouterClient.totalBudget, from start: Date = Date()) {
            expiry = start.addingTimeInterval(max(0, seconds))
        }

        public init(expiry: Date) {
            self.expiry = expiry
        }

        /// Secondi che restano, mai negativi.
        public func remaining(at now: Date = Date()) -> TimeInterval {
            max(0, expiry.timeIntervalSince(now))
        }

        public func isExpired(at now: Date = Date()) -> Bool {
            remaining(at: now) <= 0.05
        }
    }

    // MARK: - Chiamata

    /// Chiede una scheda al modello.
    ///
    /// - Parameters:
    ///   - apiKey: la chiave dell'utente. Non viene conservata né registrata.
    ///   - model: identificativo OpenRouter, es. `"google/gemini-2.5-flash-lite"`.
    ///   - reasoning: `nil` significa "quello consigliato per questo modello".
    ///   - deadline: tetto condiviso fra più tentativi; il tempo concesso è il
    ///     minore fra quello che resta e ``timeout``.
    public func complete(
        system: String,
        user: String,
        model: String,
        apiKey: String,
        responseFormat: ResponseFormat = .jsonSchema,
        temperature: Double = 0.1,
        maxTokens: Int = OpenRouterClient.defaultMaxTokens,
        session: URLSession = .shared,
        reasoning: ReasoningMode? = nil,
        deadline: Deadline? = nil
    ) async throws -> Completion {
        let mode = reasoning ?? OpenRouterClient.recommendedReasoning(forModel: model)
        do {
            return try await send(
                system: system,
                user: user,
                model: model,
                apiKey: apiKey,
                responseFormat: responseFormat,
                temperature: temperature,
                maxTokens: maxTokens,
                session: session,
                reasoning: mode,
                deadline: deadline
            )
        } catch let failure as Failure {
            // Un solo nuovo tentativo, e solo se il servizio ha rifiutato
            // proprio il parametro `reasoning`: alcuni fornitori restituiscono
            // 400 invece di ignorarlo.
            guard mode != .untouched, OpenRouterClient.shouldRetryWithoutReasoning(failure) else { throw failure }
            return try await send(
                system: system,
                user: user,
                model: model,
                apiKey: apiKey,
                responseFormat: responseFormat,
                temperature: temperature,
                maxTokens: maxTokens,
                session: session,
                reasoning: .untouched,
                deadline: deadline
            )
        }
    }

    private func send(
        system: String,
        user: String,
        model: String,
        apiKey: String,
        responseFormat: ResponseFormat,
        temperature: Double,
        maxTokens: Int,
        session: URLSession,
        reasoning: ReasoningMode,
        deadline: Deadline?
    ) async throws -> Completion {
        let started = Date()
        // Tempo concesso: il minore fra il tetto per chiamata e quel che resta
        // del budget complessivo.
        let allowance = min(timeout, deadline?.remaining(at: started) ?? timeout)
        guard allowance > 0.5 else { throw Failure.timeout(seconds: max(0, allowance)) }

        var request = URLRequest(url: OpenRouterClient.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = allowance
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(appTitle, forHTTPHeaderField: "X-Title")
        request.httpBody = try body(
            system: system,
            user: user,
            model: model,
            responseFormat: responseFormat,
            temperature: temperature,
            maxTokens: maxTokens,
            reasoning: reasoning
        )

        let raw = try await OpenRouterClient.perform(request: request, session: session, allowance: allowance)
        let elapsed = Date().timeIntervalSince(started)
        return try OpenRouterClient.read(raw, model: model, seconds: elapsed)
    }

    // MARK: - Rete con tetto di tempo

    /// Quel poco che serve della risposta HTTP, e che si può passare fra task.
    public struct RawResponse: Sendable {
        public let data: Data
        public let status: Int

        public init(data: Data, status: Int) {
            self.data = data
            self.status = status
        }
    }

    /// Esegue la richiesta e si ferma comunque dopo `allowance` secondi.
    ///
    /// `URLRequest.timeoutInterval` non basta: si azzera a ogni pacchetto, e un
    /// modello che "ragiona" tiene la connessione aperta senza mandare nulla di
    /// utile. Qui la chiamata corre contro un orologio e perde.
    public static func perform(
        request: URLRequest,
        session: URLSession,
        allowance: TimeInterval
    ) async throws -> RawResponse {
        try await withThrowingTaskGroup(of: RawResponse?.self) { group in
            group.addTask {
                do {
                    let (data, response) = try await session.data(for: request)
                    return RawResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Si riporta solo la descrizione dell'errore di rete: la
                    // richiesta, che contiene l'intestazione con la chiave, non
                    // viene mai stampata.
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
                        throw Failure.timeout(seconds: allowance)
                    }
                    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                        throw CancellationError()
                    }
                    throw Failure.transport(error.localizedDescription)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(allowance * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            while let next = try await group.next() {
                if let next { return next }
                throw Failure.timeout(seconds: allowance)
            }
            throw Failure.timeout(seconds: allowance)
        }
    }

    // MARK: - Lettura della risposta

    /// Interpreta il corpo restituito dal servizio e diagnostica il caso
    /// "nessun contenuto" invece di liquidarlo con un messaggio generico.
    public static func read(_ raw: RawResponse, model: String, seconds: Double = 0) throws -> Completion {
        let data = raw.data
        let rawBody = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(raw.status) else {
            switch raw.status {
            case 401, 403: throw Failure.unauthorized
            case 402: throw Failure.paymentRequired
            case 429: throw Failure.rateLimited
            case 404: throw Failure.modelNotFound(model)
            default:
                let message = errorMessage(in: data) ?? "risposta non interpretabile"
                let lowered = message.lowercased()
                if lowered.contains("not a valid model") || lowered.contains("no endpoints found") {
                    throw Failure.modelNotFound(model)
                }
                throw Failure.http(status: raw.status, message: message)
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformedResponse("il corpo non è un oggetto JSON")
        }
        if let message = errorMessage(in: data) {
            throw Failure.http(status: raw.status, message: message)
        }

        let usage = readUsage(object["usage"])
        let choice = (object["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]
        let finishReason = (choice?["finish_reason"] as? String)
            ?? (choice?["native_finish_reason"] as? String)
        let text = (message?["content"] as? String) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            // Il caso che ha fatto fallire la prima prova: il modello ha
            // "pensato" fino a esaurire il budget e non ha scritto nulla.
            let reasoningTokens = usage?.reasoningTokens ?? 0
            let thought = (message?["reasoning"] as? String)?.isEmpty == false
            if finishReason == "length" || reasoningTokens > 0 || thought {
                throw Failure.emptyContentReasoningExhausted(reasoningTokens: reasoningTokens)
            }
            throw Failure.emptyResponse
        }

        if finishReason == "length" {
            throw Failure.truncated(completionTokens: usage?.completionTokens ?? 0)
        }

        return Completion(
            text: text,
            usage: usage,
            model: object["model"] as? String ?? model,
            rawBody: rawBody,
            finishReason: finishReason,
            provider: object["provider"] as? String,
            seconds: seconds
        )
    }

    /// Legge `usage`, compresi i token di ragionamento quando ci sono.
    public static func readUsage(_ value: Any?) -> Usage? {
        guard let raw = value as? [String: Any] else { return nil }
        let details = raw["completion_tokens_details"] as? [String: Any]
        return Usage(
            promptTokens: raw["prompt_tokens"] as? Int ?? 0,
            completionTokens: raw["completion_tokens"] as? Int ?? 0,
            reasoningTokens: details?["reasoning_tokens"] as? Int ?? raw["reasoning_tokens"] as? Int ?? 0
        )
    }

    // MARK: - Corpo della richiesta

    /// Costruisce il corpo JSON. Non contiene la chiave: quella sta solo
    /// nell'intestazione `Authorization`.
    public func body(
        system: String,
        user: String,
        model: String,
        responseFormat: ResponseFormat,
        temperature: Double,
        maxTokens: Int,
        reasoning: ReasoningMode = .untouched
    ) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if let value = reasoning.payload {
            payload["reasoning"] = value
        }

        var provider: [String: Any] = [:]
        switch routing {
        case .none:
            break
        case .latency:
            provider["sort"] = "latency"
        case .throughput:
            provider["sort"] = "throughput"
            provider["preferred_max_latency"] = ["p90": OpenRouterClient.preferredMaxLatencyP90]
        }

        switch responseFormat {
        case .jsonSchema:
            payload["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": GeneratorPrompt.schemaName,
                    "strict": true,
                    "schema": GeneratorPrompt.jsonSchemaObject(),
                ],
            ]
            // Con lo schema stretto il fornitore che non lo sa fare va escluso,
            // altrimenti risponde in prosa e il tentativo è sprecato.
            provider["require_parameters"] = true
        case .jsonObject:
            payload["response_format"] = ["type": "json_object"]
        }

        if !provider.isEmpty {
            payload["provider"] = provider
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Estrae il messaggio d'errore dal corpo di OpenRouter, se c'è.
    static func errorMessage(in data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        return error["message"] as? String ?? "errore senza messaggio"
    }

    /// `true` se conviene riprovare la stessa richiesta senza lo schema stretto.
    ///
    /// Alcuni modelli economici rifiutano `json_schema` con un 400 parlante:
    /// invece di dichiarare il modello inutilizzabile si riprova con
    /// `json_object`, che tutti supportano.
    public static func shouldRetryWithoutSchema(_ failure: Failure) -> Bool {
        guard case .http(let status, let message) = failure else { return false }
        guard status == 400 || status == 422 else { return false }
        let lowered = message.lowercased()
        return lowered.contains("json_schema")
            || lowered.contains("response_format")
            || lowered.contains("structured")
            || lowered.contains("schema")
    }

    /// `true` se il servizio ha rifiutato proprio il parametro `reasoning`.
    ///
    /// Vale la pena di un solo nuovo tentativo senza: il modello ragionerà a
    /// modo suo, ma almeno risponde.
    public static func shouldRetryWithoutReasoning(_ failure: Failure) -> Bool {
        guard case .http(let status, let message) = failure else { return false }
        guard status == 400 || status == 422 else { return false }
        let lowered = message.lowercased()
        // "schema" compare anche qui: si controlla prima che non sia il caso
        // dello structured output, che ha già il suo ripiego.
        guard !shouldRetryWithoutSchema(failure) else { return false }
        return lowered.contains("reasoning")
            || lowered.contains("thinking")
            || lowered.contains("effort")
            || lowered.contains("include_reasoning")
    }
}
