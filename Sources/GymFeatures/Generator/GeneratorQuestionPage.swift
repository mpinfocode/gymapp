import SwiftUI
import GymCore
import GymUI

/// Una domanda del wizard: testata, avanzamento, opzioni, ed eventualmente il
/// bottone "Avanti" con "Salta" sotto.
///
/// Le domande a scelta singola non hanno nessun bottone: si tocca la risposta e
/// si passa avanti da soli. È il motivo per cui dieci domande non sembrano dieci.
struct GeneratorQuestionPage: View {

    @Bindable var model: GeneratorFlowModel
    let onCancel: () -> Void

    /// Attesa fra il tocco e il passaggio alla domanda dopo: giusto il tempo di
    /// vedere la risposta accendersi. Senza, la selezione non si vede proprio.
    private static let advanceDelay = Duration.milliseconds(180)

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    options
                    if model.step == .protect {
                        disclaimer
                    }
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .pageBackground()
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            SheetHeader(
                title: model.step.title,
                subtitle: model.step.subtitle,
                back: model.canGoBack ? { model.goBack() } : nil,
                actionTitle: "Annulla",
                action: onCancel
            )

            GeneratorProgressBar(index: model.step.number, total: GeneratorStep.count)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xl)
    }

    // MARK: - Opzioni

    @ViewBuilder
    private var options: some View {
        switch model.step {
        case .goal:
            ForEach(TrainingGoal.allCases) { goal in
                single(goal.displayName, goal.explanation, model.goal == goal) { model.goal = goal }
            }

        case .days:
            ForEach(Array(GeneratorAnswers.daysRange), id: \.self) { value in
                let copy = GeneratorCopy.days(value)
                single(copy.title, copy.detail, model.daysPerWeek == value) { model.daysPerWeek = value }
            }

        case .split:
            GeneratorOptionRow(
                title: "Consigliata",
                detail: GeneratorCopy.recommendedSplitDetail(days: model.daysPerWeek, experience: model.experience),
                isSelected: model.splitChoice == nil
            ) {
                choose { model.splitChoice = nil }
            }
            ForEach(model.availableSplits) { split in
                single(split.displayName, split.explanation, model.splitChoice == split) {
                    model.splitChoice = split
                }
            }

        case .experience:
            ForEach(TrainingExperience.allCases) { value in
                single(value.displayName, value.explanation, model.experience == value) {
                    model.experience = value
                }
            }

        case .sessionLength:
            ForEach(SessionLength.allCases) { value in
                single(value.displayName, GeneratorCopy.sessionLength(value), model.sessionLength == value) {
                    model.sessionLength = value
                }
            }

        case .equipment:
            ForEach(EquipmentAvailability.allCases) { value in
                single(value.displayName, GeneratorCopy.equipment(value), model.equipment == value) {
                    model.equipment = value
                }
            }

        case .focus:
            ForEach(GeneratorCopy.focusableGroups) { group in
                GeneratorOptionRow(
                    title: group.displayName,
                    detail: GeneratorCopy.focus(group),
                    isSelected: model.focusGroups.contains(group),
                    isMultipleChoice: true,
                    isDimmed: model.focusGroups.count >= GeneratorFlowModel.maxFocusGroups
                ) {
                    if model.toggleFocus(group) { Haptics.play(.selection) }
                }
            }

        case .protect:
            ForEach(StressZone.displayOrder) { zone in
                GeneratorOptionRow(
                    title: zone.displayName,
                    detail: GeneratorCopy.protect(zone),
                    isSelected: model.protectedZones.contains(zone),
                    isMultipleChoice: true
                ) {
                    model.toggleProtected(zone)
                    Haptics.play(.selection)
                }
            }

        case .cardio:
            ForEach([true, false], id: \.self) { value in
                let copy = GeneratorCopy.cardio(value)
                single(copy.title, copy.detail, model.includeCardio == value) { model.includeCardio = value }
            }

        case .weeks:
            ForEach(GeneratorCopy.weekOptions, id: \.self) { value in
                let copy = GeneratorCopy.weeks(value)
                single(copy.title, copy.detail, model.weeks == value) { model.weeks = value }
            }
        }
    }

    /// Riga a scelta singola: seleziona e passa avanti.
    private func single(
        _ title: String,
        _ detail: String,
        _ isSelected: Bool,
        set: @escaping () -> Void
    ) -> some View {
        GeneratorOptionRow(title: title, detail: detail, isSelected: isSelected) {
            choose(set)
        }
    }

    /// Applica la scelta, vibra e avanza dopo un istante.
    private func choose(_ set: @escaping () -> Void) {
        set()
        Haptics.play(.selection)
        Task {
            try? await Task.sleep(for: Self.advanceDelay)
            withAnimation(Theme.Motion.quick) { model.advance() }
        }
    }

    // MARK: - Avviso della domanda sulle zone da proteggere

    private var disclaimer: some View {
        Text(GeneratorCopy.medicalDisclaimer)
            .font(.captionText)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Theme.Spacing.s)
    }

    // MARK: - Fondo

    /// Solo le domande facoltative hanno bottoni: "Avanti" e, sotto, "Salta".
    @ViewBuilder
    private var footer: some View {
        if model.step.isOptional {
            VStack(spacing: 0) {
                PrimaryButton("Avanti") {
                    withAnimation(Theme.Motion.quick) { model.advance() }
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.m)

                GeneratorTextAction("Salta") {
                    withAnimation(Theme.Motion.quick) { model.skipCurrentQuestion() }
                }
                .padding(.bottom, Theme.Spacing.xs)
            }
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
        }
    }
}
