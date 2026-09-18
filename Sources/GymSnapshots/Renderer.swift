#if os(macOS)
import AppKit
import SwiftUI

/// Larghezza di riferimento: iPhone 15/16 Pro in punti.
let snapshotWidth: CGFloat = 393

/// Una scena da rendere: nome del file, view, altezza e tema.
struct SnapshotScene {

    /// Nome del PNG (senza estensione) e chiave del filtro da riga di comando.
    let name: String
    let view: AnyView
    /// Altezza di rendering. Una `ScrollView` viene resa per l'altezza data:
    /// per le pagine lunghe serve un valore generoso (1600 e oltre).
    let height: CGFloat
    let dark: Bool
    /// Secondi di run loop concessi ai task asincroni (dati, download media).
    let settle: TimeInterval

    init<V: View>(_ name: String, height: CGFloat = 1600, dark: Bool = false, settle: TimeInterval = 1.5, view: V) {
        self.name = name
        self.view = AnyView(view)
        self.height = height
        self.dark = dark
        self.settle = settle
    }
}

/// Rende una scena in PNG dentro `directory`.
@MainActor
func render(_ scene: SnapshotScene, into directory: String) async {
    let size = CGSize(width: snapshotWidth, height: scene.height)
    let root = scene.view
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scene.dark ? .dark : .light)

    let host = NSHostingView(rootView: root)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: scene.dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    // La finestra deve esistere davvero: senza di essa SwiftUI non considera la
    // view "comparsa" e non esegue `.task` / `.onAppear`, quindi le schermate che
    // caricano dati in modo asincrono uscirebbero vuote.
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    // Primo disegno "a vuoto": è quello che fa comparire davvero la view e quindi
    // fa partire i suoi `.task` / `.onAppear`. Senza, si fotograferebbe lo stato
    // iniziale (schermata di avvio, thumbnail ancora vuote).
    window.displayIfNeeded()
    if let warmUp = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: warmUp)
    }

    // Attesa *asincrona*: cede il main actor a SwiftUI, che può così eseguire i
    // task e completare i caricamenti prima dello scatto vero.
    try? await Task.sleep(for: .milliseconds(Int(scene.settle * 1000)))
    host.layoutSubtreeIfNeeded()

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("ko", scene.name, "(bitmap non disponibile)")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    // La finestra ha fatto il suo lavoro: toglierla evita che le scene successive
    // si accavallino.
    window.orderOut(nil)
    let url = URL(fileURLWithPath: directory).appendingPathComponent(scene.name + ".png")
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("ko", scene.name, "(codifica PNG fallita)")
        return
    }
    do {
        try data.write(to: url)
        print("ok", url.path)
    } catch {
        print("ko", scene.name, "(\(error))")
    }
}
#endif
