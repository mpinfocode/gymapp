import SwiftUI

// Scelta: i mini grafici sono disegnati con `Path` invece che con Swift Charts.
// Motivo: dentro una mini-card servono forme senza assi, senza legenda e senza
// padding automatico, con controllo esatto su tratto, punti e area. Swift Charts
// darebbe più peso (e sorprese di layout) per zero vantaggi a questa dimensione.
// Swift Charts resta la scelta giusta per i grafici grandi di Progressi, che però
// vivono in GymFeatures.

/// Curva sottile con punti, per l'andamento di una metrica.
public struct Sparkline: View {

    private let values: [Double]
    private let tint: AccentPalette
    private let lineWidth: CGFloat
    private let showsPoints: Bool
    private let fillsArea: Bool
    private let accessibilityTitle: String

    /// - Parameters:
    ///   - values: serie di valori, dal più vecchio al più recente.
    ///   - tint: colore di linea, punti e area.
    ///   - lineWidth: spessore della linea.
    ///   - showsPoints: disegna un pallino su ogni campione.
    ///   - fillsArea: riempie l'area sotto la curva con una sfumatura.
    ///   - accessibilityTitle: etichetta VoiceOver.
    public init(
        values: [Double],
        tint: AccentPalette = Theme.Metric.viola,
        lineWidth: CGFloat = 2,
        showsPoints: Bool = true,
        fillsArea: Bool = true,
        accessibilityTitle: String = "Andamento"
    ) {
        self.values = values
        self.tint = tint
        self.lineWidth = lineWidth
        self.showsPoints = showsPoints
        self.fillsArea = fillsArea
        self.accessibilityTitle = accessibilityTitle
    }

    public var body: some View {
        GeometryReader { geo in
            let points = Self.points(for: values, in: geo.size, inset: lineWidth + (showsPoints ? 2 : 0))
            ZStack {
                if fillsArea, points.count > 1 {
                    areaPath(points, height: geo.size.height)
                        .fill(
                            LinearGradient(
                                colors: [tint.fill.opacity(0.85), tint.fill.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                if points.count > 1 {
                    linePath(points)
                        .stroke(tint.deep, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                if showsPoints {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(tint.deep)
                            .frame(width: lineWidth * 1.9, height: lineWidth * 1.9)
                            .position(point)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(Text(Self.trendDescription(values)))
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func areaPath(_ points: [CGPoint], height: CGFloat) -> Path {
        var path = linePath(points)
        if let last = points.last, let first = points.first {
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.addLine(to: CGPoint(x: first.x, y: height))
            path.closeSubpath()
        }
        return path
    }

    /// Normalizza i valori nello spazio della view (y invertito).
    static func points(for values: [Double], in size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard values.count > 1 else {
            guard !values.isEmpty else { return [] }
            return [CGPoint(x: size.width / 2, y: size.height / 2)]
        }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let span = maxValue - minValue
        let usableHeight = max(size.height - inset * 2, 1)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let normalized = span > 0 ? (value - minValue) / span : 0.5
            return CGPoint(
                x: CGFloat(index) * stepX,
                y: inset + usableHeight * (1 - CGFloat(normalized))
            )
        }
    }

    static func trendDescription(_ values: [Double]) -> String {
        guard let first = values.first, let last = values.last, values.count > 1 else {
            return "nessun dato"
        }
        if last > first { return "in aumento" }
        if last < first { return "in calo" }
        return "stabile"
    }
}

/// Mini istogramma a barre arrotondate.
public struct MiniBars: View {

    private let values: [Double]
    private let tint: AccentPalette
    private let highlightedIndex: Int?
    private let accessibilityTitle: String

    /// - Parameters:
    ///   - values: valori delle barre, dal più vecchio al più recente.
    ///   - tint: colore delle barre.
    ///   - highlightedIndex: indice della barra da evidenziare (le altre sono smorzate).
    ///   - accessibilityTitle: etichetta VoiceOver.
    public init(
        values: [Double],
        tint: AccentPalette = Theme.Metric.arancio,
        highlightedIndex: Int? = nil,
        accessibilityTitle: String = "Valori per periodo"
    ) {
        self.values = values
        self.tint = tint
        self.highlightedIndex = highlightedIndex
        self.accessibilityTitle = accessibilityTitle
    }

    public var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 0.0001)
            let spacing = max(geo.size.width * 0.06 / CGFloat(max(values.count, 1)), 2)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let fraction = max(min(value / maxValue, 1), 0)
                    let isDimmed = highlightedIndex != nil && highlightedIndex != index
                    Capsule(style: .continuous)
                        .fill(isDimmed ? tint.fill.opacity(0.45) : tint.fill)
                        .frame(height: max(geo.size.height * CGFloat(fraction), 3))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(Text("\(values.count) periodi"))
    }
}
