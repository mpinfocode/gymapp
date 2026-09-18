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

    /// Titolo e sottoriga già pronti: nel `body` non si formatta più niente.
    private let presentation: ExercisePresentation
    private let imageURL: URL?
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
        self.init(
            presentation: ExercisePresentation(exercise: exercise),
            imageURL: exercise.imageURL,
            subtitle: subtitle,
            accessory: accessory
        )
    }

    /// Variante con la presentazione **già calcolata** da GymCore
    /// (``AppStore/exercisePresentation(id:)``): è quella da preferire nelle liste
    /// lunghe, dove ricavare titolo e sottoriga dall'``Exercise`` a ogni `body`
    /// costava una manciata di stringhe per riga a ogni scorrimento.
    ///
    /// - Parameters:
    ///   - presentation: id, titolo e sottoriga pronti.
    ///   - imageURL: thumbnail; `nil` per gli esercizi personalizzati.
    ///   - subtitle: sottoriga personalizzata che sostituisce quella pronta.
    public init(
        presentation: ExercisePresentation,
        imageURL: URL?,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.presentation = presentation
        self.imageURL = imageURL
        self.accessory = accessory()
        if let subtitle {
            self.detail = subtitle
        } else {
            self.detail = presentation.subtitle
        }
    }

    private let detail: String

    /// Sottoriga di default: "Pettorali · Bilanciere", con "·" come separatore.
    public static func defaultSubtitle(for exercise: Exercise) -> String {
        ExercisePresentation.subtitle(for: exercise)
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            RemoteImage(
                url: imageURL,
                side: 56,
                cornerRadius: Theme.Radius.small,
                showsBorder: true
            )

            VStack(alignment: .leading, spacing: 2) {
                // Titolo senza il prefisso dell'attrezzo: "Manubri" è già scritto
                // nella sottoriga, ripeterlo nel titolo è solo rumore (SPEC §0).
                Text(presentation.title)
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

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

    /// Riga senza accessorio, con la presentazione già calcolata.
    public init(presentation: ExercisePresentation, imageURL: URL?, subtitle: String? = nil) {
        self.init(presentation: presentation, imageURL: imageURL, subtitle: subtitle) { EmptyView() }
    }
}
