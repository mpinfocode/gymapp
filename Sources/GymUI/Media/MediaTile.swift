import SwiftUI

/// Tile bianca arrotondata che ospita GIF e immagini degli esercizi.
///
/// Resta bianca anche in dark mode: le sorgenti del dataset hanno fondo bianco
/// e un contenitore scuro le farebbe "ritagliare" (vedi DESIGN.md).
public struct MediaTile<Content: View>: View {

    private let cornerRadius: CGFloat
    private let inset: CGFloat
    private let showsBorder: Bool
    private let content: Content

    /// - Parameters:
    ///   - cornerRadius: raggio della tile (12-20).
    ///   - inset: padding interno attorno al media.
    ///   - showsBorder: bordo hairline `separator`. Serve quando la tile poggia sul
    ///     bianco di pagina; dentro una card grigia si passa `false`.
    public init(
        cornerRadius: CGFloat = Theme.Radius.medium,
        inset: CGFloat = Theme.Spacing.s,
        showsBorder: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.showsBorder = showsBorder
        self.content = content()
    }

    public var body: some View {
        content
            .padding(inset)
            .background(Theme.mediaTile, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // Disegnato solo quando serve: un `strokeBorder` trasparente resta
                // comunque un livello da comporre per ogni tile della lista.
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: Theme.Size.hairline)
                }
            }
    }
}

/// Segnaposto di caricamento di una tile media.
///
/// ## Perché non è sempre animato
/// Il velo che scorre costa, per ogni tile, un `GeometryReader`, un gradiente largo
/// 1,6× il contenitore, un `.clipped()` e un'animazione `repeatForever`: in una lista
/// di esercizi sono decine di animazioni contemporanee mentre si scorre. Le tile
/// piccole (< ``Shimmer/animationThreshold``) usano quindi un riempimento statico
/// sobrio; l'animazione resta alle tile grandi, dove il caricamento si nota davvero.
///
/// Il lato è sempre noto dal chiamante, quindi non serve alcun `GeometryReader`.
/// L'animazione è una sola `repeatForever` su `offset` (la interpola Core Animation)
/// e viene **rimossa** alla scomparsa: un `repeatForever` avviato e mai fermato resta
/// vivo sul layer anche fuori schermo.
public struct Shimmer: View {

    /// Da questo lato in su il segnaposto si anima.
    public static let animationThreshold: CGFloat = 120

    private let side: CGFloat?

    @State private var sweeping = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.blobAnimationPaused) private var pausedByEnvironment
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter side: lato della tile. Se `nil` il segnaposto resta statico
    ///   (senza misura non si può animare uno scorrimento senza `GeometryReader`).
    public init(side: CGFloat? = nil) {
        self.side = side
    }

    private var animates: Bool {
        guard let side, side >= Self.animationThreshold else { return false }
        return !reduceMotion && !pausedByEnvironment && scenePhase != .background
    }

    public var body: some View {
        Group {
            if let side, side >= Self.animationThreshold {
                sweep(side: side)
            } else {
                Theme.separator.opacity(0.5)
            }
        }
        .accessibilityHidden(true)
    }

    private func sweep(side: CGFloat) -> some View {
        LinearGradient(
            colors: [
                Theme.separator.opacity(0.35),
                Theme.separator.opacity(0.75),
                Theme.separator.opacity(0.35),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: side * 1.6, height: side)
        .offset(x: sweeping ? side * 1.2 : -side * 1.2)
        .frame(width: side, height: side, alignment: .leading)
        .clipped()
        .animation(
            sweeping ? .linear(duration: 1.3).repeatForever(autoreverses: false) : nil,
            value: sweeping
        )
        .onAppear { sweeping = animates }
        .onDisappear { sweeping = false }
        .onChange(of: animates) { _, isAnimating in sweeping = isAnimating }
    }
}

/// Stato di errore discreto con retry, condiviso da `RemoteImage` e `AnimatedGIFView`.
struct MediaErrorView: View {

    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(.footnote, weight: .semibold))
                Text("riprova")
                    .font(.system(.caption2, weight: .regular))
            }
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Caricamento non riuscito. Tocca per riprovare."))
    }
}
