// Strumento di revisione visiva: rende le schermate in PNG su macOS, senza Xcode
// né simulatore.
//
// Uso:
//   swift run GymSnapshots                 # tutte le scene in docs/preview
//   swift run GymSnapshots oggi            # solo le scene il cui nome contiene "oggi"
//   swift run GymSnapshots root sessione   # più filtri, in OR
//   swift run GymSnapshots --out=/tmp/png  # cartella di output diversa
//
// L'output sta in docs/preview, che è in .gitignore: contiene media protetti da
// copyright (© Gym visual) e non deve finire nel repo.
//
// Nota importante sull'architettura di questo eseguibile: il rendering avviene
// dentro un `Task` sul main actor mentre `NSApplication.run()` pompa l'event loop.
// L'attesa fra layout e cattura è un `Task.sleep` (non un `RunLoop.run` bloccante):
// solo così SwiftUI esegue `.task` / `.onAppear` e le schermate che caricano dati
// in modo asincrono vengono fotografate piene invece che vuote.
#if os(macOS)
import AppKit
import Foundation

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

Task { @MainActor in
    var outputDirectory = "docs/preview"
    var filters: [String] = []
    for argument in CommandLine.arguments.dropFirst() {
        if argument.hasPrefix("--out=") {
            outputDirectory = String(argument.dropFirst("--out=".count))
        } else if !argument.hasPrefix("-") {
            filters.append(argument.lowercased())
        }
    }

    try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

    let full = await MockData.fullEnvironment()
    let empty = await MockData.emptyEnvironment()
    let running = await MockData.activeSessionEnvironment()

    print(MockData.summary(of: full, label: "pieno"))
    print(MockData.summary(of: running, label: "sessione in corso"))

    let scenes = makeScenes(full: full, empty: empty, running: running)
    let selected = filters.isEmpty
        ? scenes
        : scenes.filter { scene in filters.contains { scene.name.lowercased().contains($0) } }

    if selected.isEmpty {
        print("Nessuna scena corrisponde a: \(filters.joined(separator: ", "))")
        print("Scene disponibili: \(scenes.map(\.name).joined(separator: ", "))")
    } else {
        for scene in selected {
            await render(scene, into: outputDirectory)
        }
        print("\(selected.count) scene rese in \(outputDirectory)")
    }
    exit(0)
}

application.run()
#else
print("GymSnapshots funziona solo su macOS")
#endif
