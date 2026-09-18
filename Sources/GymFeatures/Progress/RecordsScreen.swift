import SwiftUI
import Charts
import GymCore
import GymUI

/// Record di carico: quanti nel periodo, quando sono arrivati, quali esercizi.
public struct RecordsScreen: View {

    @Environment(AppEnvironment.self) private var app

    @State private var range: ChartRange = .month3

    private var tint: AccentPalette { Theme.Metric.rosa }

    public init() {}

    public var body: some View {
        let events = RecordTimeline.events(in: app.store.sessions)
        let start = range.start(from: app.now, calendar: app.calendar)
        let inRange = events.filter { $0.date >= start }
        // Un record per esercizio: contano gli esercizi migliorati, non le ripetizioni del primato.
        let latest = RecordTimeline.latestPerExercise(inRange)
        let months = monthlyPoints(inRange)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                Text("Record")
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                CapsuleSegmentedControl(values: ChartRange.allCases, selection: $range, title: \.title)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("\(latest.count)")
                        .hugeNumberStyle()
                        .lineLimit(1)
                    Text("esercizi migliorati \(range.periodText)")
                        .captionStyle()
                }
                .accessibilityElement(children: .combine)

                chart(months)
                list(latest)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
    }

    // MARK: - Grafico

    private func monthlyPoints(_ events: [RecordEvent]) -> [TrainingPoint] {
        guard let current = app.calendar.date(from: app.calendar.dateComponents([.year, .month], from: app.now)) else {
            return []
        }
        let from = range.start(from: app.now, calendar: app.calendar)

        var starts: [Date] = []
        var cursor = current
        while cursor >= from, starts.count < 24 {
            starts.append(cursor)
            guard let previous = app.calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        starts.reverse()

        var byMonth: [Date: [RecordEvent]] = [:]
        for event in events {
            guard let start = app.calendar.date(from: app.calendar.dateComponents([.year, .month], from: event.date)) else { continue }
            byMonth[start, default: []].append(event)
        }
        var counts: [Date: Double] = [:]
        for (start, monthEvents) in byMonth {
            counts[start] = Double(RecordTimeline.latestPerExercise(monthEvents).count)
        }
        return starts.map { TrainingPoint(date: $0, value: counts[$0] ?? 0) }
    }

    @ViewBuilder
    private func chart(_ points: [TrainingPoint]) -> some View {
        if points.contains(where: { $0.value > 0 }) {
            Chart(points) { point in
                BarMark(
                    x: .value("Mese", point.date, unit: .month),
                    y: .value("Record", point.value)
                )
                .foregroundStyle(tint.fill)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Formatters.monthAbbreviations[max(0, app.calendar.component(.month, from: date) - 1)])
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
                            Text("\(Int(number.rounded()))")
                                .font(.captionText)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel(Text("Esercizi migliorati per mese"))
        } else {
            Text("Nessun record nel periodo")
                .captionStyle(color: Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        }
    }

    // MARK: - Elenco

    @ViewBuilder
    private func list(_ events: [RecordEvent]) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Esercizi")
                    .overlineStyle()
                    .padding(.bottom, Theme.Spacing.s)

                ForEach(events) { event in
                    NavigationLink(value: AppRoute.exercise(id: event.exerciseID)) {
                        ValueRow(
                            title: app.store.exerciseDisplayName(id: event.exerciseID),
                            subtitle: "\(Formatters.relativeDay(event.date, now: app.now, calendar: app.calendar)) · prima \(Formatters.weight(event.previousKg, unit: app.unit))",
                            value: Formatters.weight(event.weightKg, unit: app.unit),
                            showsSeparator: event.id != events.last?.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
