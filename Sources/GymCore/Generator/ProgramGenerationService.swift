import Foundation

// Orchestrazione della generazione di una scheda, in un posto solo.
//
// Prima questa sequenza (candidati → prompt → chiamata → decodifica → validazione
// → riparazione → secondo tentativo → esito) viveva solo dentro `GymGeneratorTest`,
// cioè in un eseguibile che l'app non può usare. Rifarla nella schermata avrebbe
// significato due implementazioni che divergono al primo ritocco: qui c'è **una**
// implementazione, pura, senza SwiftUI e senza stato globale, che l'app chiama e i
// check verificano con un client finto.
//
// La chiave arriva come parametro e non viene mai conservata, stampata o inserita
// in un messaggio d'errore: nessun caso di ``ProgramGenerationFailure`` la contiene.

/// Chi sa parlare con il modello. Un protocollo, non ``OpenRouterClient``, così i
/// check possono iniettare un client finto senza toccare la rete.
public protocol ProgramGenerationClient: Sendable {

    /// Chiede una risposta al modello e restituisce il testo dell'assistente.
    ///
    /// - Parameters:
    ///   - apiKey: chiave dell'utente; l'implementazione non deve conservarla.
    ///   - responseFormat: `jsonSchema` al primo colpo, `jsonObject` come ripiego.
    ///   - maxTokens: tetto di token in uscita, calcolato sulla scheda richiesta.
    ///   - deadline: scadenza **condivisa** fra i due tentativi: il primo
    ///     tentativo lento toglie tempo al secondo invece di sommarcisi.
    func complete(
        system: String,
        user: String,
        model: String,
        apiKey: String,
        responseFormat: OpenRouterClient.ResponseFormat,
        maxTokens: Int,
        deadline: OpenRouterClient.Deadline
    ) async throws -> String
}

/// Il client vero: OpenRouter.
public struct OpenRouterGenerationClient: ProgramGenerationClient {

    private let client: OpenRouterClient

    public init(timeout: TimeInterval = OpenRouterClient.requestTimeout) {
        client = OpenRouterClient(timeout: timeout)
    }

    public func complete(
        system: String,
        user: String,
        model: String,
        apiKey: String,
        responseFormat: OpenRouterClient.ResponseFormat,
        maxTokens: Int,
        deadline: OpenRouterClient.Deadline
    ) async throws -> String {
        try await client.complete(
            system: system,
            user: user,
            model: model,
            apiKey: apiKey,
            responseFormat: responseFormat,
            maxTokens: maxTokens,
            deadline: deadline
        ).text
    }
}

/// Da dove arriva la bozza mostrata all'utente.
public enum ProgramGenerationSource: String, Sendable, Hashable {
    /// Scelta dal modello linguistico.
    case ai
    /// Costruita dal generatore deterministico di riserva.
    case fallback

    /// Etichetta discreta da mostrare sopra l'anteprima.
    public var displayName: String {
        switch self {
        case .ai: "Proposta dall'AI"
        case .fallback: "Generata senza AI"
        }
    }
}

/// Una bozza pronta da mostrare: la scheda, da dove viene e cosa è stato sistemato.
public struct ProgramGenerationResult: Sendable {

    public let answers: GeneratorAnswers
    public let parameters: GeneratorPlanParameters
    public let candidates: GeneratorCandidates
    public let draft: GeneratedProgramDraft
    public let source: ProgramGenerationSource
    /// Correzioni applicate dal validatore, in italiano.
    public let repairs: [String]
    /// Rilievi non bloccanti del validatore.
    public let warnings: [String]
    /// Quante chiamate sono servite (0 per la scheda di riserva).
    public let attempts: Int

    public init(
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates,
        draft: GeneratedProgramDraft,
        source: ProgramGenerationSource,
        repairs: [String],
        warnings: [String],
        attempts: Int
    ) {
        self.answers = answers
        self.parameters = parameters
        self.candidates = candidates
        self.draft = draft
        self.source = source
        self.repairs = repairs
        self.warnings = warnings
        self.attempts = attempts
    }

