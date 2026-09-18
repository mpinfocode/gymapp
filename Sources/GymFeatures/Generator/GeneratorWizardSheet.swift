import SwiftUI
import GymCore
import GymUI

/// Da dove far partire il wizard. Serve **solo** agli screenshot: nell'app il
/// flusso comincia sempre dalla prima domanda.
public enum GeneratorWizardStart: Sendable, Hashable {
    /// Una delle dieci domande, per numero (1...10).
    case question(Int)
    /// Il riepilogo, con tutte le risposte già date.
    case summary
    /// La schermata d'attesa.
    case waiting
    /// La schermata "serve una chiave".
    case missingKey
    /// Una schermata d'errore, con l'errore indicato.
    case failure(ProgramGenerationFailure)
    /// L'anteprima di una bozza costruita dal generatore senza AI.
    case preview
}

/// Il wizard "crea scheda con l'AI": dieci domande, riepilogo, attesa, anteprima.
///
/// Sta tutto in una sheet a tutta altezza e in un solo `View`: le pagine non sono
/// spinte in un `NavigationStack` ma sostituite, perché il flusso non ha una
/// gerarchia (non si "entra" in una domanda, ci si passa attraverso) e perché
/// così "Indietro" ha lo stesso significato ovunque.
///
/// Chi la apre resta responsabile della chiusura: ``onFinished`` viene chiamata
/// solo quando la scheda è stata davvero salvata.
public struct GeneratorWizardSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var model = GeneratorFlowModel()
    @State private var isEnteringKey = false
    @State private var confirmsReplacement = false

    private let start: GeneratorWizardStart
    private let onFinished: (() -> Void)?

    /// Avvio normale: prima domanda.
    /// - Parameter onFinished: chiamata dopo il salvataggio della scheda.
    public init(onFinished: (() -> Void)? = nil) {
        self.start = .question(1)
        self.onFinished = onFinished
    }

    /// Avvio da un punto preciso: lo usano le scene di screenshot.
    public init(start: GeneratorWizardStart, onFinished: (() -> Void)? = nil) {
        self.start = start
        self.onFinished = onFinished
    }

    public var body: some View {
        content
            .task { await prepare() }
            .onDisappear { model.stop() }
            .sheet(isPresented: $isEnteringKey) {
                APIKeySheet(isReplacing: app.ai.status.hasKey) {
                    // Appena salvata la chiave si riparte da sola: l'utente aveva
                    // già chiesto la scheda, non deve chiederla due volte.
                    model.generateWithAI(app: app)
                }
                .environment(app)
            }
            .alert("C'è già una scheda attiva", isPresented: $confirmsReplacement) {
                Button("Annulla", role: .cancel) {}
                Button("Crea e archivia") { save() }
            } message: {
                Text("La scheda attiva finisce in archivio, con tutto il suo storico.")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .questions:
            GeneratorQuestionPage(model: model, onCancel: cancel)

        case .summary:
            GeneratorSummaryPage(model: model, onCancel: cancel) {
                model.start(app: app)
            }

        case .missingKey:
            GeneratorMissingKeyPage(
                onCancel: cancel,
                onEnterKey: { isEnteringKey = true },
                onFallback: { model.generateWithoutAI(app: app) }
            )

        case .generating:
            GeneratorWaitingPage { model.cancelGeneration() }

        case .failed(let failure):
            GeneratorFailurePage(
                failure: failure,
                onCancel: cancel,
                onRetry: { model.generateWithAI(app: app) },
                onFallback: { model.generateWithoutAI(app: app) },
                onOpenSettings: openSettings
            )

        case .preview:
            if let result = model.result {
                GeneratorPreviewPage(
                    model: model,
                    result: result,
                    onCancel: cancel,
                    onRegenerate: { model.regenerate(app: app) },
                    onUse: use
                )
            }
        }
    }

    // MARK: - Avvio

    /// Legge lo stato della chiave (mai nel `body`) e applica l'eventuale punto di
    /// partenza chiesto dagli screenshot.
    private func prepare() async {
        app.ai.refresh()
        switch start {
        case .question(let number):
            guard number > 1 else { return }
            model.step = GeneratorStep(rawValue: number - 1) ?? .goal
        case .summary:
            model.phase = .summary
        case .waiting:
            model.phase = .generating
        case .missingKey:
            model.phase = .missingKey
        case .failure(let failure):
            model.phase = .failed(failure)
        case .preview:
            model.generateWithoutAI(app: app)
        }
    }

    // MARK: - Azioni

    private func cancel() {
        model.stop()
        dismiss()
    }

    /// Le Impostazioni le presenta la shell, non questa sheet: si chiude prima
    /// questa e si apre quella al giro dopo, altrimenti le due presentazioni si
    /// accavallano e la seconda non compare.
    private func openSettings() {
        model.stop()
        dismiss()
        let router = app.router
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            router.presentSettings()
        }
    }

    /// "Usa questa scheda": se ce n'è già una attiva si chiede conferma, con lo
    /// stesso testo del flusso manuale.
    private func use() {
        if app.store.activeProgram != nil {
            confirmsReplacement = true
        } else {
            save()
        }
    }

    private func save() {
        guard let program = model.program(now: app.now) else { return }
        app.store.addProgram(program, makeActive: true)
        Haptics.play(.success)
        model.stop()
        dismiss()
        onFinished?()
    }
}
