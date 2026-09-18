import SwiftUI

/// GIF animata resa dentro una tile bianca arrotondata.
///
/// I fotogrammi sono decodificati una volta con ImageIO e tenuti in memoria finché
/// la view è sullo schermo; alla scomparsa vengono rilasciati e l'animazione si ferma.
/// Con "Riduci movimento" attivo mostra il primo fotogramma, immobile.
public struct AnimatedGIFView: View {

    private let url: URL?
    private let side: CGFloat
    private let cornerRadius: CGFloat
    private let inset: CGFloat
    private let showsBorder: Bool
    private let isPlaying: Bool
    private let cache: MediaCache
    private let accessibilityTitle: String?

    @State private var animation: GIFAnimation?
    @State private var failed = false
    @State private var reloadToken = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - url: sorgente della GIF; `nil` mostra lo stato di errore.
    ///   - side: lato della tile quadrata (il dataset è 180×180: non superare ~240).
    ///   - cornerRadius: raggio della tile.
    ///   - inset: padding interno della tile.
    ///   - showsBorder: bordo hairline; `false` quando la tile poggia dentro una card grigia.
    ///   - isPlaying: mette in pausa senza scaricare i fotogrammi (es. cella fuori schermo).
    ///   - cache: cache da usare (iniettabile nei test).
    ///   - accessibilityTitle: se nil la GIF è decorativa.
    public init(
        url: URL?,
        side: CGFloat = 180,
        cornerRadius: CGFloat = Theme.Radius.medium,
        inset: CGFloat = Theme.Spacing.s,
        showsBorder: Bool = true,
        isPlaying: Bool = true,
        cache: MediaCache = .shared,
        accessibilityTitle: String? = nil
    ) {
        self.url = url
        self.side = side
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.showsBorder = showsBorder
        self.isPlaying = isPlaying
        self.cache = cache
        self.accessibilityTitle = accessibilityTitle
    }

    private var contentSide: CGFloat { max(side - inset * 2, 1) }

    public var body: some View {
        MediaTile(cornerRadius: cornerRadius, inset: inset, showsBorder: showsBorder) {
            ZStack {
                if let animation {
                    frames(animation)
                } else if failed || url == nil {
                    MediaErrorView { reloadToken += 1 }
                } else {
                    Shimmer()
                        .clipShape(RoundedRectangle(cornerRadius: max(cornerRadius - inset, 0), style: .continuous))
                }
            }
            .frame(width: contentSide, height: contentSide)
        }
        .frame(width: side, height: side)
        .task(id: GIFTaskKey(url: url, token: reloadToken)) { await load() }
        .onDisappear { animation = nil }
        .accessibilityHidden(accessibilityTitle == nil)
        .accessibilityLabel(Text(accessibilityTitle ?? ""))
    }

    @ViewBuilder
    private func frames(_ animation: GIFAnimation) -> some View {
        let paused = reduceMotion || !isPlaying || animation.frames.count < 2
        TimelineView(.animation(minimumInterval: max(animation.shortestFrame, 0.02), paused: paused)) { context in
            let time = paused ? 0 : context.date.timeIntervalSinceReferenceDate
            let index = animation.frameIndex(at: time)
            Image(decorative: animation.frames[index].image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }

    private func load() async {
        guard let url else { return }
        failed = false
        do {
            let data = try await cache.data(for: url)
            let decoded = await Task.detached(priority: .userInitiated) {
                GIFDecoder.decode(data)
            }.value
            guard let decoded else {
                failed = true
                return
            }
            animation = decoded
        } catch {
            failed = true
        }
    }
}

/// Chiave che combina URL e token di retry, così `task(id:)` riparte a ogni "riprova".
private struct GIFTaskKey: Hashable {
    let url: URL?
    let token: Int
}
