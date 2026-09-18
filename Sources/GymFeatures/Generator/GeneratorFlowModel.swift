import Foundation
import Observation
import GymCore

/// Lo stato del wizard "crea scheda con l'AI": le risposte, il passo corrente e
/// la fase (domande, riepilogo, attesa, errore, anteprima).
///
/// È un oggetto e non una manciata di `@State` perché la generazione è un `Task`
/// annullabile che deve sopravvivere al ridisegno della schermata, e perché le
/// regole fra le risposte (la divisione che dipende dai giorni, il massimo di due
/// zone su cui insistere) devono stare in un posto solo e verificabile.
///
/// Niente qui tocca la rete: la chiamata la fa ``ProgramGenerationService``.
@MainActor
@Observable
final class GeneratorFlowModel {

    /// A che punto è il flusso.
    enum Phase: Equatable {
        /// Una delle dieci domande.
        case questions
        /// Riepilogo delle risposte, con "Crea scheda".
        case summary
        /// Non c'è nessuna chiave: si spiega a cosa serve e si offre il senza AI.
        case missingKey
        /// Generazione in corso.
        case generating
        /// Generazione fallita.
        case failed(ProgramGenerationFailure)
        /// Bozza pronta da guardare.
        case preview
    }

    // MARK: - Passo e fase

    var step: GeneratorStep = .goal
    var phase: Phase = .questions

    // MARK: - Risposte

    var goal: TrainingGoal = .muscleGain

    var daysPerWeek = 3 {
        didSet {
            // Cambiando i giorni una divisione può non essere più possibile: si
            // torna a "Consigliata" invece di tenere una scelta impossibile.
            if let choice = splitChoice, !GeneratorAnswers.availableSplits(forDays: daysPerWeek).contains(choice) {
                splitChoice = nil
            }
        }
    }

    /// Divisione scelta a mano; `nil` vuol dire "Consigliata".
    var splitChoice: TrainingSplit?

    var experience: TrainingExperience = .beginner
    var sessionLength: SessionLength = .medium60
    var equipment: EquipmentAvailability = .fullGym
    var focusGroups: Set<MuscleGroup> = []
    var protectedZones: Set<StressZone> = []
    var includeCardio = false
    var weeks = 6

    /// Al massimo due zone su cui insistere (SPEC §0).
    static let maxFocusGroups = 2

    // MARK: - Esito

    /// La bozza pronta, con la sua provenienza e le riparazioni fatte.
    private(set) var result: ProgramGenerationResult?
    /// Nome proposto per la scheda, modificabile nell'anteprima.
    var draftName = ""
    /// Seme della scheda senza AI: "Rigenera" lo cambia.
    private var fallbackSeed = 0
    /// Il `Task` della generazione, annullabile dal bottone "Annulla".
    private var work: Task<Void, Never>?

    // MARK: - Risposte complete

    /// La divisione che verrà davvero usata (risolve "Consigliata").
    var resolvedSplit: TrainingSplit {
        splitChoice ?? GeneratorAnswers.recommendedSplit(days: daysPerWeek, experience: experience)
    }

    /// Divisioni proponibili con i giorni scelti.
    var availableSplits: [TrainingSplit] {
        GeneratorAnswers.availableSplits(forDays: daysPerWeek)
    }

    /// Le risposte nel formato che il motore si aspetta.
    var answers: GeneratorAnswers {
        GeneratorAnswers(
            goal: goal,
            daysPerWeek: daysPerWeek,
            split: resolvedSplit,
            experience: experience,
            sessionLength: sessionLength,
            equipment: equipment,
            focusGroups: focusGroups,
            protectedZones: protectedZones,
            includeCardio: includeCardio,
            weeks: weeks
        )
    }

    // MARK: - Navigazione fra le domande

    /// Avanza alla domanda successiva, o al riepilogo se era l'ultima.
    func advance() {
        if let next = step.next {
            step = next
        } else {
            phase = .summary
        }
    }

    /// Torna indietro di un passo. Dal riepilogo si rientra sull'ultima domanda.
    func goBack() {
        switch phase {
        case .summary:
            phase = .questions
            step = .weeks
        case .questions:
            guard let previous = step.previous else { return }
            step = previous
        default:
            phase = .questions
        }
    }

    /// `true` se dal passo corrente si può tornare indietro.
    var canGoBack: Bool {
        phase == .summary || step.previous != nil
    }

