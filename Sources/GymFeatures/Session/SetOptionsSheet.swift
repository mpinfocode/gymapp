import SwiftUI
import GymCore
import GymUI

/// Opzioni avanzate della singola serie: tipo, RPE, rimozione.
///
/// Sta un livello sotto (long-press sulla riga o menu "…"): il percorso base in
/// palestra resta "guarda i numeri, tocca ✓".
/// È `public` solo perché la scena di screenshot `sessione-menu` la rende da sola:
/// dentro l'app si apre unicamente dalla sessione attiva.
@MainActor
public struct SetOptionsSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entryID: UUID
    let setID: UUID

    public init(entryID: UUID, setID: UUID) {
        self.entryID = entryID
        self.setID = setID
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Serie \(label)")
                        .sectionTitleStyle()
                    Text(exerciseName)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("TIPO DI SERIE").overlineStyle()
                    kindChips
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("RPE").overlineStyle()
                    rpeChips
                }

                Button(role: .destructive) {
                    app.store.removeSet(id: setID, fromEntry: entryID)
                    dismiss()
                } label: {
                    Text("Rimuovi la serie")
                        .font(.bodyText)
                        .foregroundStyle(Theme.Metric.rosa.deep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: Theme.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pageBackground()
        .immersiveDark()
        .presentationDetents([.medium, .large])
    }

    // MARK: - Tipo di serie

    private var kindChips: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(kindRows.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(kindRows[index]) { kind in
                        FilterChip(kind.displayName, isSelected: currentKind == kind) {
                            app.store.updateSet(id: setID, inEntry: entryID) { $0.kind = kind }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var kindRows: [[SetKind]] {
        [[.warmup, .normal], [.drop, .failure]]
    }

    // MARK: - RPE

    private var rpeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                FilterChip("nessuno", isSelected: currentRPE == nil) {
                    app.store.updateSet(id: setID, inEntry: entryID) { $0.rpe = nil }
                }
                ForEach(SetLog.rpeScale, id: \.self) { value in
                    FilterChip(Formatters.decimal(value), isSelected: currentRPE == value) {
                        app.store.updateSet(id: setID, inEntry: entryID) { $0.rpe = value }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Stato

    private var entry: SessionEntry? {
        app.store.activeSession?.entries.first { $0.id == entryID }
    }

    private var currentSet: SetLog? {
        entry?.sets.first { $0.id == setID }
    }

    private var currentKind: SetKind { currentSet?.kind ?? .normal }

    private var currentRPE: Double? { currentSet?.rpe }

    private var label: String {
        guard let entry else { return "" }
        return SessionPresentation.setLabels(for: entry)[setID] ?? ""
    }

    private var exerciseName: String {
        guard let entry else { return "" }
        return app.store.exerciseDisplayName(id: entry.exerciseID)
    }
}
