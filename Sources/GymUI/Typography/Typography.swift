import SwiftUI

// Un solo font in tutta l'app: SF Pro di sistema (`.system`, design `.default`).
// Vietati serif, rounded, monospaced e larghezze alternative; vietata la spaziatura
// fra lettere. La gerarchia nasce solo da dimensione, peso, colore e maiuscole.
//
// Tutti gli stili scalano con Dynamic Type: o tramite un text style di sistema,
// o tramite `@ScaledMetric` dove la dimensione richiesta non coincide con nessun
// text style (titolo di pagina 30, numero gigante 64).

extension Font {

    /// Saluto grande: 34 semibold ("Buongiorno, Francesco").
    public static let greeting: Font = .system(.largeTitle, weight: .semibold)

    /// Titolo di sezione: 22 semibold ("Oggi", "Questa settimana").
    public static let sectionTitle: Font = .system(.title2, weight: .semibold)

    /// Etichetta piccola maiuscola: 12 semibold ("VENERDÌ 18 SETTEMBRE").
    /// Il maiuscolo e il colore secondario li applica `View.overlineStyle(color:)`.
    public static let overline: Font = .system(.caption, weight: .semibold)

    /// Momenti guida grandi, leggeri e minuscoli: 28 light ("pronto per iniziare?").
    public static let whisper: Font = .system(.title, weight: .light)

    /// Numero grande con cifre tabellari: 28 medium.
    public static let bigNumber: Font = .system(.title, weight: .medium).monospacedDigit()

    /// Corpo del testo.
    public static let bodyText: Font = .system(.body, weight: .regular)

    /// Corpo enfatizzato (titoli di riga).
    public static let bodyEmphasis: Font = .system(.body, weight: .semibold)

    /// Didascalia grigia.
    public static let captionText: Font = .system(.footnote, weight: .regular)

    /// Valore numerico di una cella serie.
    public static let cellNumber: Font = .system(.body, weight: .semibold).monospacedDigit()
}

// MARK: - Stili con dimensione fuori scala di sistema

/// Titolo di pagina: 30 heavy maiuscolo (dashboard Progressi, riepilogo sessione).
private struct PageTitleStyle: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 30

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(Theme.textPrimary)
    }
}

/// Numero gigante: 64 medium con cifre tabellari (hero completata, riepilogo).
private struct HugeNumberStyle: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .medium).monospacedDigit())
            .foregroundStyle(color)
    }
}

// MARK: - Modificatori

extension View {

    /// Saluto 34 semibold, colore primario.
    public func greetingStyle() -> some View {
        font(.greeting).foregroundStyle(Theme.textPrimary)
    }

    /// Titolo di sezione 22 semibold.
    public func sectionTitleStyle() -> some View {
        font(.sectionTitle).foregroundStyle(Theme.textPrimary)
    }

    /// Titolo di pagina 30 heavy, sempre maiuscolo.
    public func pageTitleStyle() -> some View {
        modifier(PageTitleStyle())
    }

    /// Numero gigante 64 medium, cifre tabellari.
    public func hugeNumberStyle(color: Color = Theme.textPrimary) -> some View {
        modifier(HugeNumberStyle(color: color))
    }

    /// Overline: 12 semibold, maiuscolo, colore secondario. Nessuna spaziatura fra lettere.
    public func overlineStyle(color: Color = Theme.textSecondary) -> some View {
        font(.overline)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Whisper: 28 light, tutto minuscolo.
    public func whisperStyle(color: Color = Theme.textPrimary) -> some View {
        font(.whisper)
            .textCase(.lowercase)
            .foregroundStyle(color)
    }

    /// Numero grande 28 medium con cifre tabellari.
    public func bigNumberStyle(color: Color = Theme.textPrimary) -> some View {
        font(.bigNumber).foregroundStyle(color)
    }

    /// Didascalia grigia.
    public func captionStyle(color: Color = Theme.textSecondary) -> some View {
        font(.captionText).foregroundStyle(color)
    }
}
