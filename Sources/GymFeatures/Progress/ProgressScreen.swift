import SwiftUI
import GymCore
import GymUI

/// Tab **Progressi**: griglia di card (allenamenti, volume, costanza, peso e misure
/// corporee, record), dettaglio per card con range 1M/3M/6M/1A e storico sessioni
/// filtrabile (SPEC §5.5).
///
/// Il dettaglio di una sessione si apre con
/// `NavigationLink(value: AppRoute.session(id:))`.
public struct ProgressScreen: View {

    @Environment(AppEnvironment.self) private var app

    /// Destinazione locale alla feature: non serve una rotta condivisa.
    @State private var destination: ProgressDestination?
    @State private var isAddingEntry = false

    public init() {}

    public var body: some View {
        let dashboard = ProgressDashboard.make(store: app.store, now: app.now, calendar: app.calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                header

                // Senza alcun dato la griglia sarebbe una parete di card vuote:
                // meglio una sola frase e un'azione (DESIGN, "in caso di dubbio togli").
                if dashboard.hasSessions || dashboard.hasBodyData {
                    grid(dashboard)
                    muscleGroups(dashboard)
                    footer(dashboard)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .pageBackground()
        .navigationDestination(item: $destination) { destination in
            ProgressDestinationView(destination: destination)
        }
        .sheet(isPresented: $isAddingEntry) {
            BodyEntrySheet(entry: nil, defaultDate: app.now)
        }
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Formatters.longDateUppercased(app.now, calendar: app.calendar))
                .overlineStyle()

            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                Text("Progressi")
                    .pageTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: Theme.Spacing.s)

                CircleIconButton(systemImage: "plus", accessibilityTitle: "Nuova rilevazione") {
                    isAddingEntry = true
                }
            }
        }
    }

    // MARK: - Griglia

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: Theme.Spacing.m),
            GridItem(.flexible(), spacing: Theme.Spacing.m),
        ]
    }

    @ViewBuilder
    private func grid(_ dashboard: ProgressDashboard) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            workoutsCard(dashboard)
            volumeCard(dashboard)
            consistencyCard(dashboard)
            recordsCard(dashboard)
            weightCard(dashboard)
            measuresCard(dashboard)
        }
    }

    private func workoutsCard(_ dashboard: ProgressDashboard) -> some View {
        let workouts = dashboard.currentWeek?.workouts ?? 0
        let hasData = dashboard.hasSessions
        return MetricCard(
            title: "Allenamenti",
            subtitle: "Questa settimana",
            value: hasData ? "\(workouts)" : Formatters.missing,
            tint: Theme.Metric.blu,
            action: hasData ? { destination = .training(.workouts) } : nil
        ) {
            BarsSlot(
                values: dashboard.weeklyWorkouts,
                tint: Theme.Metric.blu,
                accessibilityTitle: "Allenamenti per settimana"
            )
        }
    }

    private func volumeCard(_ dashboard: ProgressDashboard) -> some View {
        let volume = dashboard.currentWeek?.volumeKg ?? 0
        let hasData = dashboard.hasSessions
        return MetricCard(
            title: "Volume",
            subtitle: "Questa settimana",
            value: hasData ? Formatters.volume(volume, unit: app.unit, includeSymbol: false) : Formatters.missing,
            unit: hasData ? app.unit.symbol : nil,
            tint: Theme.Metric.arancio,
            action: hasData ? { destination = .training(.volume) } : nil
        ) {
            BarsSlot(
                values: dashboard.weeklyVolume,
                tint: Theme.Metric.arancio,
                accessibilityTitle: "Volume per settimana"
            )
        }
    }

    private func consistencyCard(_ dashboard: ProgressDashboard) -> some View {
        let hasData = dashboard.activeDays > 0
        return MetricCard(
            title: "Costanza",
            subtitle: "Ultimi 30 giorni",
            value: hasData ? "\(dashboard.activeDays)" : Formatters.missing,
            unit: hasData ? "giorni" : nil,
            tint: Theme.Metric.verde,
            action: hasData ? { destination = .training(.consistency) } : nil
        ) {
            if hasData {
                // 10 colonne da 9pt + 4 di gap = 126pt: sta dentro la colonna della
                // griglia (circa 138pt di contenuto) senza allargare la card.
                HabitGrid(
                    values: dashboard.activityValues,
                    columns: 10,
                    tint: Theme.Metric.verde,
                    squareSide: 9,
                    accessibilityTitle: "Costanza degli ultimi 30 giorni"
                )
            } else {
                EmptyChartSlot()
            }
        }
    }

    private func recordsCard(_ dashboard: ProgressDashboard) -> some View {
        let hasData = !dashboard.recordEvents.isEmpty
        return MetricCard(
            title: "Record",
            subtitle: "Ultimi 30 giorni",
            value: hasData ? "\(dashboard.recentRecordCount)" : Formatters.missing,
            tint: Theme.Metric.rosa,
            action: hasData ? { destination = .records } : nil
        ) {
            BarsSlot(
                values: dashboard.recordsByMonth,
                tint: Theme.Metric.rosa,
                accessibilityTitle: "Record per mese"
            )
        }
    }

    private func weightCard(_ dashboard: ProgressDashboard) -> some View {
        let latest = dashboard.weightSeries.last
        return MetricCard(
            title: "Peso corporeo",
            subtitle: latest.map { Formatters.relativeDay($0.date, now: app.now, calendar: app.calendar) } ?? "Mai registrato",
            value: latest.map { BodyFormat.number($0.value, metric: .weight, unit: app.unit) } ?? Formatters.missing,
            unit: latest == nil ? nil : app.unit.symbol,
            tint: Theme.Metric.viola,
            action: latest == nil ? nil : { destination = .body(.weight) }
        ) {
            SparklineSlot(
                values: dashboard.weightSeries.map(\.value),
                tint: Theme.Metric.viola,
                accessibilityTitle: "Andamento del peso"
            )
        }
    }

    private func measuresCard(_ dashboard: ProgressDashboard) -> some View {
        let highlight = dashboard.measureHighlight
        let subtitle = highlight.map { "\($0.metric.shortName) · \(BodyFormat.delta($0.change, unit: app.unit))" }
        return MetricCard(
            title: "Misure",
            subtitle: subtitle ?? "Mai registrate",
            value: highlight.map { BodyFormat.number($0.change.latest.value, metric: $0.metric, unit: app.unit) } ?? Formatters.missing,
            unit: highlight.map { BodyFormat.symbol($0.metric, unit: app.unit) },
            tint: Theme.Metric.viola,
            action: dashboard.hasBodyData ? { destination = .measures } : nil
        ) {
            SparklineSlot(
                values: highlight?.series.map(\.value) ?? [],
                tint: Theme.Metric.viola,
                accessibilityTitle: "Andamento delle misure"
            )
        }
    }

    // MARK: - Serie per gruppo muscolare

    @ViewBuilder
    private func muscleGroups(_ dashboard: ProgressDashboard) -> some View {
        if !dashboard.weekMuscleGroups.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Serie per gruppo muscolare")
                    .sectionTitleStyle()
                Card {
                    MuscleGroupBars(facets: dashboard.weekMuscleGroups)
                }
            }
        }
    }

    // MARK: - Storico e stato vuoto

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "chart.line.uptrend.xyaxis",
            title: "Ancora nessun dato",
            message: "I progressi compaiono dopo il primo allenamento. Nel frattempo puoi registrare peso e misure.",
            actionTitle: "Nuova rilevazione",
            action: { isAddingEntry = true }
        )
        .padding(.top, Theme.Spacing.xxl)
    }

    @ViewBuilder
    private func footer(_ dashboard: ProgressDashboard) -> some View {
        if dashboard.hasSessions {
            Button {
                destination = .history
            } label: {
                PillRow(
                    title: "Storico allenamenti",
                    detail: "\(dashboard.sessionCount)",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Storico allenamenti"))
            .accessibilityValue(Text("\(dashboard.sessionCount) sessioni"))
        }
    }
}
