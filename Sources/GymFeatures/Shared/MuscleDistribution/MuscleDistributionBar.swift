import SwiftUI
import GymCore
import GymUI

/// Barra orizzontale a segmenti: una quota di colore per zona del corpo.
///
/// Fluidità (SPEC §0): è **una sola view** che disegna in un `Canvas`, senza
/// `GeometryReader` e senza una view per segmento, quindi non innesca un secondo
/// passaggio di layout e non ha animazioni continue. Il disegno dipende solo dalle
/// quote passate: cambia quando cambia la scheda, mai a ogni ridisegno.
public struct MuscleDistributionBar: View {

    private let shares: [Stats.MuscleShare]
    private let height: CGFloat

    /// Spazio fra un segmento e l'altro.
    private let gap: CGFloat = 2
    /// Larghezza sotto la quale un segmento non scenderebbe mai: una serie su
    /// sessanta resta comunque visibile.
    private let minimumSegmentWidth: CGFloat = 5

    /// - Parameters:
    ///   - shares: quote già ordinate (vedi ``Stats/MuscleDistribution/shares``).
    ///   - height: spessore della barra; 12 nella versione estesa, 10 in quella compatta.
    public init(shares: [Stats.MuscleShare], height: CGFloat = 12) {
        self.shares = shares
        self.height = height
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let widths = segmentWidths(in: size.width)
            var x: CGFloat = 0
            for (index, width) in widths.enumerated() {
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                let radius = min(size.height / 2, width / 2)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                    with: .color(MuscleGroupColor.palette(for: shares[index].group).fill)
                )
                x += width + gap
            }
        }
        .frame(height: height)
        .background(emptyTrack)
        .accessibilityElement()
        .accessibilityLabel("Ripartizione dei muscoli colpiti")
        .accessibilityValue(accessibilityValue)
    }

    /// Fondo grigio quando non c'è niente da mostrare: la barra resta una riga
    /// discreta invece di sparire e far saltare il layout.
    @ViewBuilder
    private var emptyTrack: some View {
        if shares.isEmpty {
            Capsule(style: .continuous).fill(Theme.separator)
        }
    }

    /// Larghezze dei segmenti, con un minimo garantito e una normalizzazione finale
    /// perché la somma resti dentro lo spazio disponibile.
    private func segmentWidths(in totalWidth: CGFloat) -> [CGFloat] {
        guard !shares.isEmpty else { return [] }
        let available = max(0, totalWidth - gap * CGFloat(shares.count - 1))
        guard available > 0 else { return Array(repeating: CGFloat(0), count: shares.count) }

        let widths: [CGFloat] = shares.map { max(minimumSegmentWidth, available * CGFloat($0.fraction)) }
        let sum = widths.reduce(0, +)
        guard sum > available, sum > 0 else { return widths }
        return widths.map { $0 * available / sum }
    }

    private var accessibilityValue: String {
        guard !shares.isEmpty else { return "nessun esercizio" }
        return shares
            .map { "\($0.group.displayName) \($0.percent) per cento" }
            .joined(separator: ", ")
    }
}
