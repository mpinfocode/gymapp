import SwiftUI
import GymCore
import GymUI

/// Riga di un esercizio: thumbnail, nome, sottoriga "muscolo · attrezzo" in italiano.
///
/// È la riga usata in lista Esercizi, nel picker, nell'editor della scheda e nello
/// storico: l'accessorio a destra è generico (chevron, spunta, bottone, conteggio…)
/// così la riga resta una sola in tutta l'app.
///
/// Il titolo è ``Exercise/shortDisplayName``: il prefisso dell'attrezzo sparisce dal
/// nome perché la sottoriga lo dice già in italiano.
///
///     ExerciseRowView(exercise: exercise)                       // senza accessorio
///     ExerciseRowView(exercise: exercise) { Chevron() }         // accessorio libero
///     ExerciseRowView(exercise: exercise, subtitle: "4 × 8-12") // sottoriga forzata
public struct ExerciseRowView<Accessory: View>: View {

    private let exercise: Exercise
    private let subtitle: String?
    private let accessory: Accessory

    /// - Parameters:
    ///   - exercise: esercizio da mostrare.
    ///   - subtitle: sottoriga personalizzata; se `nil` usa "muscolo · attrezzo".
    ///   - accessory: contenuto allineato a destra.
    public init(
        exercise: Exercise,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.exercise = exercise
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    /// Sottoriga di default: "Pettorali · Bilanciere", con "·" come separatore.
    public static func defaultSubtitle(for exercise: Exercise) -> String {
        [exercise.localizedTarget, exercise.localizedEquipment]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            RemoteImage(
                url: exercise.imageURL,
                side: 56,
                cornerRadius: Theme.Radius.small,
                showsBorder: true
            )

            VStack(alignment: .leading, spacing: 2) {
                // Titolo senza il prefisso dell'attrezzo: "Manubri" è già scritto
                // nella sottoriga, ripeterlo nel titolo è solo rumore (SPEC §0).
                Text(exercise.shortDisplayName)
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                let detail = subtitle ?? Self.defaultSubtitle(for: exercise)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
        }
        .frame(minHeight: Theme.Size.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension ExerciseRowView where Accessory == EmptyView {

    /// Riga senza accessorio a destra.
    public init(exercise: Exercise, subtitle: String? = nil) {
        self.init(exercise: exercise, subtitle: subtitle) { EmptyView() }
    }
}