    /// La bozza convertita in ``Program``, pronta da salvare.
    public func program(now: Date) -> Program {
        GeneratorValidator.program(from: draft, answers: answers, candidates: candidates, now: now)
    }
}

/// Perché la generazione non è riuscita.
///
/// Ogni caso porta un messaggio italiano già leggibile e, dove serve, il
/// suggerimento dell'unica cosa utile da fare. Nessun caso contiene la chiave.
public enum ProgramGenerationFailure: Error, Sendable, Hashable, CustomStringConvertible {

    /// Non c'è nessuna chiave nel Portachiavi.
    case missingKey
    /// 401 o 403: chiave sbagliata, revocata o senza permessi.
    case unauthorized
    /// 402: credito esaurito.
    case paymentRequired
    /// 429: troppe richieste.
    case rateLimited
    /// Il modello indicato non esiste.
    case modelNotFound(String)
    /// Niente rete, o il servizio non risponde entro il tempo previsto.
    case offline
    /// Due tentativi e nessuna scheda valida.
    case invalidResponse
    /// Il tempo concesso alla generazione è finito.
    case tooSlow
    /// Il modello non è adatto: ragiona troppo, o tronca la risposta. Cambiarlo
    /// è l'unica cosa che risolve.
    case modelUnsuitable(String)
    /// Qualunque altro errore del servizio.
    case server(String)

    /// Titolo breve dell'errore.
    public var title: String {
        switch self {
        case .missingKey: "Manca la chiave"
        case .unauthorized: "Chiave non valida"
        case .paymentRequired: "Credito esaurito"
        case .rateLimited: "Troppe richieste"
        case .modelNotFound: "Modello non disponibile"
        case .offline: "Niente rete"
        case .invalidResponse: "Risposta non utilizzabile"
        case .tooSlow: "Ci sta mettendo troppo"
        case .modelUnsuitable: "Modello poco adatto"
        case .server: "Servizio non raggiungibile"
        }
    }

    /// Una o due righe che spiegano cosa è successo e cosa fare.
    public var message: String {
        switch self {
        case .missingKey:
            "Serve una chiave OpenRouter per far proporre la scheda dall'AI."
        case .unauthorized:
            "Controlla la chiave in Impostazioni: potrebbe essere sbagliata o revocata."
        case .paymentRequired:
            "Il credito OpenRouter è finito. Ricaricalo dal sito, poi riprova."
        case .rateLimited:
            "Il servizio ha ricevuto troppe richieste di fila. Aspetta un minuto e riprova."
        case .modelNotFound(let model):
            "Il modello \"\(model)\" non esiste più. Cambialo in Impostazioni."
        case .offline:
            "Il telefono non riesce a raggiungere il servizio. Controlla la connessione."
        case .invalidResponse:
            "Il modello ha risposto due volte con una scheda che non sta in piedi."
        case .tooSlow:
            "Il modello non ha risposto nel tempo previsto. Riprova, oppure prendi la scheda senza AI."
        case .modelUnsuitable(let detail):
            detail
        case .server(let detail):
            detail
        }
    }

    public var description: String { "\(title): \(message)" }

    /// `true` quando ha senso proporre "Riprova".
    public var allowsRetry: Bool {
        switch self {
        case .missingKey, .unauthorized, .paymentRequired, .modelNotFound, .modelUnsuitable: false
        case .rateLimited, .offline, .invalidResponse, .tooSlow, .server: true
        }
    }

    /// `true` quando la via d'uscita è aprire le Impostazioni.
    public var pointsToSettings: Bool {
        switch self {
        case .unauthorized, .modelNotFound, .missingKey, .modelUnsuitable: true
        default: false
        }
    }
}

/// Il motore: dalle risposte del wizard a una bozza mostrabile.
///
/// Tutti i metodi sono statici e puri: nessuno stato, nessun singleton, niente da
/// ripulire. L'unica cosa che entra ed esce è un valore.
public enum ProgramGenerationService {

