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
            base: .adaptive(light: Color(hex: 0xFDF2EA), dark: Color(hex: 0x100F0E)),
            baseEnd: .adaptive(light: Color(hex: 0xFBE8DC), dark: Color(hex: 0x0A0806)),
            blobs: [
                .adaptive(light: Color(hex: 0xFBD9BF), dark: Color(hex: 0xF0B78A)),
                .adaptive(light: Color(hex: 0xF7C7C3), dark: Color(hex: 0xEDA79E)),
                .adaptive(light: Color(hex: 0xFBE7C0), dark: Color(hex: 0xEFD199)),
            ]
        ),
        BlobPalette(
            id: 1, name: "menta",
            base: .adaptive(light: Color(hex: 0xEDF8F2), dark: Color(hex: 0x0A1410)),
            baseEnd: .adaptive(light: Color(hex: 0xE2F2EC), dark: Color(hex: 0x050A08)),
            blobs: [
                .adaptive(light: Color(hex: 0xC2E8D2), dark: Color(hex: 0xA5D2BC)),
                .adaptive(light: Color(hex: 0xBFE3E8), dark: Color(hex: 0x9DC7CD)),
                .adaptive(light: Color(hex: 0xDDF0D8), dark: Color(hex: 0xB8D5AF)),
            ]
        ),
        BlobPalette(
            id: 2, name: "lilla",
            base: .adaptive(light: Color(hex: 0xF3F0FB), dark: Color(hex: 0x100E18)),
            baseEnd: .adaptive(light: Color(hex: 0xECE8F7), dark: Color(hex: 0x08070E)),
            blobs: [
                .adaptive(light: Color(hex: 0xD8D2F2), dark: Color(hex: 0xC2BCE0)),
                .adaptive(light: Color(hex: 0xE3D2F0), dark: Color(hex: 0xC2B2D8)),
                .adaptive(light: Color(hex: 0xCBD5F5), dark: Color(hex: 0xC0C6E5)),
            ]
        ),
        BlobPalette(
            id: 3, name: "salvia",
            base: .adaptive(light: Color(hex: 0xF0F5EE), dark: Color(hex: 0x0C120C)),
            baseEnd: .adaptive(light: Color(hex: 0xE7EFE4), dark: Color(hex: 0x060906)),
            blobs: [
                .adaptive(light: Color(hex: 0xCFE3C8), dark: Color(hex: 0xB6CCB0)),
                .adaptive(light: Color(hex: 0xDDEBCE), dark: Color(hex: 0xB1C69F)),
                .adaptive(light: Color(hex: 0xBFDDCB), dark: Color(hex: 0xB6D2C4)),
            ]
        ),
        BlobPalette(
            id: 4, name: "cipria",
            base: .adaptive(light: Color(hex: 0xFCF0F4), dark: Color(hex: 0x160F12)),
            baseEnd: .adaptive(light: Color(hex: 0xF7E8EE), dark: Color(hex: 0x0B0709)),
            blobs: [
                .adaptive(light: Color(hex: 0xF5D2DE), dark: Color(hex: 0xDCB4C3)),
                .adaptive(light: Color(hex: 0xF7DCD0), dark: Color(hex: 0xD8B0A6)),
                .adaptive(light: Color(hex: 0xE8D2EC), dark: Color(hex: 0xD1C1D7)),
            ]
        ),
        BlobPalette(
            id: 5, name: "polvere",
            base: .adaptive(light: Color(hex: 0xEFF4FA), dark: Color(hex: 0x0A0F16)),
            baseEnd: .adaptive(light: Color(hex: 0xE6EDF6), dark: Color(hex: 0x05080B)),
            blobs: [
                .adaptive(light: Color(hex: 0xCCDDF2), dark: Color(hex: 0xB4C5DA)),
                .adaptive(light: Color(hex: 0xD3E6F2), dark: Color(hex: 0xA6C1D1)),
                .adaptive(light: Color(hex: 0xD8D8F0), dark: Color(hex: 0xC5C5E0)),
            ]
        ),
        BlobPalette(
            id: 6, name: "sabbia",
            base: .adaptive(light: Color(hex: 0xFBF5EC), dark: Color(hex: 0x101010)),
            baseEnd: .adaptive(light: Color(hex: 0xF5EDE0), dark: Color(hex: 0x0A0805)),
            blobs: [
                .adaptive(light: Color(hex: 0xEFE0C4), dark: Color(hex: 0xE4CB93)),
                .adaptive(light: Color(hex: 0xF2D9C2), dark: Color(hex: 0xE6B893)),
                .adaptive(light: Color(hex: 0xE3E0CC), dark: Color(hex: 0xCBC9A2)),
            ]
        ),
        BlobPalette(
            id: 7, name: "ghiaccio",
            base: .adaptive(light: Color(hex: 0xEDF5F8), dark: Color(hex: 0x0A1215)),
            baseEnd: .adaptive(light: Color(hex: 0xE3EFF4), dark: Color(hex: 0x05090B)),
            blobs: [
                .adaptive(light: Color(hex: 0xC6E4EC), dark: Color(hex: 0xA7CCD5)),
                .adaptive(light: Color(hex: 0xD5E8F0), dark: Color(hex: 0xA0C4D2)),
                .adaptive(light: Color(hex: 0xCFEDE4), dark: Color(hex: 0xAED4CB)),
            ]
        ),
    ]
}

