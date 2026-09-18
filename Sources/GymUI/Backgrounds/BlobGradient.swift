import SwiftUI

/// Una delle 8 palette pastello curate usate per i gradienti organici delle schede.
///
/// Ogni colore è adattivo: in chiaro il fondo è una tinta chiarissima e le macchie
/// sono pastello; in scuro il fondo diventa quasi nero e le macchie restano luminose
/// e morbide. `foreground` e `scrim` seguono lo stesso tema, così il testo sopra la
/// card resta leggibile in entrambi i casi.
public struct BlobPalette: Sendable, Hashable, Identifiable {
    /// Indice della palette (0...7).
    public let id: Int
    /// Nome descrittivo, utile in debug e nella gallery.
    public let name: String
    /// Colore di fondo alto.
    public let base: Color
    /// Colore di fondo basso.
    public let baseEnd: Color
    /// Le tre macchie sfocate, dalla più ampia alla più piccola.
    public let blobs: [Color]
    /// Colore consigliato per il testo sopra questo gradiente.
    public let foreground: Color
    /// Velo da stendere sotto al testo per garantirne il contrasto.
    public let scrim: Color

    init(id: Int, name: String, base: Color, baseEnd: Color, blobs: [Color]) {
        self.id = id
        self.name = name
        self.base = base
        self.baseEnd = baseEnd
        self.blobs = blobs
        self.foreground = Self.foreground
        self.scrim = Self.scrim
    }

    /// Testo sopra il gradiente: quasi nero in chiaro, quasi bianco in scuro.
    static let foreground = Color.adaptive(light: Color(hex: 0x1A1A1F), dark: Color(hex: 0xF5F5F7))
    /// Velo di contrasto: bianco tenue in chiaro, nero tenue in scuro.
    static let scrim = Color.adaptive(
        light: Color(hex: 0xFFFFFF, opacity: 0.45),
        dark: Color(hex: 0x000000, opacity: 0.42)
    )

    /// Palette corrispondente al seed (qualsiasi intero, anche negativo).
    public static func palette(for seed: Int) -> BlobPalette {
        all[((seed % all.count) + all.count) % all.count]
    }

    /// Le 8 combinazioni pastello curate: 4 calde, 4 fredde.
    public static let all: [BlobPalette] = [
        BlobPalette(
            id: 0, name: "pesca",
            base: .adaptive(light: Color(hex: 0xFDF2EA), dark: Color(hex: 0x14100C)),
            baseEnd: .adaptive(light: Color(hex: 0xFBE8DC), dark: Color(hex: 0x0A0806)),
            blobs: [
                .adaptive(light: Color(hex: 0xFBD9BF), dark: Color(hex: 0xD9A278)),
                .adaptive(light: Color(hex: 0xF7C7C3), dark: Color(hex: 0xD18F88)),
                .adaptive(light: Color(hex: 0xFBE7C0), dark: Color(hex: 0xD6BA82)),
            ]
        ),
        BlobPalette(
            id: 1, name: "menta",
            base: .adaptive(light: Color(hex: 0xEDF8F2), dark: Color(hex: 0x0A1410)),
            baseEnd: .adaptive(light: Color(hex: 0xE2F2EC), dark: Color(hex: 0x050A08)),
            blobs: [
                .adaptive(light: Color(hex: 0xC2E8D2), dark: Color(hex: 0x76BA98)),
                .adaptive(light: Color(hex: 0xBFE3E8), dark: Color(hex: 0x74AFB8)),
                .adaptive(light: Color(hex: 0xDDF0D8), dark: Color(hex: 0x9CC48F)),
            ]
        ),
        BlobPalette(
            id: 2, name: "lilla",
            base: .adaptive(light: Color(hex: 0xF3F0FB), dark: Color(hex: 0x100E18)),
            baseEnd: .adaptive(light: Color(hex: 0xECE8F7), dark: Color(hex: 0x08070E)),
            blobs: [
                .adaptive(light: Color(hex: 0xD8D2F2), dark: Color(hex: 0x8C82C4)),
                .adaptive(light: Color(hex: 0xE3D2F0), dark: Color(hex: 0x9B82BF)),
                .adaptive(light: Color(hex: 0xCBD5F5), dark: Color(hex: 0x7B89C9)),
            ]
        ),
        BlobPalette(
            id: 3, name: "salvia",
            base: .adaptive(light: Color(hex: 0xF0F5EE), dark: Color(hex: 0x0C120C)),
            baseEnd: .adaptive(light: Color(hex: 0xE7EFE4), dark: Color(hex: 0x060906)),
            blobs: [
                .adaptive(light: Color(hex: 0xCFE3C8), dark: Color(hex: 0x82A879)),
                .adaptive(light: Color(hex: 0xDDEBCE), dark: Color(hex: 0x97B27E)),
                .adaptive(light: Color(hex: 0xBFDDCB), dark: Color(hex: 0x72A88C)),
            ]
        ),
        BlobPalette(
            id: 4, name: "cipria",
            base: .adaptive(light: Color(hex: 0xFCF0F4), dark: Color(hex: 0x160F12)),
            baseEnd: .adaptive(light: Color(hex: 0xF7E8EE), dark: Color(hex: 0x0B0709)),
            blobs: [
                .adaptive(light: Color(hex: 0xF5D2DE), dark: Color(hex: 0xC98BA1)),
                .adaptive(light: Color(hex: 0xF7DCD0), dark: Color(hex: 0xCC978A)),
                .adaptive(light: Color(hex: 0xE8D2EC), dark: Color(hex: 0xA98BB5)),
            ]
        ),
        BlobPalette(
            id: 5, name: "polvere",
            base: .adaptive(light: Color(hex: 0xEFF4FA), dark: Color(hex: 0x0A0F16)),
            baseEnd: .adaptive(light: Color(hex: 0xE6EDF6), dark: Color(hex: 0x05080B)),
            blobs: [
                .adaptive(light: Color(hex: 0xCCDDF2), dark: Color(hex: 0x7392BA)),
                .adaptive(light: Color(hex: 0xD3E6F2), dark: Color(hex: 0x7FA6BC)),
                .adaptive(light: Color(hex: 0xD8D8F0), dark: Color(hex: 0x8686BF)),
            ]
        ),
        BlobPalette(
            id: 6, name: "sabbia",
            base: .adaptive(light: Color(hex: 0xFBF5EC), dark: Color(hex: 0x14110A)),
            baseEnd: .adaptive(light: Color(hex: 0xF5EDE0), dark: Color(hex: 0x0A0805)),
            blobs: [
                .adaptive(light: Color(hex: 0xEFE0C4), dark: Color(hex: 0xC4B183)),
                .adaptive(light: Color(hex: 0xF2D9C2), dark: Color(hex: 0xC9A684)),
                .adaptive(light: Color(hex: 0xE3E0CC), dark: Color(hex: 0xB0AE8B)),
            ]
        ),
        BlobPalette(
            id: 7, name: "ghiaccio",
            base: .adaptive(light: Color(hex: 0xEDF5F8), dark: Color(hex: 0x0A1215)),
            baseEnd: .adaptive(light: Color(hex: 0xE3EFF4), dark: Color(hex: 0x05090B)),
            blobs: [
                .adaptive(light: Color(hex: 0xC6E4EC), dark: Color(hex: 0x74AEBC)),
                .adaptive(light: Color(hex: 0xD5E8F0), dark: Color(hex: 0x82B2C4)),
                .adaptive(light: Color(hex: 0xCFEDE4), dark: Color(hex: 0x7CBAAB)),
            ]
        ),
    ]
}

