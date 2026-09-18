import CoreGraphics
import SwiftUI

/// Immagine remota (thumbnail statica) resa dentro una tile bianca arrotondata.
///
/// Decodifica con ImageIO, senza UIKit/AppKit; i byte arrivano da ``MediaCache`` e i
/// `CGImage` già decodificati da ``DecodedImageCache``.
///
/// ## Scroll
/// La cache dei decodificati è letta **sincronamente** dentro `body`, prima di
/// qualunque `await`: una riga che ricompare nasce già piena al primo fotogramma,
/// senza hop sull'actor, senza lettura da disco e senza ridecodifica. Per lo stesso
/// motivo l'immagine **non** viene azzerata alla scomparsa: a tenerla in vita è la
/// cache, non la view, e la view che esce dallo schermo annulla solo il caricamento.
public struct RemoteImage: View {

    private let url: URL?
    private let side: CGFloat
    private let cornerRadius: CGFloat
    private let inset: CGFloat
    private let showsBorder: Bool
    private let cache: MediaCache
    private let accessibilityTitle: String?

    @State private var image: CGImage?
    @State private var failed = false
    @State private var reloadToken = 0

    /// - Parameters:
    ///   - url: sorgente remota; `nil` mostra il segnaposto.
    ///   - side: lato della tile quadrata.
    ///   - cornerRadius: raggio della tile.
    ///   - inset: padding interno della tile.
    ///   - showsBorder: bordo hairline; `false` quando la tile poggia dentro una card grigia.
    ///   - cache: cache da usare (iniettabile nei test).
    ///   - accessibilityTitle: se nil l'immagine è decorativa.
    public init(
        url: URL?,
        side: CGFloat = 64,
        cornerRadius: CGFloat = Theme.Radius.small,
        inset: CGFloat = Theme.Spacing.xs,
        showsBorder: Bool = true,
        cache: MediaCache = .shared,
        accessibilityTitle: String? = nil
    ) {
        self.url = url
        self.side = side
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.showsBorder = showsBorder
        self.cache = cache
        self.accessibilityTitle = accessibilityTitle
    }

    private var contentSide: CGFloat { max(side - inset * 2, 1) }

    /// Lato di decodifica in pixel: 3× il lato in punti copre anche i display @3x.
    private var pixelSide: Int { max(Int(side * 3), 1) }

    public var body: some View {
        // Lettura sincrona: se l'immagine è già decodificata la riga compare piena.
        let shown = image ?? DecodedImageCache.shared.image(for: url, pixelSide: pixelSide)
        MediaTile(cornerRadius: cornerRadius, inset: inset, showsBorder: showsBorder) {
            ZStack {
                if let shown {
                    Image(decorative: shown, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                } else if failed || url == nil {
                    MediaErrorView { reloadToken += 1 }
                } else {
                    Shimmer(side: contentSide)
                        .clipShape(RoundedRectangle(cornerRadius: max(cornerRadius - inset, 0), style: .continuous))
                }
            }
            .frame(width: contentSide, height: contentSide)
        }
        .frame(width: side, height: side)
        .task(id: TaskKey(url: url, token: reloadToken)) { await load() }
        // Riga riciclata su un altro esercizio: la vecchia immagine non deve
        // sopravvivere al cambio di sorgente (se la nuova è in cache, la lettura
        // sincrona qui sopra la sostituisce nello stesso fotogramma).
        .onChange(of: url) { _, _ in
            image = nil
            failed = false
        }
        .accessibilityHidden(accessibilityTitle == nil)
        .accessibilityLabel(Text(accessibilityTitle ?? ""))
    }

    private func load() async {
        guard let url else { return }
        let pixels = pixelSide

        // Già decodificata: niente rete, niente disco, niente decodifica.
        if let cached = DecodedImageCache.shared.image(for: url, pixelSide: pixels) {
            if image == nil { image = cached }
            return
        }

        if failed { failed = false }
        do {
            let data = try await cache.data(for: url)
            if Task.isCancelled { return }
            let decoded = await Task.detached(priority: .userInitiated) {
                DecodedImage(image: GIFDecoder.decodeStill(data, maxPixelSize: pixels))
            }.value
            if Task.isCancelled { return }
            guard let cgImage = decoded.image else {
                failed = true
                return
            }
            DecodedImageCache.shared.insert(cgImage, for: url, pixelSide: pixels)
            image = cgImage
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// Chiave che combina URL e token di retry, così `task(id:)` riparte a ogni "riprova".
private struct TaskKey: Hashable {
    let url: URL?
    let token: Int
}

/// Trasporto sicuro del `CGImage` dal task di decodifica al main actor.
struct DecodedImage: @unchecked Sendable {
    let image: CGImage?
}
