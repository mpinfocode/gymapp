import SwiftUI
import GymCore
import GymUI

/// Tab **Misure**: il peso corporeo in evidenza con il suo grafico, le altre
/// metriche registrate almeno una volta e l'elenco delle rilevazioni.
///
/// È la radice del quarto tab. Dalla testata si apre il foglio
/// "Nuova rilevazione" ("+"); le Impostazioni stanno nell'ingranaggio della Home.
public struct MeasuresScreen: View {

    @Environment(AppEnvironment.self) private var app

    @State private var isAddingEntry = false
    @State private var editedEntry: BodyEntry?
    @State private var entryToDelete: BodyEntry?
    @State private var range: ChartRange = .month3
    /// Serie, dominio e ultimo valore del grafico del peso: si ricalcolano in un
    /// `.task(id:)`, mai dentro il `body`.
    @State private var weightChart = BodyChartData()
    @State private var weightCaption: String?

    /// Ancora in cima alla pagina, per il "scorri in cima" del ritocco del tab.
    private static let topID = "misure-top"

    public init() {}

    public var body: some View {
        let entries = app.store.bodyEntries
        let metrics = Stats.recordedBodyMetrics(in: entries)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .id(Self.topID)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                        if metrics.isEmpty {
                            emptyState
                        } else {
                            weightSection
                            otherMetrics(metrics)
                            entryList(entries)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                }
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
            // Ritocco dell'icona "Misure" quando si è già alla radice: si torna in
            // cima (il token lo incrementa `Router.reselect(_:)`).
            .onChange(of: app.router.scrollToTopToken(for: .measures)) { _, _ in
                withAnimation(Theme.Motion.smooth) {
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            }
        }
        .pageBackground()
        .task(id: chartSignature) { reloadWeightChart() }
        .sheet(isPresented: $isAddingEntry) {
            BodyEntrySheet(entry: nil, defaultDate: app.now)
        }
        .sheet(item: $editedEntry) { entry in
            BodyEntrySheet(entry: entry, defaultDate: app.now)
        }
        .alert("Eliminare la rilevazione?", isPresented: deleteAlertBinding, presenting: entryToDelete) { entry in
            Button("Elimina", role: .destructive) { app.store.deleteBodyEntry(id: entry.id) }
            Button("Annulla", role: .cancel) {}
        } message: { entry in
            Text("La rilevazione del \(Formatters.shortDate(entry.date, calendar: app.calendar)) verrà rimossa.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )
    }

    // MARK: - Testata

    /// Stessa testata di tutte le altre pagine: niente overline con la data, niente
    /// titolo heavy maiuscolo. Un solo accesso alle Impostazioni in tutta l'app
    /// (l'ingranaggio della Home): qui l'azione è "+".
    private var header: some View {
        PageHeader(title: "Misure") {
            CircleIconButton(systemImage: "plus", accessibilityTitle: "Nuova rilevazione") {
                isAddingEntry = true
            }
        }
    }

    // MARK: - Peso in evidenza

    @ViewBuilder
    private var weightSection: some View {
        if let latest = weightChart.latest {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Peso corporeo")
                        .overlineStyle()

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(BodyFormat.number(latest.value, metric: .weight, unit: app.unit))
                            .hugeNumberStyle()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(app.unit.symbol)
                            .font(.bodyText)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let weightCaption {
                        Text(weightCaption).captionStyle()
                    }
                }
                .accessibilityElement(children: .combine)

                CapsuleSegmentedControl(values: ChartRange.allCases, selection: $range, title: \.title)

                BodyMetricChart(
                    points: weightChart.points,
                    domain: weightChart.domain,
                    metric: .weight,
                    unit: app.unit,
                    calendar: app.calendar,
                    height: 180
                )
            }
        }
    }

    // MARK: - Ricalcolo fuori dal body