    /// Quante volte si chiede al modello prima di arrendersi (SPEC §0: due).
    public static let maxAttempts = 2

    /// Modello economico di default.
    public static let defaultModel = "google/gemini-2.5-flash-lite"

    // MARK: - Preparazione

    /// Parametri numerici e candidati per quelle risposte.
    ///
    /// È il pezzo che il telefono fa da solo: l'AI non legge il dataset, riceve
    /// solo questo elenco ristretto.
    public static func prepare(
        answers: GeneratorAnswers,
        library: some ExerciseSource
    ) -> (parameters: GeneratorPlanParameters, candidates: GeneratorCandidates) {
        let parameters = GeneratorPlanParameters(answers: answers)
        let candidates = GeneratorCandidates.make(
            answers: answers,
            library: library,
            parameters: parameters
        )
        return (parameters, candidates)
    }

    // MARK: - Senza AI

    /// La scheda di riserva, deterministica: stesso seme, stessa scheda.
    public static func fallback(
        answers: GeneratorAnswers,
        library: some ExerciseSource,
        seed: Int = 0
    ) -> ProgramGenerationResult {
        let (parameters, candidates) = prepare(answers: answers, library: library)
        return fallback(answers: answers, parameters: parameters, candidates: candidates, seed: seed)
    }

    /// Variante che riusa parametri e candidati già calcolati.
    public static func fallback(
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates,
        seed: Int = 0
    ) -> ProgramGenerationResult {
        let draft = FallbackProgramGenerator.makeDraft(
            answers: answers,
            parameters: parameters,
            candidates: candidates,
            seed: seed
        )
        let validation = GeneratorValidator.validate(
            draft,
            answers: answers,
            parameters: parameters,
            candidates: candidates
        )
        return ProgramGenerationResult(
            answers: answers,
            parameters: parameters,
            candidates: candidates,
            draft: draft,
            source: .fallback,
            repairs: [],
            warnings: validation.warnings,
            attempts: 0
        )
    }

    // MARK: - Con l'AI

