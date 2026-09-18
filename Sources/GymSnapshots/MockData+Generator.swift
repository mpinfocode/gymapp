#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Scene della "scheda con l'AI": la scelta Manuale/Con l'AI e i vari momenti
/// del wizard.
///
/// Come le altre scene della sezione Scheda, costruisce il proprio ambiente in
/// `task` così `makeScenes` (file condiviso) resta com'è. L'ambiente monta un
/// Portachiavi **in memoria**: nessuno screenshot tocca il Portachiavi vero, e
/// nessuna chiave compare in un PNG.
struct GeneratorVariantScene: View {

    enum Variant {
        /// Scelta fra scheda manuale e scheda con l'AI.
        case choice
        /// Una domanda del wizard, per numero (1...10).
        case question(Int)
        /// Riepilogo delle risposte.
        case summary
        /// Attesa della generazione.
        case waiting
        /// Nessuna chiave salvata.
        case missingKey
        /// Errore di generazione.
        case failure
        /// Anteprima di una bozza costruita senza AI.
        case preview
    }

    let variant: Variant

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                content
                    .environment(environment)
            }
        }
        .task {
            environment = await GeneratorMockData.environment()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .choice:
            ProgramCreationChoiceSheet(onManual: {}, onAssisted: {})
        case .question(let number):
            GeneratorWizardSheet(start: .question(number))
        case .summary:
            GeneratorWizardSheet(start: .summary)
        case .waiting:
            GeneratorWizardSheet(start: .waiting)
        case .missingKey:
            GeneratorWizardSheet(start: .missingKey)
        case .failure:
            GeneratorWizardSheet(start: .failure(.unauthorized))
        case .preview:
            GeneratorWizardSheet(start: .preview)
        }
    }
}

/// Ambiente per le scene del generatore: libreria vera, nessuna scheda, nessuna
/// chiave (così la schermata "serve una chiave" è quella vera e l'anteprima
/// arriva dal generatore senza AI).
@MainActor
enum GeneratorMockData {

    private static var repository: ExerciseRepository?

    static func environment() async -> AppEnvironment {
        let clock = MockClock(MockData.now)
        if repository == nil {
            repository = try? await ExerciseRepository.loadFromBundle()
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GymSnapshots-ai-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(
            store: JSONFileStore(directory: directory),
            exercises: repository,
            saveDelay: .seconds(60),
            now: { clock.date }
        )
        let environment = AppEnvironment(store: store)
        await environment.start()
        clock.date = MockData.now
        return environment
    }
}
#endif
