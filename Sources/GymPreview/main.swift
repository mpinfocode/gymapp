// L'app in una finestra Mac formato iPhone: interattiva, per provare navigazione,
// layout e flussi prima di ricevere una build sul telefono.
//
// Uso:
//   swift run GymPreview
//   swift run GymPreview --vuoto                  # primo avvio, nessun dato
//   swift run GymPreview --scuro --dispositivo=max
//
// Non è un bundle .app: l'eseguibile si promuove da solo ad app con interfaccia
// (`setActivationPolicy(.regular)`), si costruisce il menu minimo e apre la finestra.
// Chiudere la finestra chiude il processo.
//
// I dati sono finti e vivono in una cartella temporanea nuova a ogni avvio: niente
// di quello che si tocca qui tocca i dati veri dell'app.
#if os(macOS)
import AppKit

// Barre di scorrimento in sovrimpressione come su iOS: quelle "legacy" di macOS
// rubano 18pt a destra quando il contenuto sborda e falsano i margini.
UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")

let options = PreviewOptions.parse(Array(CommandLine.arguments.dropFirst()))
if !options.unknown.isEmpty {
    print("Argomenti ignorati: \(options.unknown.joined(separator: ", "))")
    print(PreviewOptions.usage)
}
print("Anteprima: \(options.device.name) · \(options.scenario.menuTitle) · \(options.dark ? "scuro" : "chiaro")")

let application = NSApplication.shared
let delegate: PreviewApp?

if let path = options.pngPath {
    // Modalità di servizio: nessuna finestra visibile, solo un PNG.
    delegate = nil
    application.setActivationPolicy(.accessory)
    Task { @MainActor in
        await capturePreview(options: options, to: path)
        exit(0)
    }
} else {
    application.setActivationPolicy(.regular)
    let app = PreviewApp(options: options)
    delegate = app
    application.delegate = app
}
_ = delegate
application.run()
#else
print("GymPreview funziona solo su macOS")
#endif