    /// Salta dal riepilogo alla domanda toccata.
    func jump(to step: GeneratorStep) {
        self.step = step
        phase = .questions
    }

    // MARK: - Selezioni multiple

    /// Accende o spegne una zona su cui insistere, rispettando il massimo di due.
    /// Restituisce `false` se il tocco è stato ignorato perché si era al limite.
    @discardableResult
    func toggleFocus(_ group: MuscleGroup) -> Bool {
        if focusGroups.contains(group) {
            focusGroups.remove(group)
            return true
        }
        guard focusGroups.count < Self.maxFocusGroups else { return false }
        focusGroups.insert(group)
        return true
    }

    /// Accende o spegne una zona da proteggere.
    func toggleProtected(_ zone: StressZone) {
        if protectedZones.contains(zone) {
            protectedZones.remove(zone)
        } else {
            protectedZones.insert(zone)
        }
    }

    /// Salta una domanda facoltativa azzerandone la risposta.
    func skipCurrentQuestion() {
        switch step {
        case .focus: focusGroups = []
        case .protect: protectedZones = []
        default: break
        }
        advance()
    }

    // MARK: - Generazione

    /// Parte dal riepilogo: con la chiave chiama il modello, senza chiave spiega
    /// prima a cosa serve.
    func start(app: AppEnvironment) {
        guard app.ai.status.hasKey, let key = app.ai.apiKey() else {
            phase = .missingKey
            return
        }
        generateWithAI(app: app, apiKey: key)
    }

    /// Chiede la scheda al modello. Il lavoro sta in un `Task` annullabile e gira
    /// fuori dal main actor: la schermata d'attesa resta fluida.
    func generateWithAI(app: AppEnvironment, apiKey: String? = nil) {
        guard let library = app.exercises else {
            phase = .failed(.server("La libreria esercizi non è pronta. Riprova fra un istante."))
            return
        }
        guard let key = apiKey ?? app.ai.apiKey() else {
            phase = .missingKey
            return
        }
        let request = answers
        let model = app.ai.model

        work?.cancel()
        phase = .generating
        work = Task { [weak self] in
            do {
                let produced = try await ProgramGenerationService.generate(
                    answers: request,
                    library: library,
                    model: model,
                    apiKey: key,
                    client: OpenRouterGenerationClient()
                )
                guard !Task.isCancelled else { return }
                self?.present(produced)
            } catch is CancellationError {
                return
            } catch let failure as ProgramGenerationFailure {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(failure)
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(.server("Qualcosa è andato storto. Riprova fra poco."))
            }
        }
    }

    /// Costruisce la scheda senza AI. `newSeed` serve a "Rigenera": stesso seme,
    /// stessa scheda; seme diverso, seconde scelte al posto delle prime.
    func generateWithoutAI(app: AppEnvironment, newSeed: Bool = false) {
        guard let library = app.exercises else {
            phase = .failed(.server("La libreria esercizi non è pronta. Riprova fra un istante."))
            return
        }
        if newSeed { fallbackSeed += 1 }
        let request = answers
        let seed = fallbackSeed

        work?.cancel()
        phase = .generating
        work = Task { [weak self] in
            // Fuori dal main actor: la selezione dei candidati è breve, ma la
            // schermata d'attesa non deve avere nemmeno un fotogramma perso.
            let produced = await Task.detached(priority: .userInitiated) {
                ProgramGenerationService.fallback(answers: request, library: library, seed: seed)
            }.value
            guard !Task.isCancelled else { return }
            self?.present(produced)
        }
    }

    /// "Rigenera" dall'anteprima: rifà con la stessa sorgente della bozza attuale.
    func regenerate(app: AppEnvironment) {
        if result?.source == .fallback {
            generateWithoutAI(app: app, newSeed: true)
        } else {
            generateWithAI(app: app)
        }
    }

    /// Annulla la generazione in corso e torna al riepilogo.
    func cancelGeneration() {
        work?.cancel()
        work = nil
        phase = .summary
    }

    /// Ferma tutto: la chiama la sheet quando si chiude.
    func stop() {
        work?.cancel()
        work = nil
    }

    private func present(_ produced: ProgramGenerationResult) {
        result = produced
        draftName = produced.draft.name
        phase = .preview
    }

    // MARK: - Salvataggio

    /// La scheda pronta da salvare, con il nome eventualmente ritoccato.
    func program(now: Date) -> Program? {
        guard let result else { return nil }
        var program = result.program(now: now)
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { program.name = name }
        return program
    }
}