    /// Cambia solo quando cambia davvero il grafico: intervallo scelto, numero di
    /// rilevazioni, unità o scheda attiva (che sposta la riga di variazione).
    private var chartSignature: String {
        "\(range.rawValue)|\(app.store.bodyEntries.count)|\(app.unit.rawValue)|\(app.store.activeProgramID?.uuidString ?? "")"
    }

    private func reloadWeightChart() {
        let series = app.store.bodySeries(of: .weight)
        let start = range.start(from: app.now, calendar: app.calendar)
        weightChart = BodyChartData.make(series: series, from: start)
        weightCaption = makeWeightCaption(from: start)
    }

    /// Variazione dall'inizio della scheda attiva; se non c'è una scheda si ripiega
    /// sulla variazione nel periodo scelto.
    private func makeWeightCaption(from start: Date) -> String? {
        if app.store.activeProgram != nil, let change = app.store.bodyChange(of: .weight) {
            return "\(BodyFormat.delta(change, unit: app.unit)) dall'inizio della scheda"
        }
        guard let change = Stats.bodyChange(of: .weight, in: app.store.bodyEntries, since: start) else { return nil }
        return "\(BodyFormat.delta(change, unit: app.unit)) \(range.periodText)"
    }

    // MARK: - Altre metriche

    @ViewBuilder
    private func otherMetrics(_ metrics: [BodyMetricKind]) -> some View {
        let others = metrics.filter { $0 != .weight }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Altre misure")
                    .overlineStyle()
                    .padding(.bottom, Theme.Spacing.xs)

                ForEach(others) { metric in
                    let latest = app.store.latestBodyValue(of: metric)
                    let change = app.store.activeProgram == nil ? nil : app.store.bodyChange(of: metric)
                    PillRow(
                        title: metric.displayName,
                        subtitle: change.map { BodyFormat.delta($0, unit: app.unit) },
                        detail: latest.map { BodyFormat.value($0.value, metric: metric, unit: app.unit) },
                        action: { app.router.push(.bodyMetric(metric)) }
                    )
                }
            }
        }
    }

    // MARK: - Rilevazioni

    @ViewBuilder
    private func entryList(_ entries: [BodyEntry]) -> some View {
        // Pigra: con qualche anno di rilevazioni una `VStack` normale costruirebbe
        // ogni riga (data formattata e riepilogo compresi) a ogni ridisegno.
        LazyVStack(alignment: .leading, spacing: 0) {
            Text("Rilevazioni")
                .overlineStyle()
                .padding(.bottom, Theme.Spacing.s)

            ForEach(entries) { entry in
                ValueRow(
                    title: Formatters.shortDate(entry.date, calendar: app.calendar).firstUppercased,
                    subtitle: summary(of: entry),
                    showsSeparator: entry.id != entries.last?.id
                ) {
                    EllipsisMenu(accessibilityTitle: "Azioni sulla rilevazione") {
                        Button("Modifica") { editedEntry = entry }
                        Button("Elimina", role: .destructive) { entryToDelete = entry }
                    }
                }
            }
        }
    }

    /// "77,2 kg · 16,4% · 4 circonferenze".
    private func summary(of entry: BodyEntry) -> String {
        var parts: [String] = []
        if let weight = entry.weightKg {
            parts.append(BodyFormat.value(weight, metric: .weight, unit: app.unit))
        }
        if let fat = entry.bodyFatPct {
            parts.append(BodyFormat.value(fat, metric: .bodyFat, unit: app.unit))
        }
        let measures = entry.recordedMeasures.count
        if measures > 0 {
            parts.append(measures == 1 ? "1 circonferenza" : "\(measures) circonferenze")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Stato vuoto

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "ruler",
            title: "Nessuna misura",
            message: "Registra peso, composizione o circonferenze: bastano i valori che ti danno in palestra.",
            actionTitle: "Nuova rilevazione",
            action: { isAddingEntry = true }
        )
        .padding(.top, Theme.Spacing.xxxl)
    }
}
