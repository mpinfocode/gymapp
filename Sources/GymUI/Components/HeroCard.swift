import SwiftUI

/// Card alta full-bleed con gradiente organico: l'allenamento di oggi, una scheda, il riepilogo.
///
/// Il contenuto è ancorato in basso a sinistra; la chip-etichetta sta in alto a sinistra.
public struct HeroCard<Content: View>: View {

    private let seed: Int
    private let height: CGFloat
    private let chipText: String?
    private let chipSystemImage: String?
    private let animated: Bool
    private let content: Content

    /// - Parameters:
    ///   - seed: seed del gradiente (identità della scheda).
    ///   - height: altezza della card.
    ///   - chipText: testo della chip in alto a sinistra (nil per nasconderla).
    ///   - chipSystemImage: SF Symbol della chip.
    ///   - animated: gradiente animato (disattivarlo in liste lunghe).
    ///   - content: contenuto in basso a sinistra; usare `palette.foreground` come colore testo.
    public init(
        seed: Int,
        height: CGFloat = Theme.Size.heroCardHeight,
        chipText: String? = nil,
        chipSystemImage: String? = nil,
        animated: Bool = true,
        @ViewBuilder content: (BlobPalette) -> Content
    ) {
        self.seed = seed
        self.height = height
        self.chipText = chipText
        self.chipSystemImage = chipSystemImage
        self.animated = animated
        self.content = content(BlobPalette.palette(for: seed))
    }

    public var body: some View {
        let palette = BlobPalette.palette(for: seed)
        ZStack(alignment: .topLeading) {
            BlobGradient(seed: seed, animated: animated)

            // Velo in basso: garantisce il contrasto del testo sul gradiente,
            // chiaro sul tema chiaro e scuro sul tema scuro.
            LinearGradient(
                colors: [.clear, palette.scrim],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if let chipText {
                LabelChip(chipText, systemImage: chipSystemImage, foreground: palette.foreground)
                    .padding(Theme.Spacing.xl)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                content
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    }
}
