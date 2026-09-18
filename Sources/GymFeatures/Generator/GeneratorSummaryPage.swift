import SwiftUI
import GymCore
import GymUI

/// Riepilogo delle dieci risposte, con "Crea scheda".
///
/// Ogni riga è toccabile e riporta alla sua domanda: correggere una risposta non
/// deve costare dieci "Indietro".
struct GeneratorSummaryPage: View {

    @Bindable var model: GeneratorFlowModel
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    rows
                    Text("Tocca una riga per cambiare quella risposta.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, Theme.Spacing.xs)
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrimaryButton("Crea scheda", action: onCreate)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.background.ignoresSafeArea(edges: .bottom))
        }
        .pageBackground()
    }

    private var header: some View {
        SheetHeader(
            title: "Ci siamo",
            subtitle: "Controlla le risposte, poi crea la scheda.",
            back: { model.goBack() },
            actionTitle: "Annulla",
            action: onCancel
        )
        .sheetHeaderMargins()
    }

    // MARK: - Righe

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(GeneratorStep.allCases.enumerated()), id: \.element) { index, step in
                if index > 0 {
                    Divider().overlay(Theme.separator).padding(.leading, Theme.Spacing.l)
                }
                row(step)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func row(_ step: GeneratorStep) -> some View {
        Button {
            withAnimation(Theme.Motion.quick) { model.jump(to: step) }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Text(step.summaryLabel)
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)

                Spacer(minLength: Theme.Spacing.m)

                Text(value(for: step))
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .frame(minHeight: Theme.Size.minTapTarget + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Torna a questa domanda"))
    }

    /// Il valore scelto, scritto come lo direbbe una persona.
    private func value(for step: GeneratorStep) -> String {
        switch step {
        case .goal: model.goal.displayName
        case .days: "\(model.daysPerWeek)"
        case .split: splitValue
        case .experience: model.experience.displayName
        case .sessionLength: model.sessionLength.displayName
        case .equipment: model.equipment.displayName
        case .focus: model.focusGroups.isEmpty ? "Niente in particolare" : GeneratorCopy.groupList(model.focusGroups)
        case .protect: model.protectedZones.isEmpty ? "Nessuna" : GeneratorCopy.zoneList(model.protectedZones)
        case .cardio: model.includeCardio ? "Sì" : "No"
        case .weeks: "\(model.weeks) settimane"
        }
    }

    /// Con "Consigliata" si mostra anche quale divisione uscirà davvero: il
    /// riepilogo non deve nascondere una decisione presa dall'app.
    private var splitValue: String {
        model.splitChoice == nil
            ? "\(model.resolvedSplit.displayName) (consigliata)"
            : model.resolvedSplit.displayName
    }
}
