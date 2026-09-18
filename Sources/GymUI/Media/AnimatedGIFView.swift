import CoreGraphics
import SwiftUI

/// GIF animata resa dentro una tile bianca arrotondata.
///
/// I fotogrammi sono decodificati una volta con ImageIO **alla dimensione di resa**
/// (bitmap piccole, pronte per la composizione) e tenuti in memoria finché la view è
/// sullo schermo; alla scomparsa vengono rilasciati e l'animazione si ferma.
/// Con "Riduci movimento" attivo mostra il primo fotogramma, immobile.
///
/// Se `posterURL` punta a una thumbnail già decodificata in ``DecodedImageCache``
/// (tipicamente quella mostrata nella lista da cui si arriva), la tile si riempie
/// subito con quel fotogramma statico mentre la GIF si scarica e si decodifica.
public struct AnimatedGIFView: View {

    private let url: URL?
    private let side: CGFloat
    private let cornerRadius: CGFloat
    private let inset: CGFloat
    private let showsBorder: Bool
    private let isPlaying: Bool
    private let cache: MediaCache
    private let accessibilityTitle: String?
    private let posterURL: URL?

    @State private var animation: GIFAnimation?
    @State private var failed = false
    @State private var reloadToken = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.blobAnimationPaused) private var pausedByEnvironment
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - url: sorgente della GIF; `nil` mostra lo stato di errore.
    ///   - side: lato della tile quadrata (il dataset è 180×180: non superare ~240).
    ///   - cornerRadius: raggio della tile.
    ///   - inset: padding interno della tile.
    ///   - showsBorder: bordo hairline; `false` quando la tile poggia dentro una card grigia.
    ///   - isPlaying: mette in pausa senza scaricare i fotogrammi (es. cella fuori schermo).
    ///   - cache: cache da usare (iniettabile nei test).
    ///   - accessibilityTitle: se nil la GIF è decorativa.
    ///   - posterURL: thumbnail statica dello stesso esercizio, mostrata subito se è
    ///     già decodificata in memoria. Non viene scaricata: è solo un anticipo.
    public init(
        url: URL?,
        side: CGFloat = 180,
        cornerRadius: CGFloat = Theme.Radius.medium,
        inset: CGFloat = Theme.Spacing.s,
        showsBorder: Bool = true,
        isPlaying: Bool = true,
        cache: MediaCache = .shared,
        accessibilityTitle: String? = nil,
        posterURL: URL? = nil
    ) {
        self.url = url
        self.side = side
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.showsBorder = showsBorder
        self.isPlaying = isPlaying
        self.cache = cache
        self.accessibilityTitle = accessibilityTitle
        self.posterURL = posterURL
    }

    private var contentSide: CGFloat { max(side - inset * 2, 1) }

    /// Lato di decodifica in pixel: 3× il lato in punti copre anche i display @3x.
    private var pixelSide: Int { max(Int(side * 3), 1) }

    public var body: some View {
        // Letto sincronamente: se c'è, la tile non è mai vuota.
        // In mancanza di un poster esplicito vale il primo fotogramma della GIF
        // stessa, memorizzato al caricamento precedente: tornando sulla schermata
        // la tile è piena subito anche mentre i fotogrammi si ridecodificano.
        let poster = animation == nil ? DecodedImageCache.shared.anyImage(for: posterURL ?? url) : nil
        MediaTile(cornerRadius: cornerRadius, inset: inset, showsBorder: showsBorder) {
            ZStack {
                if let animation {
                    frames(animation)
                } else if let poster {
                    Image(decorative: poster, scale: 1)
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
        .task(id: GIFTaskKey(url: url, token: reloadToken)) { await load() }
        // Rilascio dei fotogrammi alla scomparsa e al riciclo della cella.
        .onDisappear { animation = nil }
        .onChange(of: url) { _, _ in
            animation = nil
            failed = false
        }
        .accessibilityHidden(accessibilityTitle == nil)
        .accessibilityLabel(Text(accessibilityTitle ?? ""))
    }

    @ViewBuilder
    private func frames(_ animation: GIFAnimation) -> some View {
        // Ci si ferma davvero quando non serve: fotogramma unico, "Riduci movimento",
        // scena in background, pausa dall'ambiente (tab nascosto: resta montato, quindi
        // `onDisappear` non scatta) o `isPlaying == false` dalla cella fuori schermo.
        let paused = reduceMotion
            || pausedByEnvironment
            || scenePhase == .background
            || !isPlaying
            || animation.frames.count < 2
        // Il passo è la durata del fotogramma più breve: non si ridisegna mai più
        // spesso di quanto la GIF cambi davvero (e mai sotto i 20 ms).
        TimelineView(.animation(minimumInterval: max(animation.shortestFrame, 0.02), paused: paused)) { context in
            let time = paused ? 0 : context.date.timeIntervalSinceReferenceDate
            let index = animation.frameIndex(at: time)
            Image(decorative: animation.frames[index].image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
        }
    }

    private func load() async {
        guard let url else { return }
        let pixels = pixelSide
        if failed { failed = false }
        do {
            let data = try await cache.data(for: url)
            if Task.isCancelled { return }
            let decoded = await Task.detached(priority: .userInitiated) {
                GIFDecoder.decode(
                    data,
                    maxPixelSize: pixels,
                    maxFrames: GIFDecoder.defaultMaximumFrames
                )
            }.value
            if Task.isCancelled { return }
            guard let value = decoded else {
                failed = true
                return
            }
            // Il primo fotogramma diventa il poster di chi tornerà su questa GIF.
            if let first = value.frames.first?.image {
                DecodedImageCache.shared.insert(first, for: url, pixelSide: pixels)
            }
            animation = value
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// Chiave che combina URL e token di retry, così `task(id:)` riparte a ogni "riprova".
private struct GIFTaskKey: Hashable {
    let url: URL?
    let token: Int
}
