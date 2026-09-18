import SwiftUI
import GymCore
import GymUI

/// GIF ingrandita e istruzioni a passi: si apre toccando la GIF della sessione.
@MainActor
struct ExerciseInstructionsSheet: View {

    @Environment(AppEnvironment.self) private var app

    let exerciseID: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let exercise {
                    AnimatedGIFView(
                        url: exercise.gifURL,
                        side: 240,
                        cornerRadius: Theme.Radius.medium,
                        showsBorder: false,
                        accessibilityTitle: "Animazione di \(exercise.displayName)"
                    )
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(exercise.displayName)
                            .sectionTitleStyle()
                        Text(subtitle(for: exercise))
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if !exercise.steps.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            ForEach(Array(exercise.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                                    Text("\(index + 1)")
                                        .font(.system(.subheadline, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(width: 20, alignment: .trailing)
                                    Text(step)
                                        .font(.bodyText)
                                        .foregroundStyle(Theme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Text(Exercise.displayAttribution)
                        .font(.system(.caption2, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    EmptyStateView(
                        systemImage: "questionmark.circle",
                        title: "Esercizio non disponibile",
                        message: "Non ci sono istruzioni per questo esercizio."
                    )
                }
            }
            .padding(Theme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pageBackground()
        .immersiveDark()
        .presentationDetents([.large])
    }

    private var exercise: Exercise? { app.store.exercise(id: exerciseID) }

    private func subtitle(for exercise: Exercise) -> String {
        [exercise.localizedTarget, exercise.localizedEquipment]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