/// Gradiente organico sfocato generato da un seed: tre macchie di colore che
/// "respirano" molto lentamente (≤ 0.1 Hz) sopra un fondo scuro.
///
/// Lo stesso seed produce sempre lo stesso gradiente: è l'identità visiva di una scheda
/// in Home, in Schede e nella sessione attiva.
public struct BlobGradient: View {

    private let seed: Int
    private let intensity: Double
    private let animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - seed: intero che identifica la scheda; determina palette e fasi.
    ///   - intensity: opacità complessiva delle macchie (0...1).
    ///   - animated: se `false` il gradiente resta immobile (usare per liste lunghe).
    public init(seed: Int, intensity: Double = 1, animated: Bool = true) {
        self.seed = seed
        self.intensity = intensity
        self.animated = animated
    }

    /// Palette risolta dal seed, utile a chi deve scegliere il colore del testo sopra.
    public var palette: BlobPalette { BlobPalette.palette(for: seed) }

    public var body: some View {
        let palette = self.palette
        let phases = Self.phases(for: seed)
        let moving = animated && !reduceMotion

        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !moving)) { context in
                let time = moving ? context.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                    LinearGradient(
                        colors: [palette.base, palette.baseEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ForEach(Array(palette.blobs.enumerated()), id: \.offset) { index, color in
                        let phase = phases[index]
                        let angle = (time / Theme.Motion.breathPeriod) * 2 * .pi + phase.start
                        let diameter = side * phase.scale
                        Circle()
                            .fill(color)
                            .frame(width: diameter, height: diameter)
                            .offset(
                                x: geo.size.width * (phase.centerX - 0.5) + CGFloat(cos(angle)) * side * phase.travel,
                                y: geo.size.height * (phase.centerY - 0.5) + CGFloat(sin(angle * 0.7)) * side * phase.travel
                            )
                            .blur(radius: side * 0.22)
                            .opacity(0.78 * intensity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .compositingGroup()
            .clipped()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Generazione deterministica

    private struct Phase {
        let centerX: Double
        let centerY: Double
        let scale: Double
        let travel: Double
        let start: Double
    }

    /// Generatore lineare congruenziale deterministico: stesso seed → stesse macchie.
    private static func phases(for seed: Int) -> [Phase] {
        var state = UInt64(bitPattern: Int64(seed)) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 10_000) / 10_000
        }
        return (0..<3).map { index in
            Phase(
                centerX: 0.15 + next() * 0.7,
                centerY: 0.12 + next() * 0.76,
                scale: [0.95, 0.78, 0.62][index] + next() * 0.15,
                travel: 0.035 + next() * 0.045,
                start: next() * 2 * .pi
            )
        }
    }
}
