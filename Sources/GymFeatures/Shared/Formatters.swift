import Foundation
import GymCore

/// Formattatori condivisi dalle schermate: funzioni pure, italiane, senza locale
/// di sistema (così il risultato è identico su iPhone, su macOS e negli screenshot).
///
/// Regole di design rispettate qui e da rispettare altrove:
/// - virgola decimale italiana ("82,5 kg");
/// - separatore delle migliaia "." ("12.480 kg");
/// - mai "—" né "–": un valore mancante è "·" (``Formatters/missing``).
public enum Formatters {

    /// Segnaposto per un valore mancante. Mai "—".
    public static let missing = "·"

    // MARK: - Pesi e volumi

    /// Carico nell'unità scelta dall'utente, con la virgola decimale ("82,5 kg").
    ///
    /// - Parameters:
    ///   - kilograms: valore salvato, sempre in kg.
    ///   - unit: unità di presentazione.
    ///   - includeSymbol: se includere "kg" / "lb".
    public static func weight(_ kilograms: Double, unit: WeightUnit, includeSymbol: Bool = true) -> String {
        italianDecimals(unit.format(kilograms: kilograms, fractionDigits: 1, includeSymbol: includeSymbol))
    }

    /// Carico opzionale: `nil` diventa ``missing``.
    public static func weight(_ kilograms: Double?, unit: WeightUnit, includeSymbol: Bool = true) -> String {
        guard let kilograms else { return missing }
        return weight(kilograms, unit: unit, includeSymbol: includeSymbol)
    }

    /// Volume arrotondato con separatore delle migliaia ("12.480 kg").
    public static func volume(_ kilograms: Double, unit: WeightUnit, includeSymbol: Bool = true) -> String {
        let converted = unit.value(fromKilograms: kilograms)
        let text = groupedInteger(converted.rounded())
        return includeSymbol ? "\(text) \(unit.symbol)" : text
    }

    /// Intero con separatore delle migliaia all'italiana ("12.480", "980").
    public static func groupedInteger(_ value: Double) -> String {
        let negative = value < 0
        var digits = String(Int(abs(value).rounded()))
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        groups.insert(digits, at: 0)
        return (negative ? "-" : "") + groups.joined(separator: ".")
    }

    // MARK: - Durate

    /// Cronometro `mm:ss` (oltre l'ora `h:mm:ss`): per il timer di sessione e di recupero.
    public static func clock(seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h):" + String(format: "%02d:%02d", m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// Cronometro da un intervallo (durata di una sessione in corso).
    public static func clock(_ interval: TimeInterval) -> String {
        clock(seconds: Int(interval.rounded()))
    }

    /// Durata discorsiva e corta: "45 min", "1 h 05 min", "< 1 min".
    public static func minutes(_ interval: TimeInterval) -> String {
        minutes(seconds: Int(interval.rounded()))
    }

    /// Durata discorsiva e corta a partire dai secondi.
    public static func minutes(seconds: Int) -> String {
        let total = max(0, seconds)
        guard total >= 60 else { return "< 1 min" }
        let m = total / 60
        guard m >= 60 else { return "\(m) min" }
        return "\(m / 60) h " + String(format: "%02d", m % 60) + " min"
    }

    // MARK: - Date

    /// Abbreviazioni dei mesi in italiano, da gennaio a dicembre.
    public static let monthAbbreviations = [
        "gen", "feb", "mar", "apr", "mag", "giu",
        "lug", "ago", "set", "ott", "nov", "dic",
    ]

    /// Data relativa e breve: "oggi", "ieri", altrimenti "lun 14 set".
    public static func relativeDay(
        _ date: Date,
        now: Date,
        calendar: Calendar = Stats.weekCalendar()
    ) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let distance = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch distance {
        case 0: return "oggi"
        case 1: return "ieri"
        default: return shortDate(date, calendar: calendar)
        }
    }

    /// Data breve con il giorno della settimana: "lun 14 set".
    public static func shortDate(_ date: Date, calendar: Calendar = Stats.weekCalendar()) -> String {
        let weekday = Weekday.from(date: date, calendar: calendar).shortName.lowercased()
        return "\(weekday) \(dayAndMonth(date, calendar: calendar))"
    }

    /// Giorno e mese senza giorno della settimana: "14 set".
    public static func dayAndMonth(_ date: Date, calendar: Calendar = Stats.weekCalendar()) -> String {
        let components = calendar.dateComponents([.day, .month], from: date)
        let day = components.day ?? 1
        let month = components.month ?? 1
        let name = monthAbbreviations.indices.contains(month - 1) ? monthAbbreviations[month - 1] : ""
        return "\(day) \(name)"
    }

    /// Overline maiuscola dell'header di Progressi: "GIOVEDÌ 18 SETTEMBRE".
    ///
    /// Il maiuscolo lo applica qui, non con `.textCase`, perché serve anche a VoiceOver.
    public static func longDateUppercased(_ date: Date, calendar: Calendar = Stats.weekCalendar()) -> String {
        let weekday = Weekday.from(date: date, calendar: calendar).italianName
        let components = calendar.dateComponents([.day, .month], from: date)
        let day = components.day ?? 1
        let month = components.month ?? 1
        let name = Formatters.months.indices.contains(month - 1) ? Formatters.months[month - 1] : ""
        return "\(weekday) \(day) \(name)".uppercased()
    }

    /// Nomi estesi dei mesi in italiano, minuscoli.
    public static let months = [
        "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
        "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre",
    ]

    // MARK: - Numeri

    /// Sostituisce il punto decimale con la virgola italiana.
    ///
    /// ``WeightUnit/format(kilograms:fractionDigits:includeSymbol:)`` produce sempre
    /// il punto per restare stabile fra dispositivi e backup: la conversione alla
    /// virgola è quindi una scelta di sola presentazione e vive solo qui.
    public static func italianDecimals(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: ",")
    }

    /// Numero con al più una cifra decimale, virgola italiana ("12,5", "8").
    public static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        italianDecimals(WeightUnit.trimmedNumber(value, fractionDigits: fractionDigits))
    }
}
