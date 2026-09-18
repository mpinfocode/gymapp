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
/// - Important: la chiave arriva come parametro a ogni chiamata e non viene mai
///   memorizzata, stampata o inserita in un messaggio d'errore. Chi costruisce
///   messaggi di log a partire da questo tipo non ha modo di ottenerla.
public struct OpenRouterClient: Sendable {

    /// Endpoint delle chat completions.
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Come si chiede al modello di rispondere in JSON.
    public enum ResponseFormat: String, Sendable {
        /// `json_schema` stretto: il modello non può uscire dallo schema.
        case jsonSchema
        /// `json_object`: ripiego per i modelli che non supportano lo schema.
        case jsonObject
    }

    /// Consumo dichiarato dal servizio.
    public struct Usage: Sendable, Hashable {
        public let promptTokens: Int
        public let completionTokens: Int
        public var totalTokens: Int { promptTokens + completionTokens }

        public init(promptTokens: Int, completionTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
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
    }

    /// Errori della chiamata, tutti con un messaggio in italiano già leggibile.
    ///
    /// - Warning: nessun caso porta con sé la chiave o gli header della richiesta.
    public enum Failure: Error, Sendable, CustomStringConvertible {
        case unauthorized
        case paymentRequired
        case rateLimited
        case modelNotFound(String)
        case http(status: Int, message: String)
        case emptyResponse
        case malformedResponse(String)
        case transport(String)

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
            }
        }
    }

    /// Titolo e origine dichiarati a OpenRouter (facoltativi, generici).
    public var appTitle: String
    public var referer: String
    /// Timeout della richiesta, in secondi.
    public var timeout: TimeInterval

    public init(
        appTitle: String = "GymApp",
        referer: String = "https://github.com/gymapp",
        timeout: TimeInterval = 60
    ) {
        self.appTitle = appTitle
        self.referer = referer
        self.timeout = timeout
    }

    // MARK: - Chiamata

    /// Chiede una scheda al modello.
    ///
    /// - Parameters:
    ///   - apiKey: la chiave dell'utente. Non viene conservata né registrata.
    ///   - model: identificativo OpenRouter, es. `"google/gemini-2.5-flash-lite"`.
    public func complete(
        system: String,
        user: String,
        model: String,
        apiKey: String,
        responseFormat: ResponseFormat = .jsonSchema,
        temperature: Double = 0.2,
        maxTokens: Int = 3_000,
        session: URLSession = .shared
    ) async throws -> Completion {
        var request = URLRequest(url: OpenRouterClient.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
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
            maxTokens: maxTokens
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Si riporta solo la descrizione dell'errore di rete: la richiesta,
            // che contiene l'intestazione con la chiave, non viene mai stampata.
            throw Failure.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let rawBody = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(status) else {
            switch status {
            case 401, 403: throw Failure.unauthorized
            case 402: throw Failure.paymentRequired
            case 429: throw Failure.rateLimited
            case 404: throw Failure.modelNotFound(model)
            default:
                let message = OpenRouterClient.errorMessage(in: data) ?? "risposta non interpretabile"
                if message.lowercased().contains("not a valid model") || message.lowercased().contains("no endpoints found") {
                    throw Failure.modelNotFound(model)
                }
                throw Failure.http(status: status, message: message)
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformedResponse("il corpo non è un oggetto JSON")
        }
        if let message = OpenRouterClient.errorMessage(in: data) {
            throw Failure.http(status: status, message: message)
        }
        guard
            let choices = object["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let text = message["content"] as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw Failure.emptyResponse
        }

        var usage: Usage?
        if let raw = object["usage"] as? [String: Any] {
            usage = Usage(
                promptTokens: raw["prompt_tokens"] as? Int ?? 0,
                completionTokens: raw["completion_tokens"] as? Int ?? 0
            )
        }

        return Completion(
            text: text,
            usage: usage,
            model: object["model"] as? String ?? model,
            rawBody: rawBody
        )
    }

    // MARK: - Corpo della richiesta

    /// Costruisce il corpo JSON. Non contiene la chiave: quella sta solo
    /// nell'intestazione `Authorization`.
    func body(
        system: String,
        user: String,
        model: String,
        responseFormat: ResponseFormat,
        temperature: Double,
        maxTokens: Int
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
        case .jsonObject:
            payload["response_format"] = ["type": "json_object"]
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
}
