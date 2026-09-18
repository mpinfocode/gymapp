import CoreGraphics
import SwiftUI

/// Immagine remota (thumbnail statica) resa dentro una tile bianca arrotondata.
///
/// Decodifica con ImageIO, senza UIKit/AppKit; i byte arrivano da `MediaCache`.
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

    public var body: some View {
        MediaTile(cornerRadius: cornerRadius, inset: inset, showsBorder: showsBorder) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else if failed || url == nil {
                    MediaErrorView { reloadToken += 1 }
                } else {
                    Shimmer()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius - inset, style: .continuous))
                }
            }
            .frame(width: side - inset * 2, height: side - inset * 2)
        }
        .frame(width: side, height: side)
        .task(id: TaskKey(url: url, token: reloadToken)) { await load() }
        .onDisappear { image = nil }
        .accessibilityHidden(accessibilityTitle == nil)
        .accessibilityLabel(Text(accessibilityTitle ?? ""))
    }

    private func load() async {
        guard let url else { return }
        failed = false
        do {
            let data = try await cache.data(for: url)
            let pixels = Int(side * 3)
            let decoded = await Task.detached(priority: .userInitiated) {
                DecodedImage(image: GIFDecoder.decodeStill(data, maxPixelSize: pixels))
            }.value
            guard let cgImage = decoded.image else {
                failed = true
                return
            }
            image = cgImage
        } catch {
            failed = true
        }
    }
}

/// Chiave che combina URL e token di retry, così `task(id:)` riparte a ogni "riprova".
private struct TaskKey: Hashable {
    let url: URL?
    let token: Int
}

/// Trasporto sicuro del `CGImage` dal task di decodifica al main actor.
private struct DecodedImage: @unchecked Sendable {
    let image: CGImage?
}