    /// Chiede la scheda al modello, la ripara e la verifica.
    ///
    /// Sequenza per ogni tentativo: chiamata (con ripiego su `json_object` per i
    /// modelli che rifiutano lo schema stretto) → decodifica → riparazione →
    /// validazione. Se il secondo tentativo non basta, l'errore è
    /// ``ProgramGenerationFailure/invalidResponse`` e chi chiama offrirà la scheda
    /// senza AI.
    ///
    /// - Parameter apiKey: non viene conservata né registrata da nessuna parte.
    /// - Throws: ``ProgramGenerationFailure``, oppure `CancellationError` se il
    ///   `Task` viene annullato (il bottone "Annulla" della schermata d'attesa).
    public static func generate(
        answers: GeneratorAnswers,
        library: some ExerciseSource,
        model: String,
        apiKey: String,
        client: some ProgramGenerationClient,
        maxAttempts: Int = ProgramGenerationService.maxAttempts
    ) async throws -> ProgramGenerationResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProgramGenerationFailure.missingKey
        }
        let (parameters, candidates) = prepare(answers: answers, library: library)
        let system = GeneratorPrompt.system
        let user = GeneratorPrompt.user(answers: answers, parameters: parameters, candidates: candidates)
        let maxTokens = GeneratorPrompt.outputTokenBudget(parameters: parameters, model: model)
        // Scadenza **condivisa**: il primo tentativo lento toglie tempo al
        // secondo invece di sommarcisi, e l'utente non aspetta mai il doppio.
        let deadline = OpenRouterClient.Deadline()

        // Una volta che un modello ha rifiutato lo schema stretto non lo si ripropone.
        var format: OpenRouterClient.ResponseFormat =
            OpenRouterClient.prefersJSONObject(forModel: model) ? .jsonObject : .jsonSchema

        for attempt in 1...max(1, maxAttempts) {
            try Task.checkCancellation()

            let text: String
            do {
                text = try await call(
                    client: client,
                    system: system,
                    user: user,
                    model: model,
                    apiKey: apiKey,
                    maxTokens: maxTokens,
                    deadline: deadline,
                    format: &format
                )
            } catch let failure as ProgramGenerationFailure {
                // Un errore di trasporto o di credito non migliora riprovando
                // subito: si riporta com'è e decide l'utente.
                throw failure
            }

            guard let draft = try? GeneratedProgramDraft.decode(fromModelOutput: text) else {
                // Riprovare ha senso solo se resta tempo per farlo davvero.
                if deadline.isExpired() { throw ProgramGenerationFailure.tooSlow }
                continue
            }

            let (repaired, repairs) = GeneratorValidator.repair(
                draft,
                answers: answers,
                parameters: parameters,
                candidates: candidates
            )
            let validation = GeneratorValidator.validate(
                repaired,
                answers: answers,
                parameters: parameters,
                candidates: candidates
            )
            guard validation.isValid else {
                if deadline.isExpired() { throw ProgramGenerationFailure.tooSlow }
                continue
            }

            return ProgramGenerationResult(
                answers: answers,
                parameters: parameters,
                candidates: candidates,
                draft: repaired,
                source: .ai,
                repairs: repairs,
                warnings: validation.warnings,
                attempts: attempt
            )
        }

        throw ProgramGenerationFailure.invalidResponse
    }

    /// Una chiamata sola, con il ripiego su `json_object` quando il modello
    /// rifiuta lo schema stretto (è il comportamento del banco di prova).
    private static func call(
        client: some ProgramGenerationClient,
        system: String,
        user: String,
        model: String,
        apiKey: String,
        maxTokens: Int,
        deadline: OpenRouterClient.Deadline,
        format: inout OpenRouterClient.ResponseFormat
    ) async throws -> String {
        do {
            return try await client.complete(
                system: system,
                user: user,
                model: model,
                apiKey: apiKey,
                responseFormat: format,
                maxTokens: maxTokens,
                deadline: deadline
            )
        } catch let failure as OpenRouterClient.Failure {
            if format == .jsonSchema, OpenRouterClient.shouldRetryWithoutSchema(failure) {
                format = .jsonObject
                do {
                    return try await client.complete(
                        system: system,
                        user: user,
                        model: model,
                        apiKey: apiKey,
                        responseFormat: .jsonObject,
                        maxTokens: maxTokens,
                        deadline: deadline
                    )
                } catch let second as OpenRouterClient.Failure {
                    throw translate(second, model: model)
                }
            }
            throw translate(failure, model: model)
        }
    }

    /// Traduce l'errore del client in un esito con messaggio e azioni per l'utente.
    ///
    /// - Important: non riporta mai gli header della richiesta, quindi la chiave
    ///   non può finire in un messaggio.
    public static func translate(_ failure: OpenRouterClient.Failure, model: String) -> ProgramGenerationFailure {
        switch failure {
        case .unauthorized: .unauthorized
        case .paymentRequired: .paymentRequired
        case .rateLimited: .rateLimited
        case .modelNotFound: .modelNotFound(model)
        // Il modello c'è ma nessun fornitore lo serve alle nostre condizioni: il
        // client ha già riprovato una volta senza vincoli, quindi qui è finita.
        case .noEndpointsForConstraints:
            .modelUnsuitable(failure.description + " Cambia modello in Impostazioni.")
        case .transport: .offline
        case .emptyResponse, .malformedResponse: .invalidResponse
        case .timeout: .tooSlow
        // Il modello ragiona troppo o tronca: riprovare con lo stesso modello
        // darebbe lo stesso esito, quindi si dice di cambiarlo.
        case .truncated, .emptyContentReasoningExhausted:
            .modelUnsuitable(failure.description + " Cambia modello in Impostazioni.")
        case .http(let status, _): .server("Il servizio ha risposto con un errore (\(status)). Riprova fra poco.")
        }
    }
}
