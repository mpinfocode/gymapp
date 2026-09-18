import SwiftUI
import GymCore
import GymUI

/// Foglio "Nuova rilevazione" (e modifica di una esistente).
///
/// Tutti i campi sono facoltativi: si salva anche solo il peso. I campi si
/// generano dall'astrazione uniforme ``BodyMetricKind``, così non c'è codice per
/// singola metrica; accanto a ognuno compare l'ultimo valore noto come riferimento.
public struct BodyEntrySheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// Rilevazione da modificare; `nil` per crearne una nuova.
    private let entry: BodyEntry?

    @State private var date: Date
    /// Valori nell'unità mostrata all'utente: la conversione in kg avviene al salvataggio.
    @State private var values: [BodyMetricKind: Double]
    @State private var showsComposition: Bool
    @State private var showsMeasures: Bool

    public init(entry: BodyEntry?, defaultDate: Date) {
        self.entry = entry
        _date = State(initialValue: entry?.date ?? defaultDate)
        _values = State(initialValue: [:])
        _showsComposition = State(initialValue: true)
        // Le circonferenze sono chiuse di default: si aprono solo se c'erano già.
        _showsMeasures = State(initialValue: !(entry?.recordedMeasures.isEmpty ?? true))
    }

    private var measureMetrics: [BodyMetricKind] {
        BodyMeasure.allCases.map(BodyMetricKind.measure)
    }

    private var canSave: Bool {
        values.values.contains { $0.isFinite }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                header
                dateRow

                CollapsibleSection(title: "Peso e composizione", isExpanded: $showsComposition) {
                    fields(BodyMetricKind.compositionCases)
                }

                CollapsibleSection(title: "Circonferenze", isExpanded: $showsMeasures) {
                    fields(measureMetrics)
                }

                PrimaryButton("Salva", isEnabled: canSave, action: save)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
        .keyboardDoneToolbar()
        .onAppear(perform: loadExistingValues)
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button("Annulla") { dismiss() }
                .font(.bodyText)
                .foregroundStyle(Theme.textSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)

            Text(entry == nil ? "Nuova rilevazione" : "Modifica rilevazione")
                .sectionTitleStyle()
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var dateRow: some View {
        DatePicker(
            "Data",
            selection: $date,
            in: ...app.now,
            displayedComponents: .date
        )
        .font(.bodyText)
        .foregroundStyle(Theme.textPrimary)
        .frame(minHeight: Theme.Size.minTapTarget)
    }

    // MARK: - Campi

    @ViewBuilder
    private func fields(_ metrics: [BodyMetricKind]) -> some View {
        VStack(spacing: 0) {
            ForEach(metrics) { metric in
                field(metric, showsSeparator: metric != metrics.last)
            }
        }
    }

    private func field(_ metric: BodyMetricKind, showsSeparator: Bool) -> some View {
        let last = app.store.latestBodyValue(of: metric)
        return VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.displayName)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let last {
                        Text("ultimo \(BodyFormat.value(last.value, metric: metric, unit: app.unit))")
                            .font(.captionText)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                NumberCapsuleField(
                    value: binding(for: metric),
                    placeholder: Formatters.missing,
                    accessibilityTitle: metric.displayName
                )
                .frame(width: 92)

                Text(BodyFormat.symbol(metric, unit: app.unit))
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, alignment: .leading)
            }
            .padding(.vertical, Theme.Spacing.s)

            if showsSeparator {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.Size.hairline)
            }
        }
    }

    private func binding(for metric: BodyMetricKind) -> Binding<Double?> {
        Binding(
            get: { values[metric] },
            set: { newValue in
                if let newValue, newValue.isFinite {
                    values[metric] = newValue
                } else {
                    values.removeValue(forKey: metric)
                }
            }
        )
    }

    // MARK: - Dati

    private func loadExistingValues() {
        guard let entry, values.isEmpty else { return }
        var loaded: [BodyMetricKind: Double] = [:]
        for metric in entry.recordedMetrics {
            guard let stored = metric.value(in: entry) else { continue }
            loaded[metric] = BodyFormat.displayValue(stored, metric: metric, unit: app.unit)
        }
        values = loaded
    }

    private func save() {
        var result = BodyEntry(id: entry?.id ?? UUID(), date: date)
        for (metric, value) in values {
            result.setValue(BodyFormat.storedValue(value, metric: metric, unit: app.unit), for: metric)
        }
        if entry == nil {
            app.store.addBodyEntry(result)
        } else {
            app.store.updateBodyEntry(result)
        }
        dismiss()
    }
}
