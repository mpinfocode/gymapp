import SwiftUI
import GymCore
import GymUI

/// Pagina "Misure": le metriche corporee registrate almeno una volta e l'elenco
/// delle rilevazioni, con modifica ed eliminazione dal menu "…".
public struct BodyMeasuresScreen: View {

    @Environment(AppEnvironment.self) private var app

    @State private var metricDestination: BodyMetricKind?
    @State private var editedEntry: BodyEntry?
    @State private var isAddingEntry = false
    @State private var entryToDelete: BodyEntry?

    public init() {}

    public var body: some View {
        let entries = app.store.bodyEntries
        let metrics = Stats.recordedBodyMetrics(in: entries)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                header

                if metrics.isEmpty {
                    EmptyStateView(
                        systemImage: "ruler",
                        title: "Nessuna misura",
                        message: "Registra peso, composizione o circonferenze: bastano i valori che ti danno in palestra.",
                        actionTitle: "Nuova rilevazione",
                        action: { isAddingEntry = true }
                    )
                } else {
                    metricList(metrics)
                    entryList(entries)
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
        .navigationDestination(item: $metricDestination) { metric in
            BodyMetricDetailScreen(metric: metric)
        }
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

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text("Misure")
                .sectionTitleStyle()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Theme.Spacing.s)

            CircleIconButton(systemImage: "plus", accessibilityTitle: "Nuova rilevazione") {
                isAddingEntry = true
            }
        }
    }

    // MARK: - Metriche

    @ViewBuilder
    private func metricList(_ metrics: [BodyMetricKind]) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(metrics) { metric in
                let latest = app.store.latestBodyValue(of: metric)
                let change = app.store.bodyChange(of: metric)
                PillRow(
                    title: metric.displayName,
                    subtitle: change.map { "\(BodyFormat.delta($0, unit: app.unit)) dall'inizio della scheda" },
                    detail: latest.map { BodyFormat.value($0.value, metric: metric, unit: app.unit) },
                    action: { metricDestination = metric }
                )
            }
        }
    }

    // MARK: - Rilevazioni

    @ViewBuilder
    private func entryList(_ entries: [BodyEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
}
