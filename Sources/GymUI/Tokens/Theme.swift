import SwiftUI

/// Un colore d'accento pastello e la sua variante profonda.
///
/// Regola d'uso (DESIGN.md → "Accenti pastello"):
/// - `fill` è il pastello pieno: si usa come **riempimento** (barre, celle, anelli,
///   sfondo di riga completata). È chiaro in entrambi i temi, quindi il contenuto
///   sopra è sempre scuro (`onFill`): **mai testo bianco su pastello**.
/// - `deep` è lo stesso tono, più profondo: linee sottili dei grafici, icone e
///   testo colorato. Ha contrasto AA sul fondo di pagina in entrambi i temi.
public struct AccentPalette: Sendable, Hashable {

    /// Pastello pieno, per i riempimenti.
    public let fill: Color
    /// Variante profonda, per tratti sottili, icone e testo.
    public let deep: Color

    /// Colore del contenuto sopra `fill`: sempre quasi nero.
    public var onFill: Color { Theme.onPastel }

    init(fill: Color, deep: Color) {
        self.fill = fill
        self.deep = deep
    }
}

/// Token del design system: colori semantici, raggi, spaziature, animazioni.
///
/// Regola: nessun colore letterale fuori da `Theme.swift` / `AdaptiveColor.swift`.
public enum Theme {

    // MARK: - Sfondo pagina

