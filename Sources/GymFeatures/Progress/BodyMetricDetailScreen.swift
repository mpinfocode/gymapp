import SwiftUI
import Charts
import GymCore
import GymUI

/// Dettaglio di una metrica corporea: range 1M/3M/6M/1A, una sola curva, valore
/// corrente, variazione nel periodo e dall'inizio della scheda, elenco dei valori.
public struct BodyMetricDetailScreen: View {

    @Environment(AppEnvironment.self) private var app

    private let metric: BodyMetricKind

    @State private var range: ChartRange = .month3

    public init(metric: BodyMetricKind) {
        self.metric = metric
    }

    private var tint: AccentPalette { Theme.Metric.viola }

    public var body: some View {
        let series = app.store.bodySeries(of: metric)
        let start = range.start(from: app.now, calendar: app.calendar)
        let points = series.filter { $0.date >= start }

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                Text(metric.displayName)
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                CapsuleSegmentedControl(values: ChartRange.allCases, selection: $range, title: \.title)

                summary(series: series, from: start)
                chart(points)
                list(points.isEmpty ? series : points)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
    }

    // MARK: - Valore corrente e variazioni

    @ViewBuilder
    private func summary(series: [Stats.BodyPoint], from start: Date) -> some View {
        let periodChange = Stats.bodyChange(of: metric, in: app.store.bodyEntries, since: start)
        let programChange = app.store.activeProgram == nil ? nil : app.store.bodyChange(of: metric)

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(series.last.map { BodyFormat.number($0.value, metric: metric, unit: app.unit) } ?? Formatters.missing)
                    .hugeNumberStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(BodyFormat.symbol(metric, unit: app.unit))
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let periodChange {
                Text("\(BodyFormat.delta(periodChange, unit: app.unit)) \(range.periodText)")
                    .captionStyle()
            }
            if let programChange {
                Text("\(BodyFormat.delta(programChange, unit: app.unit)) dall'inizio della scheda")
                    .captionStyle(color: Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Grafico grande

    @ViewBuilder
    private func chart(_ points: [Stats.BodyPoint]) -> some View {
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
            .chartYScale(domain: domain(points))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Formatters.dayAndMonth(date, calendar: app.calendar))
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
                            Text(BodyFormat.number(number, metric: metric, unit: app.unit))
                                .font(.captionText)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityLabel(Text(metric.displayName))
        } else {
            Text("Servono almeno due rilevazioni nel periodo")
                .captionStyle(color: Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        }
    }

    private func domain(_ points: [Stats.BodyPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.3, 0.5)
        return (low - padding)...(high + padding)
    }

    // MARK: - Elenco dei valori

    @ViewBuilder
    private func list(_ points: [Stats.BodyPoint]) -> some View {
        let rows = Array(points.reversed())
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Valori")
                    .overlineStyle()
                    .padding(.bottom, Theme.Spacing.s)

                ForEach(rows) { point in
                    ValueRow(
                        title: Formatters.shortDate(point.date, calendar: app.calendar).firstUppercased,
                        value: BodyFormat.value(point.value, metric: metric, unit: app.unit),
                        showsSeparator: point.id != rows.last?.id
                    )
                }
            }
        }
    }
}
