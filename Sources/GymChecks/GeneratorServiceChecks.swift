import Foundation
import GymCore

/// Verifica l'orchestrazione di ``ProgramGenerationService`` con un client finto:
/// nessuna rete, nessuna chiave, risposte decise dal test.
///
/// Quello che conta qui non è il contenuto della scheda (lo coprono già
/// `GeneratorChecks`), ma la **sequenza**: quante chiamate si fanno, quando si
/// ripiega su `json_object`, cosa succede se la prima risposta è spazzatura e la
/// seconda buona, e come si traduce ogni errore del servizio in un messaggio
/// italiano che non contiene la chiave.
@MainActor
func runGeneratorServiceChecks(_ harness: Harness, repository: ExerciseRepository?) async {
    harness.section("generatore · servizio")

    guard let repository else {
        harness.fail("repository non caricato")
        return
    }

    let answers = GeneratorAnswers(
        goal: .muscleGain,
        daysPerWeek: 3,
        split: .fullBody,
        experience: .beginner,
        sessionLength: .medium60,
        equipment: .fullGym,
        weeks: 6
    )
    let (parameters, candidates) = ProgramGenerationService.prepare(answers: answers, library: repository)

    // Riferimento: la scheda di riserva è sempre valida, quindi serve anche come
    // "risposta perfetta" da far dire al client finto.
    let reference = ProgramGenerationService.fallback(
        answers: answers,
        parameters: parameters,
        candidates: candidates
    )
    harness.check("la scheda di riserva arriva dal generatore senza AI", reference.source == .fallback)
    harness.check("la scheda di riserva non richiede riparazioni", reference.repairs.isEmpty)
    harness.check("la scheda di riserva ha i giorni previsti", reference.draft.days.count == parameters.days.count)

    let goodJSON = reference.draft.jsonString()

    // Il seme cambia davvero la scheda ("Rigenera" senza AI).
    let reseeded = ProgramGenerationService.fallback(
        answers: answers,
        parameters: parameters,
        candidates: candidates,
        seed: 3
    )
    harness.check(
        "un seme diverso cambia la scheda di riserva",
        reseeded.draft.jsonString() != goodJSON
    )
    harness.check(
        "lo stesso seme dà sempre la stessa scheda",
        ProgramGenerationService.fallback(
            answers: answers,
            parameters: parameters,
            candidates: candidates,
            seed: 3
        ).draft.jsonString() == reseeded.draft.jsonString()
    )

    // MARK: - Primo colpo buono

    await runServiceCase(harness, "una risposta valida basta un tentativo") {
        let client = FakeGenerationClient(replies: [.text(goodJSON)])
        let result = try await ProgramGenerationService.generate(
            answers: answers,
            library: repository,
            model: "finto/modello",
            apiKey: "chiave-finta",
            client: client
        )
        harness.check("la bozza arriva dall'AI", result.source == .ai)
        harness.check("è bastato un tentativo", result.attempts == 1)
        harness.check("una sola chiamata al servizio", client.callCount == 1)
        harness.check("il primo colpo usa lo schema stretto", client.formats.first == .jsonSchema)
        harness.check("la scheda si converte in Program", result.program(now: Date()).days.count == parameters.days.count)
    }

    // MARK: - Primo colpo inutilizzabile, secondo buono

    await runServiceCase(harness, "la prima risposta non è JSON, la seconda sì") {
        let client = FakeGenerationClient(replies: [
            .text("Certo! Ecco la tua scheda, buon allenamento."),
            .text(goodJSON),
        ])
        let result = try await ProgramGenerationService.generate(
            answers: answers,
            library: repository,
            model: "finto/modello",
            apiKey: "chiave-finta",
            client: client
        )
        harness.check("il secondo tentativo salva la generazione", result.attempts == 2)
        harness.check("due chiamate in tutto", client.callCount == 2)
    }

    // MARK: - Riparazione

    await runServiceCase(harness, "una scheda con difetti piccoli viene riparata") {
        var broken = reference.draft
        broken.name = "Scheda — di prova"
        if !broken.days.isEmpty, !broken.days[0].items.isEmpty {
            broken.days[0].items[0].rest = 5_000
            broken.days[0].items.append(broken.days[0].items[0])
        }
        let client = FakeGenerationClient(replies: [.text(broken.jsonString())])
        let result = try await ProgramGenerationService.generate(
            answers: answers,
            library: repository,
            model: "finto/modello",
            apiKey: "chiave-finta",
            client: client
        )
        harness.check("il validatore segnala le riparazioni fatte", !result.repairs.isEmpty)
        harness.check("il trattino lungo sparisce dal nome", !result.draft.name.contains("—"))
        harness.check("il doppione sparisce", result.draft.days.first.map { day in
            Set(day.items.map(\.id)).count == day.items.count
        } ?? false)
    }

    // MARK: - Due risposte inutilizzabili

    await runServiceExpectingFailure(
        harness,
        "due risposte non valide portano a invalidResponse",
        expected: .invalidResponse
    ) {
        let client = FakeGenerationClient(replies: [.text("niente"), .text("neanche")])
        _ = try await ProgramGenerationService.generate(
            answers: answers,
            library: repository,
            model: "finto/modello",
            apiKey: "chiave-finta",
            client: client
        )
    }

    // MARK: - Ripiego su json_object

    await runServiceCase(harness, "se lo schema stretto è rifiutato si ripiega su json_object") {
        let client = FakeGenerationClient(replies: [
            .failure(.http(status: 400, message: "response_format json_schema is not supported")),
            .text(goodJSON),
        ])
        let result = try await ProgramGenerationService.generate(
            answers: answers,
            library: repository,
            model: "finto/modello",
            apiKey: "chiave-finta",
            client: client
        )
        harness.check("il ripiego resta dentro il primo tentativo", result.attempts == 1)
        harness.check("il secondo colpo usa json_object", client.formats.last == .jsonObject)
    }

    // MARK: - Errori del servizio

    let translations: [(OpenRouterClient.Failure, ProgramGenerationFailure, String)] = [
        (.unauthorized, .unauthorized, "401"),
        (.paymentRequired, .paymentRequired, "402"),
        (.rateLimited, .rateLimited, "429"),
        (.transport("offline"), .offline, "rete"),
    ]
    for (raw, expected, label) in translations {
        await runServiceExpectingFailure(harness, "errore \(label) tradotto correttamente", expected: expected) {
            let client = FakeGenerationClient(replies: [.failure(raw)])
            _ = try await ProgramGenerationService.generate(
                answers: answers,
                library: repository,
                model: "finto/modello",
                apiKey: "chiave-finta",
                client: client
            )
        }
    }

    await runServiceExpectingFailure(
        harness,
        "un modello inesistente lo dice con il suo nome",
        expected: .modelNotFound("finto/modello")
    ) {
        let client = FakeGenerationClient(replies: [.failure(.modelNotFound("finto/modello"))])
        _ = try await ProgramGenerationService.generate(
            answers: answers,
            library: repository,
            model: "finto/modello",
            apiKey: "chiave-finta",
            client: client
        )
    }

    // MARK: - Chiave assente e chiave mai esposta

    await runServiceExpectingFailure(harness, "senza chiave non si chiama nessuno", expected: .missingKey) {
        let client = FakeGenerationClient(replies: [.text(goodJSON)])
        _ = try await ProgramGenerationService.generate(
            answers: answers,
            library: repository,
            model: "finto/modello",
            apiKey: "   ",
            client: client
        )
        harness.check("nessuna chiamata senza chiave", client.callCount == 0)
    }

    let secret = "sk-or-v1-segretissima"
    await runServiceExpectingFailure(harness, "l'errore non contiene mai la chiave", expected: .unauthorized) {
        let client = FakeGenerationClient(replies: [.failure(.unauthorized)])
        do {
            _ = try await ProgramGenerationService.generate(
                answers: answers,
                library: repository,
                model: "finto/modello",
                apiKey: secret,
                client: client
            )
        } catch let failure as ProgramGenerationFailure {
            harness.check("il titolo non contiene la chiave", !failure.title.contains(secret))
            harness.check("il messaggio non contiene la chiave", !failure.message.contains(secret))
            harness.check("la descrizione non contiene la chiave", !failure.description.contains(secret))
            throw failure
        }
    }

    // MARK: - Messaggi

    let allFailures: [ProgramGenerationFailure] = [
        .missingKey, .unauthorized, .paymentRequired, .rateLimited,
        .modelNotFound("x/y"), .offline, .invalidResponse, .server("Errore del servizio."),
    ]
    let withDashes = allFailures.filter { $0.message.contains("—") || $0.message.contains("–") }
    harness.check("nessun messaggio d'errore usa i trattini lunghi", withDashes.isEmpty)
    harness.check(
        "ogni errore ha titolo e messaggio non vuoti",
        allFailures.allSatisfy { !$0.title.isEmpty && !$0.message.isEmpty }
    )
    harness.check("la chiave non valida rimanda alle Impostazioni", ProgramGenerationFailure.unauthorized.pointsToSettings)
    harness.check("il credito esaurito non propone di riprovare", !ProgramGenerationFailure.paymentRequired.allowsRetry)
    harness.check("una risposta non valida propone di riprovare", ProgramGenerationFailure.invalidResponse.allowsRetry)

    // MARK: - Annullamento

    await runServiceCase(harness, "il Task annullato interrompe la generazione") {
        let client = FakeGenerationClient(replies: [.text(goodJSON)], delayNanoseconds: 200_000_000)
        let task = Task {
            try await ProgramGenerationService.generate(
                answers: answers,
                library: repository,
                model: "finto/modello",
                apiKey: "chiave-finta",
                client: client
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            harness.fail("la generazione annullata ha comunque prodotto una scheda")
        } catch is CancellationError {
            harness.check("l'annullamento arriva come CancellationError", true)
        } catch {
            // Il client finto può accorgersi dell'annullamento durante l'attesa:
            // anche quello è un annullamento, non un errore da mostrare.
            harness.check("l'annullamento non diventa un errore del servizio", !(error is ProgramGenerationFailure))
        }
    }
}

// MARK: - Client finto

/// Risposta preconfezionata del client finto.
enum FakeGenerationReply: Sendable {
    case text(String)
    case failure(OpenRouterClient.Failure)
}

/// Client che non tocca la rete: restituisce le risposte nell'ordine dato e
/// registra con quale formato è stato chiamato.
final class FakeGenerationClient: ProgramGenerationClient, @unchecked Sendable {

    private let lock = NSLock()
    private var replies: [FakeGenerationReply]
    private var calls = 0
    private var recordedFormats: [OpenRouterClient.ResponseFormat] = []
    private let delayNanoseconds: UInt64

    init(replies: [FakeGenerationReply], delayNanoseconds: UInt64 = 0) {
        self.replies = replies
        self.delayNanoseconds = delayNanoseconds
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    var formats: [OpenRouterClient.ResponseFormat] {
        lock.lock(); defer { lock.unlock() }
        return recordedFormats
    }

    func complete(
        system: String,
        user: String,
        model: String,
        apiKey: String,
        responseFormat: OpenRouterClient.ResponseFormat,
        maxTokens: Int,
        deadline: OpenRouterClient.Deadline
    ) async throws -> String {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let reply: FakeGenerationReply? = {
            lock.lock(); defer { lock.unlock() }
            calls += 1
            recordedFormats.append(responseFormat)
            return replies.isEmpty ? nil : replies.removeFirst()
        }()
        switch reply {
        case .text(let text): return text
        case .failure(let failure): throw failure
        case nil: throw OpenRouterClient.Failure.emptyResponse
        }
    }
}

// MARK: - Piccoli aiuti

/// Esegue un caso asincrono e segnala come fallimento ogni errore inatteso.
@MainActor
private func runServiceCase(
    _ harness: Harness,
    _ label: String,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
    } catch {
        harness.fail("\(label): errore inatteso (\(error))")
    }
}

/// Come ``runServiceCase`` ma pretende un errore preciso.
@MainActor
private func runServiceExpectingFailure(
    _ harness: Harness,
    _ label: String,
    expected: ProgramGenerationFailure,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        harness.fail("\(label): atteso \(expected), nessun errore sollevato")
    } catch let failure as ProgramGenerationFailure {
        harness.check(label, failure == expected)
    } catch {
        harness.fail("\(label): atteso \(expected), ottenuto \(error)")
    }
}