/// Gradiente organico generato da un seed: tre macchie di colore morbide che
/// "respirano" molto lentamente (≤ 0.1 Hz) sopra un fondo tinto.
///
/// Lo stesso seed produce sempre lo stesso gradiente: è l'identità visiva di una scheda
/// in Home, in Schede e nella sessione attiva.
///
/// ## Costo
/// Le macchie sono `RadialGradient` che sfumano fino a trasparente: la morbidezza è
/// nel gradiente stesso, **senza `.blur`** e senza `TimelineView`. Il respiro è una
/// sola animazione implicita `repeatForever` su `offset`/`scaleEffect`, quindi la
/// interpola Core Animation: il `body` non viene rivalutato a ogni fotogramma.
/// L'animazione si ferma davvero quando la view scompare, quando la scena va in
/// background, con "Riduci movimento" e quando l'ambiente la mette in pausa
/// (``SwiftUI/View/blobAnimationPaused(_:)``: la shell la usa per i tab nascosti,
/// che in SwiftUI restano montati).
public struct BlobGradient: View {

    private let seed: Int
    private let intensity: Double
    private let animated: Bool
    private let clipsToBounds: Bool

    @State private var isOnScreen = false
    @State private var breathing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.blobAnimationPaused) private var pausedByEnvironment
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - seed: intero che identifica la scheda; determina palette e fasi.
    ///   - intensity: opacità complessiva delle macchie (0...1).
    ///   - animated: se `false` il gradiente resta immobile (usare per liste lunghe).
    ///   - clipsToBounds: ritaglia le macchie al proprio riquadro. Passare `false`
    ///     quando il chiamante ritaglia già (``HeroCard``): due ritagli annidati su
    ///     contenuto animato sono due passaggi fuori schermo per fotogramma.
    public init(seed: Int, intensity: Double = 1, animated: Bool = true, clipsToBounds: Bool = true) {
        self.seed = seed
        self.intensity = intensity
        self.animated = animated
        self.clipsToBounds = clipsToBounds
    }

    /// Palette risolta dal seed, utile a chi deve scegliere il colore del testo sopra.
    public var palette: BlobPalette { BlobPalette.palette(for: seed) }

    /// Il respiro è attivo solo se serve davvero: view sullo schermo, scena in primo
    /// piano, nessuna pausa dall'ambiente, nessun "Riduci movimento".
    private var moving: Bool {
        animated
            && !reduceMotion
            && !pausedByEnvironment
            && isOnScreen
            && scenePhase != .background
    }

    public var body: some View {
        let palette = self.palette
        let phases = Self.phases(for: seed)

        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height, 1)
            ZStack {
                LinearGradient(
                    colors: [palette.base, palette.baseEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                ForEach(Array(palette.blobs.enumerated()), id: \.offset) { index, color in
                    blob(color, phase: phases[index], side: side, size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .modifier(OptionalClip(isActive: clipsToBounds))
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: moving, initial: true) { _, isMoving in
            breathing = isMoving
        }
        .accessibilityHidden(true)
    }

    /// Una macchia: cerchio riempito da un gradiente radiale che sfuma a trasparente.
    /// Si muove di pochi punti su una diagonale e respira di scala: entrambe le
    /// proprietà sono trasformazioni di layer, non ridisegni.
    @ViewBuilder
    private func blob(_ color: Color, phase: Phase, side: CGFloat, size: CGSize) -> some View {
        // La tinta è piena fino a ~0.62 del raggio e poi sfuma a trasparente: il
        // diametro è tarato (a occhio, confrontando gli snapshot) perché la macchia
        // copra la stessa area del vecchio cerchio pieno + `.blur(side * 0.22)`.
        let diameter = side * phase.scale * 0.94
        let restX = size.width * (phase.centerX - 0.5)
        let restY = size.height * (phase.centerY - 0.5)
        let travel = side * phase.travel

        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: Self.softStops(color, intensity: intensity)),
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(breathing ? 1.06 : 0.97)
            .offset(
                x: restX + (breathing ? travel : -travel) * phase.driftX,
                y: restY + (breathing ? -travel : travel) * phase.driftY
            )
            .animation(breathAnimation(phase: phase), value: breathing)
    }

    /// Respiro lentissimo e sfasato per macchia, così le tre non si muovono all'unisono.
    private func breathAnimation(phase: Phase) -> Animation? {
        guard moving else { return nil }
        return .easeInOut(duration: Theme.Motion.breathPeriod * phase.durationFactor)
            .repeatForever(autoreverses: true)
            .delay(Theme.Motion.breathPeriod * phase.delayFactor)
    }

    /// Stop scelti per imitare la caduta morbida di una sfocatura gaussiana:
    /// pieno al centro, quasi metà a mezza via, nullo sul bordo. Niente banding
    /// perché la transizione non ha mai un salto secco.
    private static func softStops(_ color: Color, intensity: Double) -> [Gradient.Stop] {
        let peak = 0.86 * max(min(intensity, 1), 0)
        return [
            Gradient.Stop(color: color.opacity(peak), location: 0),
            Gradient.Stop(color: color.opacity(peak * 0.99), location: 0.62),
            Gradient.Stop(color: color.opacity(peak * 0.86), location: 0.73),
            Gradient.Stop(color: color.opacity(peak * 0.56), location: 0.83),
            Gradient.Stop(color: color.opacity(peak * 0.26), location: 0.91),
            Gradient.Stop(color: color.opacity(peak * 0.07), location: 0.97),
            Gradient.Stop(color: color.opacity(0), location: 1),
        ]
    }

    // MARK: - Generazione deterministica

    private struct Phase {
        let centerX: Double
        let centerY: Double
        let scale: Double
        let travel: Double
        let driftX: Double
        let driftY: Double
        let durationFactor: Double
        let delayFactor: Double
    }

    /// Generatore lineare congruenziale deterministico: stesso seed → stesse macchie.
    private static func phases(for seed: Int) -> [Phase] {
        var state = UInt64(bitPattern: Int64(seed)) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 10_000) / 10_000
        }
        return (0..<3).map { index in
            let centerX = 0.15 + next() * 0.7
            let centerY = 0.12 + next() * 0.76
            let scale = [0.95, 0.78, 0.62][index] + next() * 0.15
            let travel = 0.035 + next() * 0.045
            let angle = next() * 2 * .pi
            return Phase(
                centerX: centerX,
                centerY: centerY,
                scale: scale,
                travel: travel,
                driftX: cos(angle),
                driftY: sin(angle),
                durationFactor: 0.8 + Double(index) * 0.25,
                delayFactor: Double(index) * 0.17
            )
        }
    }
}

/// Ritaglio opzionale: evita il `.clipped()` quando a ritagliare è già il chiamante.
private struct OptionalClip: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.clipped()
        } else {
            content
        }
    }
}

// MARK: - Pausa dall'esterno

private struct BlobAnimationPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {

    /// Quando è `true`, le animazioni ambientali di GymUI (il respiro di
    /// ``BlobGradient`` e le GIF di ``AnimatedGIFView``) restano ferme.
    public var blobAnimationPaused: Bool {
        get { self[BlobAnimationPausedKey.self] }
        set { self[BlobAnimationPausedKey.self] = newValue }
    }
}

extension View {

    /// Mette in pausa le animazioni ambientali di GymUI in questo sottoalbero.
    ///
    /// Serve alla shell: i tab non selezionati restano montati (sono nascosti con
    /// `opacity(0)`), quindi `onDisappear` non scatta e i gradienti continuerebbero
    /// a respirare fuori dallo schermo. La shell applica
    /// `.blobAnimationPaused(tab != router.tab)` a ogni tab.
    public func blobAnimationPaused(_ paused: Bool = true) -> some View {
        environment(\.blobAnimationPaused, paused)
    }
}
