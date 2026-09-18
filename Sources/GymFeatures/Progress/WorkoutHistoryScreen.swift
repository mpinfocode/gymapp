import SwiftUI
import GymCore
import GymUI

/// Storico degli allenamenti: sessioni raggruppate per mese, filtro per scheda
/// solo quando le schede sono più di una.
public struct WorkoutHistoryScreen: View {

    @Environment(AppEnvironment.self) private var app

    /// `nil` = tutte le schede.
    @State private var programFilter: UUID?

    public init() {}

    public var body: some View {
        let sessions = filtered(app.store.sessions)
        let months = HistoryGrouping.byMonth(sessions, calendar: app.calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                Text("Storico")
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                filterRow

                if months.isEmpty {
                    EmptyStateView(
                        systemImage: "clock.arrow.circlepath",
                        title: "Nessun allenamento",
                        message: "Qui compaiono gli allenamenti conclusi, con serie, volume e durata."
                    )
                } else {
                    ForEach(months, id: \.start) { month in
                        monthSection(month)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
    }

    private func filtered(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        guard let programFilter else { return sessions }
        return sessions.filter { $0.programID == programFilter }
    }

    // MARK: - Filtro per scheda

    @ViewBuilder
    private var filterRow: some View {
        let programs = app.store.programs
        if programs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    FilterChip("Tutte", isSelected: programFilter == nil) {
                        programFilter = nil
                    }
                    ForEach(programs) { program in
                        FilterChip(program.name, isSelected: programFilter == program.id) {
                            programFilter = program.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Mesi

    @ViewBuilder
    private func monthSection(_ month: HistoryGrouping.Month) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(monthTitle(month.start))
                .overlineStyle()
                .padding(.bottom, Theme.Spacing.xs)

            ForEach(month.sessions) { session in
                NavigationLink(value: AppRoute.session(id: session.id)) {
                    PillRow(
                        title: session.name,
                        subtitle: "\(Formatters.relativeDay(session.startedAt, now: app.now, calendar: app.calendar)) · \(Formatters.minutes(session.duration))",
                        detail: Formatters.volume(session.totalVolumeKg, unit: app.unit)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let month = app.calendar.component(.month, from: date)
        let year = app.calendar.component(.year, from: date)
        let name = Formatters.months.indices.contains(month - 1) ? Formatters.months[month - 1] : ""
        return "\(name) \(year)"
    }
}

/// Raggruppamento dello storico per mese: funzione pura.
enum HistoryGrouping {

    struct Month: Hashable {
        /// Primo giorno del mese.
        let start: Date
        /// Sessioni del mese, dalla più recente.
        let sessions: [WorkoutSession]
    }

    /// Mesi dal più recente, con le sessioni ordinate dalla più recente.
    static func byMonth(_ sessions: [WorkoutSession], calendar: Calendar) -> [Month] {
        var buckets: [Date: [WorkoutSession]] = [:]
        for session in sessions {
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: session.startedAt)) else { continue }
            buckets[start, default: []].append(session)
        }
        return buckets
            .map { Month(start: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.start > $1.start }
    }
}
