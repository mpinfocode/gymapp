import SwiftUI
import Charts
import GymCore
import GymUI

/// "I tuoi progressi": compare **solo** se l'esercizio è stato eseguito almeno una
/// volta. Record, andamento del massimale stimato e ultime tre sessioni.
///
/// Tutto arriva da `Stats` attraverso lo store: qui non si calcola niente.
struct ExerciseProgressSection: View {

    @Environment(AppEnvironment.self) private var app

    let exerciseID: String

    private var tint: AccentPalette { Theme.Metric.rosa }

    var body: some View {
        let records = app.store.records(for: exerciseID)
        let series = app.store.series(for: exerciseID)

        if let records, !series.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("I tuoi progressi")
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                Card {
                    HStack(alignment: .top, spacing: Theme.Spacing.l) {
                        record(
                            label: "Peso max",
                            value: Formatters.weight(records.maxWeightKg, unit: app.unit),
                            date: records.maxWeightDate
                        )
                        record(
                            label: "1RM stimato",
                            value: Formatters.weight(records.best1RMKg, unit: app.unit),
                            date: records.best1RMDate
                        )
                    }
                }

                if series.count > 1 {
                    chart(series)
                }

                lastSessions(series)
            }
        }
    }

    // MARK: - Record

    private func record(label: String, value: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .overlineStyle()
            Text(value)
                .bigNumberStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(Formatters.relativeDay(date, now: app.now, calendar: app.calendar))
                .captionStyle(color: Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Andamento

    private func chart(_ series: [Stats.ExerciseDataPoint]) -> some View {
        let values = series.map(\.best1RMKg)
        let lowest = values.min() ?? 0
        let highest = values.max() ?? 1
        // Dominio stretto attorno ai dati: con lo zero il progresso di qualche
        // chilo diventerebbe una riga piatta.
        let margin = max((highest - lowest) * 0.4, max(highest * 0.06, 1))
        let domain = max(lowest - margin, 0)...(highest + margin)

        return Chart(series) { point in
            LineMark(
                x: .value("Data", point.date),
                y: .value("Massimale stimato", point.best1RMKg)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            .foregroundStyle(tint.deep)

            PointMark(
                x: .value("Data", point.date),
                y: .value("Massimale stimato", point.best1RMKg)
            )
            .symbolSize(28)
            .foregroundStyle(tint.deep)
        }
        .chartYScale(domain: domain)
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
                        Text(Formatters.weight(number, unit: app.unit, includeSymbol: false))
                            .font(.captionText)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityLabel(Text("Andamento del massimale stimato"))
    }

    // MARK: - Ultime sessioni

    private func lastSessions(_ series: [Stats.ExerciseDataPoint]) -> some View {
        let last = Array(series.suffix(3).reversed())
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Ultime sessioni")
                .overlineStyle()

            VStack(spacing: 0) {
                ForEach(last) { point in
                    VStack(spacing: 0) {
                        HStack(spacing: Theme.Spacing.m) {
                            Text(Formatters.relativeDay(point.date, now: app.now, calendar: app.calendar))
                                .font(.bodyText)
                                .foregroundStyle(Theme.textPrimary)

                            Spacer(minLength: Theme.Spacing.s)

                            Text(Formatters.weight(point.maxWeightKg, unit: app.unit))
                                .font(.system(.subheadline, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(minHeight: Theme.Size.minTapTarget)
                        .accessibilityElement(children: .combine)

                        if point.id != last.last?.id {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: Theme.Size.hairline)
                        }
                    }
                }
            }
        }
    }
}
