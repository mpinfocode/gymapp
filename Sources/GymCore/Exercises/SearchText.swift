import Foundation

/// Normalizzazione del testo per la ricerca: minuscole, senza diacritici,
/// punteggiatura ridotta a spazi singoli.
///
/// `"Pull-Up (wide grip)"` → `"pull up wide grip"`,
/// `"Flessori dell'anca"` → `"flessori dell anca"`.
public enum SearchText {

    /// Forma normalizzata di una stringa, usata sia per indicizzare sia per interrogare.
    public static func normalize(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var output = ""
        output.reserveCapacity(folded.unicodeScalars.count)
        var pendingSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !output.isEmpty { output.append(" ") }
                pendingSeparator = false
                output.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return output
    }

    /// Token normalizzati di una query (stringhe non vuote separate da spazi).
    public static func tokens(_ input: String) -> [String] {
        normalize(input).split(separator: " ").map(String.init)
    }

    /// Ricerca di sottostringa su testo già normalizzato (confronto letterale, veloce).
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return haystack.range(of: needle, options: [.literal]) != nil
    }
}
