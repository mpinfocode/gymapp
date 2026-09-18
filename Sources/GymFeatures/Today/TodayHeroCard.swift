import SwiftUI
import GymUI

/// La hero di Oggi: una sola card, quattro stati possibili.
///
/// Il gradiente nasce dall'accento della scheda attiva, così la scheda si riconosce
/// qui, in Scheda e nella sessione. Un solo bottone primario visibile, mai due.
struct TodayHeroCard: View {

    /// Cosa mostra la card.
    enum Variant: Equatable {
        /// Giorno proposto (o scelto a mano) da allenare.
        case workout(title: String, summary: String)
        /// Sessione in corso, cover minimizzata.
        case running(title: String, summary: String)
        /// Allenamento già completato oggi.
        case completed(title: String, value: String, detail: String)
        /// Giorno di riposo.
        case rest
    }

    let seed: Int
    let chipText: String
    let variant: Variant
    /// Azione del bottone primario ("Inizia" / "Riprendi").
    let onPrimary: () -> Void
    /// Azione discreta del giorno di riposo.
    let onTrainAnyway: () -> Void

    var body: some View {
        HeroCard(seed: seed, chipText: chipText, chipSystemImage: nil) { palette in
            switch variant {
            case .workout(let title, let summary):
                heading(title, summary: summary, foreground: palette.foreground)
                PrimaryButton("Inizia", action: onPrimary)
                    .padding(.top, Theme.Spacing.s)

            case .running(let title, let summary):
                heading(title, summary: summary, foreground: palette.foreground)
                PrimaryButton("Riprendi", action: onPrimary)
                    .padding(.top, Theme.Spacing.s)

            case .completed(let title, let value, let detail):
                Text(title)
                    .font(.bodyEmphasis)
                    .foregroundStyle(palette.foreground.opacity(0.7))
                Text(value)
                    .hugeNumberStyle(color: palette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(detail)
                    .font(.captionText)
                    .foregroundStyle(palette.foreground.opacity(0.7))

            case .rest:
                heading(
                    "Riposo",
                    summary: "Oggi la scheda non prevede allenamento.",
                    foreground: palette.foreground
                )
                Button(action: onTrainAnyway) {
                    Text("Allenati comunque")
                        .font(.system(.subheadline, weight: .medium))
                        .underline()
                        .foregroundStyle(palette.foreground.opacity(0.75))
                        .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Allenati comunque"))
            }
        }
    }

    @ViewBuilder
    private func heading(_ title: String, summary: String, foreground: Color) -> some View {
        Text(title)
            .font(.greeting)
            .foregroundStyle(foreground)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
        Text(summary)
            .font(.captionText)
            .foregroundStyle(foreground.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }
}
