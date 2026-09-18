import SwiftUI

/// Griglia di quadratini per la costanza degli ultimi N giorni (stile MacroFactor).
public struct HabitGrid: View {

    private let values: [Double]
    private let columns: Int
    private let tint: AccentPalette
    private let squareSide: CGFloat
    private let accessibilityTitle: String

    /// - Parameters:
    ///   - values: intensità per giorno, 0 = niente, 1 = pieno; il primo elemento è il giorno più vecchio.
    ///   - columns: quadratini per riga.
    ///   - tint: colore del riempimento.
    ///   - squareSide: lato del quadratino.
    ///   - accessibilityTitle: etichetta VoiceOver della griglia nel suo insieme.
    public init(
        values: [Double],
        columns: Int = 10,
        tint: AccentPalette = Theme.Metric.verde,
        squareSide: CGFloat = 12,
        accessibilityTitle: String = "Griglia di costanza"
    ) {
        self.values = values
        self.columns = max(columns, 1)
        self.tint = tint
        self.squareSide = squareSide
        self.accessibilityTitle = accessibilityTitle
    }

    private var activeDays: Int { values.filter { $0 > 0 }.count }

    public var body: some View {
        let layout = Array(
            repeating: GridItem(.fixed(squareSide), spacing: Theme.Spacing.xs),
            count: columns
        )
        LazyVGrid(columns: layout, spacing: Theme.Spacing.xs) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: squareSide * 0.28, style: .continuous)
                    .fill(value > 0 ? tint.fill.opacity(0.45 + 0.55 * min(value, 1)) : Theme.separator)
                    .frame(width: squareSide, height: squareSide)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(Text("\(activeDays) giorni attivi su \(values.count)"))
    }
}
