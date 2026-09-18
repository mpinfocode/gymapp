import Foundation

/// Normalizzazione del testo per la ricerca: minuscole, senza diacritici,
/// punteggiatura ridotta a spazi singoli.
///
/// `"Pull-Up (wide grip)"` → `"pull up wide grip"`,
/// `"Flessori dell'anca"` → `"flessori dell anca"`.
///
/// ## Prestazioni
/// La normalizzazione è la prima cosa che gira all'avvio (1.324 nomi da
/// indicizzare) e a ogni tasto digitato. Il percorso normale è quindi un
/// **fast-path ASCII** che lavora sui byte UTF-8 senza `folding(options:)` né
/// `CharacterSet`: i nomi del dataset sono tutti ASCII. Le stringhe con almeno un
/// byte non ASCII (query italiane accentate, note dell'utente) ricadono sul
/// percorso completo, che resta la definizione di riferimento.
public enum SearchText {

    /// `CharacterSet.alphanumerics` è un valore ponte con Foundation: risolverlo a
    /// ogni scalare costa, quindi lo si tiene qui una volta sola.
    private static let alphanumerics = CharacterSet.alphanumerics

    /// Forma normalizzata di una stringa, usata sia per indicizzare sia per interrogare.
    public static func normalize(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        if let ascii = normalizeASCII(input) { return ascii }
        return normalizeUnicode(input)
    }

    /// Fast-path: se la stringa è interamente ASCII la normalizzazione si riduce a
    /// "minuscolo + tieni solo `[0-9a-z]` + separatori collassati in uno spazio".
    ///
    /// Su input ASCII è **identico** a ``normalizeUnicode(_:)``: il folding
    /// diacritico e quello di larghezza non toccano l'ASCII, quello di maiuscole
    /// coincide con `+32` su `A…Z`, e `CharacterSet.alphanumerics` sull'ASCII è
    /// esattamente `[0-9A-Za-z]` (invarianza verificata in GymChecks).
    ///
    /// - Returns: `nil` se la stringa contiene almeno un byte non ASCII.
    private static func normalizeASCII(_ input: String) -> String? {
        let utf8 = input.utf8
        var bytes: [UInt8] = []
        bytes.reserveCapacity(utf8.count)
        var pendingSeparator = false
        for byte in utf8 {
            if byte >= 0x80 { return nil }
            let isDigit = byte >= 0x30 && byte <= 0x39
            let isUpper = byte >= 0x41 && byte <= 0x5A
            let isLower = byte >= 0x61 && byte <= 0x7A
            if isDigit || isLower || isUpper {
                if pendingSeparator, !bytes.isEmpty { bytes.append(0x20) }
                pendingSeparator = false
                bytes.append(isUpper ? byte &+ 32 : byte)
            } else {
                pendingSeparator = true
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Percorso completo (definizione di riferimento), per le stringhe non ASCII.
    private static func normalizeUnicode(_ input: String) -> String {
        let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var output = ""
        output.reserveCapacity(folded.unicodeScalars.count)
        var pendingSeparator = false
        for scalar in folded.unicodeScalars {
            if alphanumerics.contains(scalar) {
                if pendingSeparator, !output.isEmpty { output.append(" ") }
                pendingSeparator = false
                output.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return output
    }

    /// Normalizzazione senza fast-path: serve ai check per verificare che il
    /// percorso ASCII dia esattamente lo stesso risultato.
    public static func normalizeReference(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        return normalizeUnicode(input)
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
