import SwiftUI

/// Superficie standard dell'app: raggio 28, riempimento grigio chiarissimo.
/// Niente ombra e niente bordo: sul bianco puro basta il riempimento a staccare.
public struct Card<Content: View>: View {

    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let background: AnyShapeStyle
    private let content: Content

    /// - Parameters:
    ///   - padding: padding interno uniforme.
    ///   - cornerRadius: raggio degli angoli (default `Theme.Radius.card`).
    ///   - background: stile di riempimento (default `Theme.surface`).
    public init(
        padding: CGFloat = Theme.Spacing.xl,
        cornerRadius: CGFloat = Theme.Radius.card,
        background: AnyShapeStyle = AnyShapeStyle(Theme.surface),
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.background = background
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {

    /// Incapsula la view in una superficie card senza usare il contenitore `Card`.
    public func cardSurface(
        cornerRadius: CGFloat = Theme.Radius.card,
        inset: CGFloat = Theme.Spacing.xl
    ) -> some View {
        self.padding(inset)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
