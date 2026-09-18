import SwiftUI
import Charts
import GymCore
import GymUI

// Mattoni piccoli usati solo dentro Misure: il grafico di una metrica corporea e
// le righe/controlli che si ripetono fra la radice, il dettaglio e il foglio di
// inserimento.

/// Curva di una metrica corporea: una sola linea con i punti, assi discreti.
///
/// La usano sia la testata "peso" della tab Misure sia il dettaglio di una metrica,
/// così i due grafici sono identici e non c'è una seconda configurazione da tenere
/// allineata.
struct BodyMetricChart: View {

    let points: [Stats.BodyPoint]
    let metric: BodyMetricKind
    let unit: WeightUnit
    let calendar: Calendar
    var height: CGFloat = 220

    private var tint: AccentPalette { Theme.Metric.viola }

    var body: some View {
        if points.count > 1 {
            Chart(points) { point in
                LineMark(
                    x: .value("Data", point.date),
                    y: .value(metric.displayName, point.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(tint.deep)

                PointMark(
                    x: .value("Data", point.date),
                    y: .value(metric.displayName, point.value)
                )
                .symbolSize(28)
                .foregroundStyle(tint.deep)
            }
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Formatters.dayAndMonth(date, calendar: calendar))
                                .font(.captionText)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(BodyFormat.number(number, metric: metric, unit: unit))
                                .font(.captionText)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .frame(height: height)
            .accessibilityLabel(Text(metric.displayName))
        } else {
            Text("Servono almeno due rilevazioni nel periodo")
                .captionStyle(color: Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .center)
        }
    }

    /// Scala verticale con un po' d'aria sopra e sotto: una variazione di mezzo kg
    /// non deve diventare una montagna.
    private var domain: ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.3, 0.5)
        return (low - padding)...(high + padding)
    }
}

/// Riga di un elenco di valori: titolo (+ sottotitolo) a sinistra, valore a destra.
/// Separatore hairline sotto, tranne l'ultima.
struct ValueRow<Trailing: View>: View {

    let title: String
    var subtitle: String?
    var showsSeparator: Bool = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                trailing
            }
            .frame(minHeight: Theme.Size.minTapTarget)

            if showsSeparator {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.Size.hairline)
            }
        }
    }
}

extension ValueRow where Trailing == Text {

    /// Variante con un valore testuale a destra.
    init(title: String, subtitle: String? = nil, value: String, showsSeparator: Bool = true) {
        self.init(title: title, subtitle: subtitle, showsSeparator: showsSeparator) {
            Text(value)
                .font(.system(.body, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Sezione richiudibile del foglio "Nuova rilevazione".
struct CollapsibleSection<Content: View>: View {

    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button {
                withAnimation(Theme.Motion.smooth) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .overlineStyle()
                    Spacer(minLength: Theme.Spacing.s)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(isExpanded ? "aperta" : "chiusa"))
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                content
            }
        }
    }
}

/// Bottone circolare discreto da 44pt su `surface`: il "+" e l'ingranaggio della testata.
/// Non ruba la scena al titolo come farebbe una capsula `ink`.
struct CircleIconButton: View {

    let systemImage: String
    let accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

/// Menu "…" di una riga: stesso aspetto ovunque.
struct EllipsisMenu<Content: View>: View {

    var accessibilityTitle: String = "Altre azioni"
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(accessibilityTitle))
    }
}
