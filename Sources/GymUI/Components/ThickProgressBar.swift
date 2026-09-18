import SwiftUI

/// Barra di avanzamento spessa e arrotondata (Riepilogo settimanale).
public struct ThickProgressBar: View {

    private let value: Double
    private let total: Double
    private let height: CGFloat
    private let tint: Color
    private let accessibilityTitle: String?

    /// - Parameters:
    ///   - value: valore corrente.
    ///   - total: valore che riempie la barra (se ≤ 0 la barra resta vuota).
    ///   - height: spessore della barra.
    ///   - tint: colore del riempimento (default `Theme.ink`).
    ///   - accessibilityTitle: etichetta VoiceOver della barra.
    public init(
        value: Double,
        total: Double,
        height: CGFloat = 14,
        tint: Color = Theme.ink,
        accessibilityTitle: String? = nil
    ) {
        self.value = value
        self.total = total
        self.height = height
        self.tint = tint
        self.accessibilityTitle = accessibilityTitle
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Theme.separator)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? height : 0))
            }
            .animation(Theme.Motion.spring, value: fraction)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityTitle ?? "Avanzamento"))
        .accessibilityValue(Text("\(Int(fraction * 100 + 0.5)) per cento"))
    }
}
