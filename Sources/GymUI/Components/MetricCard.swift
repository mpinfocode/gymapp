import SwiftUI

/// Mini-card della dashboard Progressi: titolo, sottotitolo grigio, mini grafico,
/// divisore sottile, valore grande + unità + chevron.
public struct MetricCard<Chart: View>: View {

    private let title: String
    private let subtitle: String
    private let value: String
    private let unit: String?
    private let tint: AccentPalette
    private let chartHeight: CGFloat
    private let chart: Chart
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - title: nome della metrica ("Volume").
    ///   - subtitle: periodo o contesto ("Ultimi 7 giorni").
    ///   - value: valore grande, già formattato.
    ///   - unit: unità piccola accanto al valore ("kg").
    ///   - tint: colore della metrica.
    ///   - chartHeight: altezza dello slot grafico.
    ///   - action: apre il dettaglio; se nil il chevron non compare.
    ///   - chart: mini grafico (`Sparkline`, `MiniBars`, `HabitGrid`…).
    public init(
        title: String,
        subtitle: String,
        value: String,
        unit: String? = nil,
        tint: AccentPalette = Theme.Metric.viola,
        chartHeight: CGFloat = 56,
        action: (() -> Void)? = nil,
        @ViewBuilder chart: () -> Chart
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.unit = unit
        self.tint = tint
        self.chartHeight = chartHeight
        self.action = action
        self.chart = chart()
    }

    public var body: some View {
        if let action {
            Button(action: action) { cardContent }
                .buttonStyle(PressableButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(title), \(subtitle)"))
                .accessibilityValue(Text(unit.map { "\(value) \($0)" } ?? value))
                .accessibilityAddTraits(.isButton)
        } else {
            cardContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(title), \(subtitle)"))
                .accessibilityValue(Text(unit.map { "\(value) \($0)" } ?? value))
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            chart
                .frame(height: chartHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(value)
                    .font(.bigNumber)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(tint.deep)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
