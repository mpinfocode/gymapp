import SwiftUI

// Aggiunta **additiva** ai token: una tavolozza pastello più ampia di quella delle
// metriche, per le barre a segmenti in cui convivono molte categorie (la ripartizione
// dei muscoli colpiti da una scheda ne ha fino a 13).
//
// Perché non bastavano i token esistenti: fra `Theme.accent` e `Theme.Metric.*` i
// toni davvero distinti sono cinque, e `accent` coincide di fatto con `Metric.verde`.
// Derivare i mancanti abbassando l'opacità avrebbe prodotto segmenti slavati e
// indistinguibili fra loro proprio dove l'unica cosa che conta è distinguerli.
//
// GymUI non conosce `MuscleGroup` (non dipende da GymCore): qui c'è solo una
// sequenza **ordinata e stabile** di tinte; l'abbinamento tinta → zona del corpo
// lo decide la feature.

extension Theme {

    /// Tavolozza pastello estesa per le ripartizioni a più categorie.
    ///
    /// Tutti i toni rispettano la regola dei pastello (DESIGN.md): `fill` chiaro in
    /// entrambi i temi, contenuto sopra sempre `onFill`; `deep` leggibile come testo
    /// o pallino su fondo pagina.
    public enum MuscleGroupPalette {

        // I cinque toni già in uso altrove, ripresi tali e quali.

        /// Azzurro polvere.
        public static let azzurro = Theme.Metric.blu
        /// Pesca.
        public static let pesca = Theme.Metric.arancio
        /// Lilla.
        public static let lilla = Theme.Metric.viola
        /// Menta.
        public static let menta = Theme.Metric.verde
        /// Rosa cipria.
        public static let rosa = Theme.Metric.rosa

        // Toni aggiuntivi, scelti per stare lontani fra loro sulla ruota dei colori.

        /// Burro: giallo pastello caldo.
        public static let burro = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xF2E3AE), dark: Color(hex: 0xDFCE95)),
            deep: .adaptive(light: Color(hex: 0x7D6408), dark: Color(hex: 0xE3CC7E))
        )
        /// Terracotta: arancio bruciato tenue.
        public static let terracotta = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xF2C9BA), dark: Color(hex: 0xDCAE9D)),
            deep: .adaptive(light: Color(hex: 0x9C4526), dark: Color(hex: 0xEFA184))
        )
        /// Indaco: blu profondo in versione pastello.
        public static let indaco = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xC5CAF0), dark: Color(hex: 0xABB1E0)),
            deep: .adaptive(light: Color(hex: 0x3B47A3), dark: Color(hex: 0xA6AEF2))
        )
        /// Oliva: verde caldo, chiaramente diverso dalla menta.
        public static let oliva = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xD2E0A0), dark: Color(hex: 0xB8C888)),
            deep: .adaptive(light: Color(hex: 0x566A1A), dark: Color(hex: 0xC0D183))
        )
        /// Malva: prugna chiara.
        public static let malva = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xE7C9E2), dark: Color(hex: 0xCEADC9)),
            deep: .adaptive(light: Color(hex: 0x7A3872), dark: Color(hex: 0xDDA2D5))
        )
        /// Turchese: verde-azzurro freddo.
        public static let turchese = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xB9E2E4), dark: Color(hex: 0x9CCBCE)),
            deep: .adaptive(light: Color(hex: 0x186B72), dark: Color(hex: 0x86D0D6))
        )
        /// Sabbia: beige neutro caldo.
        public static let sabbia = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xE8DAC4), dark: Color(hex: 0xD0C0A7)),
            deep: .adaptive(light: Color(hex: 0x6B573A), dark: Color(hex: 0xD6C2A2))
        )
        /// Ardesia: grigio-azzurro spento, per i residui ("Altro").
        public static let ardesia = AccentPalette(
            fill: .adaptive(light: Color(hex: 0xD6DCE3), dark: Color(hex: 0xB6BEC7)),
            deep: .adaptive(light: Color(hex: 0x4A5763), dark: Color(hex: 0xB2BECA))
        )

        /// Tutti i toni in ordine stabile: chi ne usa solo alcuni prenda i primi.
        public static let all: [AccentPalette] = [
            azzurro, pesca, lilla, menta, rosa,
            burro, terracotta, indaco, oliva, malva,
            turchese, sabbia, ardesia,
        ]
    }
}
