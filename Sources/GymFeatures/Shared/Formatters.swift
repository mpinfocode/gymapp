import Foundation
import GymCore

/// Formattatori condivisi dalle schermate: un **sottile strato** sopra
/// ``ItalianNumberFormat`` e le API di presentazione di GymCore.
///
/// Qui non si formatta più niente a mano e non si rattoppano stringhe già
/// prodotte altrove: la regola italiana (virgola decimale, migliaia col punto,
/// meno ASCII) vive in GymCore, questo tipo si limita a scegliere l'arrotondamento
/// e il simbolo giusti per ogni posto della UI. Il risultato non dipende dalla
/// locale di sistema: identico su iPhone, su macOS e negli screenshot.
///
/// Regole di design rispettate qui e da rispettare altrove:
/// - virgola decimale italiana ("82,5 kg");
/// - separatore delle migliaia "." solo dove il numero è "da leggere" ("12.480 kg"),
///   mai accanto a un campo di input;
/// - mai "—" né "–": un valore mancante è "·" (``Formatters/missing``).
public enum Formatters {

    /// Segnaposto per un valore mancante. Mai "—".
    public static let missing = "·"

    // MARK: - Pesi e volumi

    /// Carico nell'unità scelta dall'utente, con la virgola decimale ("82,5 kg").
    ///
    /// Senza separatore delle migliaia: questo numero sta spesso accanto a un
    /// campo di input, dove il punto confonderebbe.
    ///
    /// - Parameters:
    ///   - kilograms: valore salvato, sempre in kg.
    ///   - unit: unità di presentazione.
    ///   - includeSymbol: se includere "kg" / "lb".
    public static func weight(_ kilograms: Double, unit: WeightUnit, includeSymbol: Bool = true) -> String {
        unit.format(kilograms: kilograms, fractionDigits: 1, includeSymbol: includeSymbol)
    }

    /// Carico opzionale: `nil` diventa ``missing``.
    public static func weight(_ kilograms: Double?, unit: WeightUnit, includeSymbol: Bool = true) -> String {
        guard let kilograms else { return missing }
        return weight(kilograms, unit: unit, includeSymbol: includeSymbol)
    }

    /// Volume arrotondato con separatore delle migliaia ("12.480 kg").
    ///
    /// Diverso da ``GymCore/Stats/formatVolume(_:unit:)``, che abbrevia oltre le
    /// 10 t ("12,4k kg"): nelle schermate il numero per esteso resta leggibile e
    /// più onesto.
    public static func volume(_ kilograms: Double, unit: WeightUnit, includeSymbol: Bool = true) -> String {
        let text = ItalianNumberFormat.integer(unit.value(fromKilograms: kilograms))
        return includeSymbol ? "\(text) \(unit.symbol)" : text
    }

    // MARK: - Numeri

    /// Intero con separatore delle migliaia all'italiana ("12.480", "980").
    public static func groupedInteger(_ value: Double) -> String {
        ItalianNumberFormat.integer(value)
    }

    /// Conteggio con separatore delle migliaia ("1.324 esercizi").
    public static func integer(_ value: Int) -> String {
        ItalianNumberFormat.integer(value)
    }

    /// Numero con al più una cifra decimale, virgola italiana ("12,5", "8").
    ///
    /// Senza separatore delle migliaia: è il formato dei valori "singoli"
    /// (RPE, misure corporee, megabyte) che possono finire accanto a un campo.
    public static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        ItalianNumberFormat.number(value, fractionDigits: fractionDigits, grouping: false)
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

    /// Secondi come li scrive la UI sotto il minuto: "45 s".
    public static func seconds(_ value: Int) -> String {
        "\(max(0, value)) s"
    }

    /// Durata breve di una serie o di un recupero: "45 s" sotto il minuto, "1:30" sopra.
    ///
    /// Unico formato per tutti i tempi "corti" dell'app (obiettivo a tempo,
    /// recupero della scheda, recupero predefinito): la regola sta in
    /// ``GymCore/SetMeasure/formatDuration(_:)``, qui c'è solo la soglia.
    public static func shortDuration(seconds value: Int) -> String {
        let total = max(0, value)
        return total < 60 ? seconds(total) : SetMeasure.formatDuration(total)
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

    // MARK: - Compatibilità

    /// **Deprecata.** Non fa più niente: restituisce il testo invariato.
    ///
    /// Serviva quando GymCore produceva il punto decimale. Ora ogni testo numerico
    /// arriva già all'italiana da ``ItalianNumberFormat``, e sostituire i punti
    /// sarebbe **dannoso**: rovinerebbe il separatore delle migliaia ("12.480 kg"
    /// diventerebbe "12,480 kg"). Resta come no-op solo per non rompere i richiami
    /// esistenti; va tolta (con le sue chiamate) appena possibile.
    ///
    /// Non è marcata `@available(deprecated:)` di proposito: farebbe comparire dei
    /// warning nei file di un'altra feature, e la build deve restare senza warning.
    public static func italianDecimals(_ text: String) -> String {
        text
    }
}
