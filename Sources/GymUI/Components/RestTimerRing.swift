import SwiftUI

/// Anello del timer di recupero: si svuota mentre scorre il tempo, con il tempo al centro.
public struct RestTimerRing: View {

    private let remaining: Int
    private let total: Int
    private let diameter: CGFloat
    private let tint: AccentPalette
    private let caption: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - remaining: secondi mancanti.
    ///   - total: durata totale del recupero in secondi.
    ///   - diameter: diametro dell'anello.
    ///   - tint: colore dell'anello.
    ///   - caption: testo minuscolo sotto al tempo (es. "recupera").
    public init(
        remaining: Int,
        total: Int,
        diameter: CGFloat = 220,
        tint: AccentPalette = Theme.accent,
        caption: String? = nil
    ) {
        self.remaining = max(remaining, 0)
        self.total = max(total, 1)
        self.diameter = diameter
        self.tint = tint
        self.caption = caption
    }

    private var fraction: Double {
        min(max(Double(remaining) / Double(total), 0), 1)
    }

    private var timeText: String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        return minutes > 0
            ? String(format: "%d:%02d", minutes, seconds)
            : String(format: "0:%02d", seconds)
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.separator, style: StrokeStyle(lineWidth: 10, lineCap: .round))

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint.fill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: fraction)

            VStack(spacing: Theme.Spacing.xs) {
                Text(timeText)
                    .font(.system(size: diameter * 0.26, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption)
                        .font(.system(.subheadline, weight: .light))
                        .textCase(.lowercase)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption ?? "Timer di recupero"))
        .accessibilityValue(Text("\(remaining) secondi rimanenti"))
    }
}
