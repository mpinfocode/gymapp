import SwiftUI
import GymCore
import GymUI

/// Dettaglio di una metrica corporea: range 1M/3M/6M/1A, una sola curva, valore
/// corrente, variazione nel periodo e dall'inizio della scheda, elenco dei valori.
public struct BodyMetricDetailScreen: View {

    @Environment(AppEnvironment.self) private var app

    private let metric: BodyMetricKind

    @State private var range: ChartRange = .month3
    /// Serie, dominio e valori del grafico: calcolati in un `.task(id:)`, mai nel `body`.
    @State private var chart = BodyChartData()
    @State private var rows: [Stats.BodyPoint] = []
    @State private var periodChange: String?
    @State private var programChange: String?

    public init(metric: BodyMetricKind) {
        self.metric = metric
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                Text(metric.displayName)
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                CapsuleSegmentedControl(values: ChartRange.allCases, selection: $range, title: \.title)

                summary

                BodyMetricChart(
                    points: chart.points,
                    domain: chart.domain,
                    metric: metric,
                    unit: app.unit,
                    calendar: app.calendar
                )

                list
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
        .task(id: signature) { reload() }
    }

    // MARK: - Ricalcolo fuori dal body

    private var signature: String {
        "\(range.rawValue)|\(app.store.bodyEntries.count)|\(app.unit.rawValue)|\(app.store.activeProgramID?.uuidString ?? "")"
    }

    private func reload() {
        let series = app.store.bodySeries(of: metric)
        let start = range.start(from: app.now, calendar: app.calendar)
        chart = BodyChartData.make(series: series, from: start)
        rows = Array((chart.points.isEmpty ? series : chart.points).reversed())
        periodChange = Stats.bodyChange(of: metric, in: app.store.bodyEntries, since: start)
            .map { "\(BodyFormat.delta($0, unit: app.unit)) \(range.periodText)" }
        programChange = app.store.activeProgram == nil
            ? nil
            : app.store.bodyChange(of: metric).map { "\(BodyFormat.delta($0, unit: app.unit)) dall'inizio della scheda" }
    }

    // MARK: - Valore corrente e variazioni

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(chart.latest.map { BodyFormat.number($0.value, metric: metric, unit: app.unit) } ?? Formatters.missing)
                    .hugeNumberStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(BodyFormat.symbol(metric, unit: app.unit))
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let periodChange {
                Text(periodChange).captionStyle()
            }
            if let programChange {
                Text(programChange)
                    .captionStyle(color: Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Elenco dei valori

    @ViewBuilder
    private var list: some View {
        if !rows.isEmpty {
            LazyVStack(alignment: .leading, spacing: 0) {
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
