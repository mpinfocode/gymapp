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
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(showsBorder ? Theme.separator : .clear, lineWidth: Theme.Size.hairline)
            )
    }
}

/// Velo animato di caricamento. Rispetta "Riduci movimento" restando statico.
public struct Shimmer: View {

    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                colors: [
                    Theme.separator.opacity(0.35),
                    Theme.separator.opacity(0.75),
                    Theme.separator.opacity(0.35),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 1.6)
            .offset(x: reduceMotion ? 0 : phase * width * 1.2)
            .frame(width: width, alignment: .leading)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityHidden(true)
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
