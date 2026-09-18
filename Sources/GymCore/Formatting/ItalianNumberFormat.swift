import Foundation

/// Formattazione **italiana** dei numeri per i testi destinati alla UI.
///
/// Unico punto di verità per tutto quello che GymCore mostra a schermo, così le
/// schermate non devono più rattoppare le stringhe a valle:
/// - virgola decimale (`"82,5"`), mai il punto;
/// - migliaia separate dal punto (`"12.480"`);
/// - niente zeri decimali inutili (`12.0` → `"12"`, `12.50` → `"12,5"`);
/// - segno meno **ASCII** `"-"` attaccato al numero: mai `"—"` né `"–"`;
/// - percentuali attaccate al numero (`"16,4%"`, `"-1,2%"`).
///
/// Non dipende dalla locale di sistema: il risultato è identico su iPhone, su
/// macOS e negli screenshot di verifica.
///
/// > Importante: riguarda **solo la presentazione**. La serializzazione su file
/// > (backup compresi) resta quella di `Codable` e non passa mai di qui; per un
/// > numero "tecnico" stabile con il punto decimale c'è
/// > ``WeightUnit/trimmedNumber(_:fractionDigits:)``.
public enum ItalianNumberFormat {

    /// Separatore decimale italiano.
    public static let decimalSeparator = ","
    /// Separatore delle migliaia italiano.
    public static let groupingSeparator = "."
    /// Segno meno ASCII: l'unico ammesso nei testi dell'app.
    public static let minusSign = "-"

    /// Numero all'italiana: virgola decimale, migliaia col punto, zeri finali tolti.
    ///
    /// - Parameters:
    ///   - value: valore da formattare.
    ///   - fractionDigits: decimali massimi (0…6); quelli a zero vengono rimossi.
    ///   - grouping: se separare le migliaia con il punto.
    ///
    /// `-0` non esiste: un valore che arrotonda a zero è sempre `"0"`.
    public static func number(_ value: Double, fractionDigits: Int = 1, grouping: Bool = true) -> String {
        let digits = max(0, min(6, fractionDigits))
        guard value.isFinite else { return "0" }

        let scale = pow(10.0, Double(digits))
        let rounded = (value * scale).rounded() / scale
        let isNegative = rounded < 0

        let text = String(format: "%.\(digits)f", abs(rounded))
        var integerPart = text
        var fractionPart = ""
        if let dot = text.firstIndex(of: ".") {
            integerPart = String(text[text.startIndex..<dot])
            fractionPart = String(text[text.index(after: dot)...])
        }
        while fractionPart.hasSuffix("0") { fractionPart.removeLast() }
        if grouping { integerPart = group(integerPart) }

        let body = fractionPart.isEmpty ? integerPart : integerPart + decimalSeparator + fractionPart
        return isNegative ? minusSign + body : body
    }

    /// Numero senza decimali, con le migliaia separate (`"12.480"`).
    public static func integer(_ value: Double) -> String {
        number(value, fractionDigits: 0, grouping: true)
    }

    /// Numero senza decimali, con le migliaia separate (`"12.480"`).
    public static func integer(_ value: Int) -> String {
        number(Double(value), fractionDigits: 0, grouping: true)
    }

    /// Numero con il segno esplicito quando è positivo (`"+1,5"`, `"-1,2"`, `"0"`).
    public static func signed(_ value: Double, fractionDigits: Int = 1, grouping: Bool = true) -> String {
        let text = number(value, fractionDigits: fractionDigits, grouping: grouping)
        return text.hasPrefix(minusSign) || text == "0" ? text : "+" + text
    }

    /// Percentuale **attaccata** al numero (`"16,4%"`, `"-1,2%"`).
    public static func percent(_ value: Double, fractionDigits: Int = 1) -> String {
        number(value, fractionDigits: fractionDigits, grouping: false) + "%"
    }

    /// Percentuale attaccata e con segno esplicito (`"+16,4%"`, `"-1,2%"`).
    public static func signedPercent(_ value: Double, fractionDigits: Int = 1) -> String {
        signed(value, fractionDigits: fractionDigits, grouping: false) + "%"
    }

    /// Numero e unità di misura separati da uno spazio (`"82,5 kg"`), tranne la
    /// percentuale che si scrive sempre attaccata (`"16,4%"`).
    public static func measurement(
        _ value: Double,
        unit: String,
        fractionDigits: Int = 1,
        grouping: Bool = false
    ) -> String {
        let text = number(value, fractionDigits: fractionDigits, grouping: grouping)
        guard !unit.isEmpty else { return text }
        return unit == "%" ? text + unit : text + " " + unit
    }

    /// Converte in virgola i punti decimali di un testo già formattato.
    ///
    /// Utile solo per adattare stringhe prodotte altrove: se il numero è a
    /// disposizione conviene sempre passare da ``number(_:fractionDigits:grouping:)``,
    /// perché qui non si distingue il punto decimale da quello delle migliaia.
    public static func commaDecimals(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// Inserisce il separatore delle migliaia in una stringa di sole cifre.
    private static func group(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var remaining = digits
        var groups: [String] = []
        while remaining.count > 3 {
            groups.insert(String(remaining.suffix(3)), at: 0)
            remaining.removeLast(3)
        }
        groups.insert(remaining, at: 0)
        return groups.joined(separator: groupingSeparator)
    }
}
