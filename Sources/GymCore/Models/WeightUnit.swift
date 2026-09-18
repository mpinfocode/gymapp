import Foundation

/// Unità di misura dei carichi. I pesi sono **sempre salvati in kg**:
/// questa enum serve solo alla presentazione e all'input.
public enum WeightUnit: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case kg
    case lb

    public var id: String { rawValue }

    /// Fattore di conversione esatto (definizione internazionale del pound).
    public static let kilogramsPerPound = 0.453_592_37

    /// Simbolo da mostrare (`"kg"` / `"lb"`).
    public var symbol: String { rawValue }

    /// Nome esteso in italiano.
    public var displayName: String {
        switch self {
        case .kg: "Chilogrammi"
        case .lb: "Libbre"
        }
    }

    /// Converte un valore in kg nel valore da mostrare in questa unità.
    public func value(fromKilograms kilograms: Double) -> Double {
        switch self {
        case .kg: kilograms
        case .lb: kilograms / WeightUnit.kilogramsPerPound
        }
    }

    /// Converte un valore inserito dall'utente in questa unità verso i kg da salvare.
    public func kilograms(from value: Double) -> Double {
        switch self {
        case .kg: value
        case .lb: value * WeightUnit.kilogramsPerPound
        }
    }

    /// Formatta un carico in kg nell'unità corrente **per la UI**, es. `"82,5 kg"`.
    ///
    /// Usa la virgola decimale italiana (``ItalianNumberFormat``) e non dipende dalla
    /// locale di sistema: il risultato è identico su iPhone, su macOS e negli screenshot.
    /// Le migliaia non vengono separate, così il testo resta usabile anche dove serve
    /// un numero singolo accanto a un campo di input.
    ///
    /// Per un numero "tecnico" con il punto decimale (log, confronti, testi non
    /// destinati all'utente) c'è ``trimmedNumber(_:fractionDigits:)``.
    ///
    /// - Parameters:
    ///   - kilograms: valore in kg.
    ///   - fractionDigits: cifre decimali massime (i decimali `,0` vengono omessi).
    ///   - includeSymbol: se includere il simbolo dell'unità.
    public func format(kilograms: Double, fractionDigits: Int = 1, includeSymbol: Bool = true) -> String {
        let converted = value(fromKilograms: kilograms)
        let text = ItalianNumberFormat.number(converted, fractionDigits: fractionDigits, grouping: false)
        return includeSymbol ? "\(text) \(symbol)" : text
    }

    /// Numero arrotondato con gli zeri decimali finali rimossi (`12.0` → `"12"`, `12.50` → `"12.5"`).
    ///
    /// Formato **tecnico**, con il punto decimale: stabile fra dispositivi e build,
    /// ma non adatto alla UI italiana (lì si usa ``ItalianNumberFormat``).
    public static func trimmedNumber(_ value: Double, fractionDigits: Int = 1) -> String {
        let digits = max(0, min(6, fractionDigits))
        var text = String(format: "%.\(digits)f", value)
        if digits > 0, text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        // Evita "-0"
        if text == "-0" { text = "0" }
        return text
    }
}
