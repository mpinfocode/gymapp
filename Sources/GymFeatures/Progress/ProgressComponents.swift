import SwiftUI
import GymCore
import GymUI

// Mattoni piccoli usati solo dentro Progressi. I mini grafici stanno già in GymUI:
// qui ci sono solo gli involucri che decidono cosa mostrare quando il dato manca.

/// Slot vuoto di una card: nessun numero finto, solo una riga sobria.
struct EmptyChartSlot: View {

    var body: some View {
        Text("Nessun dato")
            .font(.captionText)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Curva della card, o stato vuoto se i punti non bastano.
struct SparklineSlot: View {

    let values: [Double]
    let tint: AccentPalette
    var accessibilityTitle: String = "Andamento"

    var body: some View {
        if values.count > 1 {
            Sparkline(values: values, tint: tint, accessibilityTitle: accessibilityTitle)
        } else {
            EmptyChartSlot()
        }
    }
}

/// Istogramma della card, o stato vuoto se non c'è niente da mostrare.
struct BarsSlot: View {

    let values: [Double]
    let tint: AccentPalette
    var highlightsLast: Bool = true
    var accessibilityTitle: String = "Valori per periodo"

    var body: some View {
        if values.contains(where: { $0 > 0 }) {
            MiniBars(
                values: values,
                tint: tint,
                highlightedIndex: highlightsLast ? values.count - 1 : nil,
                accessibilityTitle: accessibilityTitle
            )
        } else {
            EmptyChartSlot()
        }
    }
}

/// Barre orizzontali sottili: serie per gruppo muscolare della settimana.
struct MuscleGroupBars: View {

    let facets: [MuscleGroupFacet]

    private var maximum: Double {
        Double(facets.map(\.count).max() ?? 1)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(facets) { facet in
                HStack(spacing: Theme.Spacing.m) {
                    Text(facet.label)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(width: 92, alignment: .leading)

                    ThickProgressBar(
                        value: Double(facet.count),
                        total: maximum,
                        height: 6,
                        tint: Theme.ink
                    )

                    Text("\(facet.count)")
                        .font(.system(.footnote, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 22, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(facet.label))
                .accessibilityValue(Text("\(facet.count) serie"))
            }
        }
    }
}

/// Riga di tre numeri con etichetta sotto (durata, volume, serie).
struct StatTriple: View {

    struct Item: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.value)
                        .font(.bigNumber)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.label)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Riga di un elenco di valori: titolo (+ sottotitolo) a sinistra, valore a destra.
/// Separatore hairline sotto, tranne l'ultima.
struct ValueRow<Trailing: View>: View {

    let title: String
    var subtitle: String?
    var showsSeparator: Bool = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                trailing
            }
            .frame(minHeight: Theme.Size.minTapTarget)

            if showsSeparator {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.Size.hairline)
            }
        }
    }
}

extension ValueRow where Trailing == Text {

    /// Variante con un valore testuale a destra.
    init(title: String, subtitle: String? = nil, value: String, showsSeparator: Bool = true) {
        self.init(title: title, subtitle: subtitle, showsSeparator: showsSeparator) {
            Text(value)
                .font(.system(.body, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Sezione richiudibile del foglio "Nuova rilevazione".
struct CollapsibleSection<Content: View>: View {

    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button {
                withAnimation(Theme.Motion.smooth) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .overlineStyle()
                    Spacer(minLength: Theme.Spacing.s)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(isExpanded ? "aperta" : "chiusa"))
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                content
            }
        }
    }
}

/// Bottone circolare discreto da 44pt su `surface`: il "+" delle testate.
/// Non ruba la scena al titolo come farebbe una capsula `ink`.
struct CircleIconButton: View {

    let systemImage: String
    let accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

/// Menu "…" di una riga o di una pagina: stesso aspetto ovunque.
struct EllipsisMenu<Content: View>: View {

    var accessibilityTitle: String = "Altre azioni"
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(accessibilityTitle))
    }
}
