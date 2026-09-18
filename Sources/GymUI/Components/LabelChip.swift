import SwiftUI

/// Capsula traslucida con icona + testo minuscolo, in alto a sinistra delle card (stile pillowtalk).
public struct LabelChip: View {

    private let text: String
    private let systemImage: String?
    private let foreground: Color

    /// - Parameters:
    ///   - text: testo dell'etichetta (reso in minuscolo).
    ///   - systemImage: nome SF Symbol opzionale.
    ///   - foreground: colore di testo e icona.
    public init(_ text: String, systemImage: String? = nil, foreground: Color = Theme.textPrimary) {
        self.text = text
        self.systemImage = systemImage
        self.foreground = foreground
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.footnote, weight: .medium))
            }
            Text(text)
                .font(.system(.footnote, weight: .medium))
                .textCase(.lowercase)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s - 1)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}
