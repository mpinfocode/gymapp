#if os(macOS)
import AppKit
import SwiftUI

/// Rende la finestra simulata in un PNG e basta, senza aprire niente a schermo.
///
/// Serve a verificare la resa della cornice (safe area, angoli, barra di stato)
/// anche dove i permessi di registrazione dello schermo non permettono di
/// fotografare una finestra vera con `screencapture`.
///
///     swift run GymPreview --png=/tmp/anteprima.png --scuro
@MainActor
func capturePreview(options: PreviewOptions, to path: String) async {
    let environment = await PreviewMockData.environment(for: options.scenario)
    let size = DeviceFrameView.windowSize(for: options.device)
    let root = DeviceFrameView(device: options.device, environment: environment, dark: options.dark)

    let host = NSHostingView(rootView: root)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: options.dark ? .darkAqua : .aqua)

    // La finestra deve esistere davvero, altrimenti SwiftUI non considera la view
    // "comparsa" e non esegue `.task` / `.onAppear`; trasparente e fuori schermo
    // per non disturbare chi sta usando il Mac.
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = host.appearance
    window.contentView = host
    window.alphaValue = 0
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    if let warmUp = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: warmUp)
    }

    try? await Task.sleep(for: .milliseconds(2500))
    host.layoutSubtreeIfNeeded()

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("ko: bitmap non disponibile")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    window.orderOut(nil)

    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("ko: codifica PNG fallita")
        return
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("ok \(path)")
    } catch {
        print("ko: \(error)")
    }
}
#endif
