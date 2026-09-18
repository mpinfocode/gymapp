import SwiftUI
import Charts
import GymCore
import GymUI

/// Metriche di allenamento che hanno un dettaglio con grafico grande.
public enum TrainingMetric: String, Hashable, CaseIterable, Sendable {
    /// Allenamenti per settimana.
    case workouts
    /// Volume per settimana.
    case volume
    /// Giorni allenati per mese: granularità diversa da ``workouts``, non un doppione.
    case consistency

    public var title: String {
        switch self {
        case .workouts: "Allenamenti"
        case .volume: "Volume"
        case .consistency: "Costanza"
        }
    }

    /// Etichetta del valore corrente.
    var currentLabel: String {
        switch self {
        case .workouts, .volume: "questa settimana"
        case .consistency: "questo mese"
        }
    }

    var tint: AccentPalette {
        switch self {
        case .workouts: Theme.Metric.blu
        case .volume: Theme.Metric.arancio
        case .consistency: Theme.Metric.verde
        }
    }

    /// Passo temporale dei punti.
    var isMonthly: Bool { self == .consistency }

    /// Simbolo piccolo accanto al valore grande.
    func symbol(unit: WeightUnit) -> String? {
        switch self {
        case .workouts: nil
        case .volume: unit.symbol
        case .consistency: "giorni"
        }
    }

    /// Valore formattato, senza simbolo.
    func text(_ value: Double, unit: WeightUnit) -> String {
        switch self {
        case .workouts, .consistency: "\(Int(value.rounded()))"
        case .volume: Formatters.volume(value, unit: unit, includeSymbol: false)
        }
    }

    /// Variazione con segno ("+2", "+1.240 kg").
    func deltaText(_ value: Double, unit: WeightUnit) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let symbol = self == .volume ? " \(unit.symbol)" : ""
        return sign + text(abs(value), unit: unit) + symbol
    }
}

/// Un punto del grafico grande: inizio della settimana o del mese.
struct TrainingPoint: Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Dettaglio di una metrica di allenamento: range 1M/3M/6M/1A, un solo grafico
/// pulito, valore corrente, variazione ed elenco dei valori.
public struct TrainingMetricDetailScreen: View {

    @Environment(AppEnvironment.self) private var app

    private let metric: TrainingMetric

    @State private var range: ChartRange = .month3

    public init(metric: TrainingMetric) {
        self.metric = metric
    }

    public var body: some View {
        let points = TrainingSeries.points(
            of: metric,
            sessions: app.store.sessions,
            range: range,
            now: app.now,
            calendar: app.calendar
        )

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                Text(metric.title)
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                CapsuleSegmentedControl(values: ChartRange.allCases, selection: $range, title: \.title)

                summary(points)
                chart(points)
                list(points)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
    }

    // MARK: - Valore corrente

    @ViewBuilder
    private func summary(_ points: [TrainingPoint]) -> some View {
        let current = points.last?.value ?? 0
        // Riferimento: il primo periodo con dati. Confrontarsi con le settimane
        // vuote che precedono il primo allenamento darebbe variazioni finte.
        let baseline = points.first { $0.value > 0 }

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(metric.text(current, unit: app.unit))
                    .hugeNumberStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let symbol = metric.symbol(unit: app.unit) {
                    Text(symbol)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let baseline, baseline.id != points.last?.id {
                Text("\(metric.currentLabel), \(metric.deltaText(current - baseline.value, unit: app.unit)) \(range.periodText)")
                    .captionStyle()
            } else {
                Text(metric.currentLabel)
                    .captionStyle()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Grafico grande

    @ViewBuilder
    private func chart(_ points: [TrainingPoint]) -> some View {
        if points.contains(where: { $0.value > 0 }) {
            Chart(points) { point in
                BarMark(
                    x: .value("Periodo", point.date, unit: metric.isMonthly ? .month : .weekOfYear),
                    y: .value(metric.title, point.value)
                )
                .foregroundStyle(metric.tint.fill)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date))
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
                            Text(metric.text(number, unit: app.unit))
                                .font(.captionText)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityLabel(Text(metric.title))
        } else {
            Text("Nessun dato nel periodo")
                .captionStyle(color: Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
        }
    }

    private func axisLabel(for date: Date) -> String {
        metric.isMonthly
            ? Formatters.monthAbbreviations[max(0, (app.calendar.component(.month, from: date)) - 1)]
            : Formatters.dayAndMonth(date, calendar: app.calendar)
    }

    // MARK: - Elenco dei valori

    @ViewBuilder
    private func list(_ points: [TrainingPoint]) -> some View {
        let rows = points.filter { $0.value > 0 }.reversed()
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Valori")
                    .overlineStyle()
                    .padding(.bottom, Theme.Spacing.s)

                ForEach(Array(rows)) { point in
                    ValueRow(
                        title: rowTitle(for: point.date),
                        value: [metric.text(point.value, unit: app.unit), metric.symbol(unit: app.unit)]
                            .compactMap { $0 }
                            .joined(separator: " "),
                        showsSeparator: point.id != rows.last?.id
                    )
                }
            }
        }
    }

    private func rowTitle(for date: Date) -> String {
        if metric.isMonthly {
            let month = app.calendar.component(.month, from: date)
            let year = app.calendar.component(.year, from: date)
            let name = Formatters.months.indices.contains(month - 1) ? Formatters.months[month - 1] : ""
            return "\(name.firstUppercased) \(year)"
        }
        return "Settimana del \(Formatters.dayAndMonth(date, calendar: app.calendar))"
    }
}

/// Costruzione delle serie temporali di allenamento: funzioni pure.
enum TrainingSeries {

    /// Un punto per settimana (o per mese) dentro il range, anche dove vale zero.
    static func points(
        of metric: TrainingMetric,
        sessions: [WorkoutSession],
        range: ChartRange,
        now: Date,
        calendar: Calendar
    ) -> [TrainingPoint] {
        let component: Calendar.Component = metric.isMonthly ? .month : .weekOfYear
        guard let last = bucketStart(for: now, component: component, calendar: calendar) else { return [] }
        let from = range.start(from: now, calendar: calendar)

        var starts: [Date] = []
        var cursor = last
        while cursor >= from, starts.count < 80 {
            starts.append(cursor)
            guard let previous = calendar.date(byAdding: component, value: -1, to: cursor) else { break }
            cursor = previous
        }
        starts.reverse()

        var buckets: [Date: Double] = [:]
        var activeDays: [Date: Set<Date>] = [:]
        for session in sessions {
            guard let start = bucketStart(for: session.startedAt, component: component, calendar: calendar) else { continue }
            switch metric {
            case .workouts:
                buckets[start, default: 0] += 1
            case .volume:
                buckets[start, default: 0] += session.totalVolumeKg
            case .consistency:
                activeDays[start, default: []].insert(calendar.startOfDay(for: session.startedAt))
            }
        }
        if metric == .consistency {
            for (start, days) in activeDays { buckets[start] = Double(days.count) }
        }

        return starts.map { TrainingPoint(date: $0, value: buckets[$0] ?? 0) }
    }

    private static func bucketStart(for date: Date, component: Calendar.Component, calendar: Calendar) -> Date? {
        if component == .month {
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        }
        return Stats.startOfWeek(for: date, calendar: calendar)
    }
}