    /// Sfondo delle pagine: bianco puro in chiaro, nero puro in scuro. Piatto, senza gradiente.
    public static let background = Color.adaptive(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x000000))

    // MARK: - Superfici

    /// Riempimento delle card: grigio neutro chiarissimo. Niente ombra, niente bordo.
    public static let surface = Color.adaptive(light: Color(hex: 0xF5F5F7), dark: Color(hex: 0x1C1C1E))
    /// Elemento sopra una card: torna bianco in chiaro.
    public static let surfaceElevated = Color.adaptive(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x2C2C2E))
    /// Superficie sempre bianca: tile delle GIF/immagini esercizio, anche in dark (vedi DESIGN.md).
    public static let mediaTile = Color(hex: 0xFFFFFF)

    // MARK: - Testo

    public static let textPrimary = Color.adaptive(light: Color(hex: 0x1A1A1F), dark: Color(hex: 0xF5F5F7))
    public static let textSecondary = Color.adaptive(light: Color(hex: 0x6B6B73), dark: Color(hex: 0xA0A0A8))
    public static let textTertiary = Color.adaptive(light: Color(hex: 0x9A9AA2), dark: Color(hex: 0x6E6E76))

    // MARK: - Linee e accenti

    /// Linea hairline e riempimenti "vuoti" (track delle barre, celle spente).
    public static let separator = Color.adaptive(light: Color(hex: 0xE3E3E8), dark: Color(hex: 0x38383A))

    /// Quasi nero su chiaro, quasi bianco su scuro: bottoni primari e barre.
    public static let ink = Color.adaptive(light: Color(hex: 0x1A1A1F), dark: Color(hex: 0xF5F5F7))
    /// Contenuto sopra `ink`.
    public static let onInk = Color.adaptive(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x1A1A1F))

    /// Velo traslucido per chip e bottoni circolari appoggiati su un gradiente:
    /// schiarisce il fondo senza sfocarlo.
    ///
    /// Sostituisce `.ultraThinMaterial`: un materiale ricalcola il backdrop blur a
    /// ogni fotogramma (costo GPU alto, e su iPhone in chiaro rendeva grigio scuro),
    /// mentre questo è un semplice riempimento composito.
    public static let veil = Color.adaptive(
        light: Color(hex: 0xFFFFFF, opacity: 0.62),
        dark: Color(hex: 0xFFFFFF, opacity: 0.14)
    )

    /// Contenuto sopra un riempimento pastello: quasi nero in entrambi i temi,
    /// perché i pastello restano chiari anche in dark.
    public static let onPastel = Color(hex: 0x1A1A1F)

    /// Verde salvia/menta pastello: solo per gli stati "fatto / attivo".
    public static let accent = AccentPalette(
        fill: .adaptive(light: Color(hex: 0xBFE5CC), dark: Color(hex: 0xA6D9B8)),
        deep: .adaptive(light: Color(hex: 0x2F7D55), dark: Color(hex: 0x8ED6AC))
    )

    // MARK: - Palette metriche (pastello)

    /// Un colore per metrica (DESIGN.md → MacroFactor), tutti pastello.
    public enum Metric {
        /// Lilla: peso corporeo.
        public static let viola = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xD9D3F2), dark: Color(hex: 0xBFB6E8)),
            deep: .adaptive(light: Color(hex: 0x5B4FA8), dark: Color(hex: 0xB3A8F0))
        )
        /// Pesca: volume.
        public static let arancio = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xFBDCC2), dark: Color(hex: 0xEFC4A2)),
            deep: .adaptive(light: Color(hex: 0xA85A21), dark: Color(hex: 0xF0B183))
        )
        /// Menta: costanza.
        public static let verde = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xC6E8D5), dark: Color(hex: 0xA8D9BD)),
            deep: .adaptive(light: Color(hex: 0x2F7D55), dark: Color(hex: 0x8ED6AC))
        )
        /// Azzurro polvere: allenamenti.
        public static let blu = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xCCDDF2), dark: Color(hex: 0xADC8E8)),
            deep: .adaptive(light: Color(hex: 0x2F6698), dark: Color(hex: 0x9CC4EC))
        )
        /// Rosa cipria: record personali.
        public static let rosa = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xF5D3DE), dark: Color(hex: 0xE8BCCB)),
            deep: .adaptive(light: Color(hex: 0xA84A6B), dark: Color(hex: 0xEDA3BD))
        )

        /// Tutti i colori metrica, nell'ordine di documentazione.
        public static let all: [AccentPalette] = [viola, arancio, verde, blu, rosa]
    }

    // MARK: - Raggi

    public enum Radius {
        /// Thumbnail, celle piccole.
        public static let small: CGFloat = 12
        /// Tile media, chip alti, campi.
        public static let medium: CGFloat = 20
        /// Card standard.
        public static let card: CGFloat = 28
        /// Card enormi impilate (sessione, hero).
        public static let hero: CGFloat = 40
    }

    // MARK: - Spaziature (base 4)

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 28
        public static let xxxl: CGFloat = 40
        /// Margine orizzontale di pagina.
        public static let page: CGFloat = 20
    }

    // MARK: - Dimensioni ricorrenti

    public enum Size {
        /// Altezza dei bottoni primari a capsula.
        public static let primaryButtonHeight: CGFloat = 56
        /// Target di tap minimo (HIG).
        public static let minTapTarget: CGFloat = 44
        /// Altezza della hero card "Oggi".
        public static let heroCardHeight: CGFloat = 360
        /// Lato massimo consigliato per i media 180×180.
        public static let maxMediaSide: CGFloat = 240
        /// Spessore delle linee hairline.
        public static let hairline: CGFloat = 1
    }

    // MARK: - Movimento

    public enum Motion {
        /// Spring morbida standard del sistema: cambi di contenuto ampi, apparizioni.
        public static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
        /// Spring breve per selezioni e navigazione (tab, segmented, chip di filtro).
        ///
        /// La `spring` standard, su un cambio di tab, si *sente* lenta: mezzo secondo
        /// prima che la pillola arrivi. Qui la risposta è ~0.25 s, quasi critica
        /// (niente rimbalzo), così il tocco sembra immediato.
        public static let quick = Animation.spring(response: 0.25, dampingFraction: 0.9)
        /// Spring breve per micro-interazioni (check, chip).
        public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.72)
        /// Transizione di contenuto senza rimbalzo.
        public static let smooth = Animation.easeInOut(duration: 0.25)
        /// Respiro dei gradienti: ≤ 0.1 Hz.
        public static let breathPeriod: Double = 18
    }
}
