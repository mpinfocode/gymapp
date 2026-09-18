import Foundation
import GymCore

/// Tutto ciò che serve alla griglia di Progressi, calcolato una volta sola.
///
/// È un tipo di sola presentazione: nessuna logica di dominio nuova, solo
/// composizione di ``Stats`` e di ``RecordTimeline``.
struct ProgressDashboard {

    /// La circonferenza che si è mossa di più: è l'unica misura mostrata in griglia.
    struct MeasureHighlight {
        let metric: BodyMetricKind
        let change: Stats.BodyChange
        let series: [Stats.BodyPoint]
    }

    /// Ultime 8 settimane, dalla più vecchia alla corrente (anche quelle vuote).
    let weeks: [Stats.WeekSummary]
    /// Ultimi 30 giorni di attività.
    let activity: [Stats.ActivityDay]
    /// Serie storica del peso corporeo.
    let weightSeries: [Stats.BodyPoint]
    let measureHighlight: MeasureHighlight?
    /// Record di carico dello storico, dal più recente.
    let recordEvents: [RecordEvent]
    /// Esercizi migliorati negli ultimi 30 giorni.
    let recentRecordCount: Int
    /// Esercizi migliorati per mese negli ultimi 6 mesi, dal più vecchio.
    let recordsByMonth: [Double]
    /// Serie per gruppo muscolare della settimana corrente, ordinate.
    let weekMuscleGroups: [MuscleGroupFacet]
    let sessionCount: Int

    var currentWeek: Stats.WeekSummary? { weeks.last }
    var hasSessions: Bool { sessionCount > 0 }
    var hasBodyData: Bool { !weightSeries.isEmpty || measureHighlight != nil }

    /// Numero di allenamenti per settimana, pronto per ``MiniBars``.
    var weeklyWorkouts: [Double] { weeks.map { Double($0.workouts) } }
    /// Volume per settimana, pronto per ``MiniBars``.
    var weeklyVolume: [Double] { weeks.map(\.volumeKg) }
    /// Intensità per giorno, pronta per ``HabitGrid``.
    var activityValues: [Double] { activity.map { $0.isActive ? 1 : 0 } }
    var activeDays: Int { activity.filter(\.isActive).count }

    // MARK: - Costruzione

    @MainActor
    static func make(store: AppStore, now: Date, calendar: Calendar) -> ProgressDashboard {
        let summaries = store.weeklySummaries()
        let weeks = lastWeeks(8, endingAt: now, calendar: calendar, summaries: summaries)
        let reference = store.activeProgram?.startDate ?? .distantPast
        let events = RecordTimeline.events(in: store.sessions)
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        return ProgressDashboard(
            weeks: weeks,
            activity: store.activityGrid(days: 30),
            weightSeries: store.bodySeries(of: .weight),
            measureHighlight: highlight(in: store.bodyEntries, since: reference),
            recordEvents: events,
            recentRecordCount: RecordTimeline.latestPerExercise(events.filter { $0.date >= monthAgo }).count,
            recordsByMonth: recordsByMonth(events, months: 6, endingAt: now, calendar: calendar),
            weekMuscleGroups: (weeks.last?.muscleGroupBreakdown ?? []).filter { $0.count > 0 },
            sessionCount: store.sessions.count
        )
    }

    /// Le ultime `count` settimane, riempendo con settimane vuote quelle senza allenamenti.
    static func lastWeeks(
        _ count: Int,
        endingAt date: Date,
        calendar: Calendar,
        summaries: [Stats.WeekSummary]
    ) -> [Stats.WeekSummary] {
        guard count > 0, let current = Stats.startOfWeek(for: date, calendar: calendar) else { return [] }
        let byStart = Dictionary(summaries.map { ($0.weekStart, $0) }, uniquingKeysWith: { first, _ in first })

        return (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current) else { return nil }
            return byStart[start] ?? Stats.WeekSummary(
                weekStart: start,
                workouts: 0,
                volumeKg: 0,
                minutes: 0,
                completedSets: 0,
                setsByCategory: [:]
            )
        }
    }

    /// Circonferenza con la variazione più marcata dal riferimento: è quella che
    /// racconta qualcosa, le altre restano nella pagina "Misure".
    static func highlight(in entries: [BodyEntry], since date: Date) -> MeasureHighlight? {
        let candidates = BodyMeasure.allCases
            .map(BodyMetricKind.measure)
            .compactMap { metric -> MeasureHighlight? in
                guard let change = Stats.bodyChange(of: metric, in: entries, since: date) else { return nil }
                return MeasureHighlight(
                    metric: metric,
                    change: change,
                    series: Stats.bodySeries(of: metric, in: entries)
                )
            }
        return candidates.max { abs($0.change.delta) < abs($1.change.delta) }
    }

    /// Esercizi migliorati per mese, dal più vecchio al più recente.
    static func recordsByMonth(
        _ events: [RecordEvent],
        months: Int,
        endingAt date: Date,
        calendar: Calendar
    ) -> [Double] {
        guard months > 0 else { return [] }
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date

        return (0..<months).reversed().map { offset in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: current),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return 0 }
            let inMonth = events.filter { $0.date >= start && $0.date < end }
            return Double(RecordTimeline.latestPerExercise(inMonth).count)
        }
    }
}
