import Foundation

/// Giorno della settimana con **lunedì come primo giorno** e nomi in italiano.
///
/// L'ordine di `allCases` è già quello di presentazione (L → D).
public enum Weekday: String, Codable, Sendable, Hashable, CaseIterable, Identifiable, Comparable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: String { rawValue }

    /// Posizione nella settimana con lunedì = 1 … domenica = 7.
    public var order: Int {
        switch self {
        case .monday: 1
        case .tuesday: 2
        case .wednesday: 3
        case .thursday: 4
        case .friday: 5
        case .saturday: 6
        case .sunday: 7
        }
    }

    /// Indice usato da `Calendar` (domenica = 1 … sabato = 7).
    public var calendarWeekday: Int {
        self == .sunday ? 1 : order + 1
    }

    /// Nome esteso in italiano, minuscolo (`"lunedì"`).
    public var italianName: String {
        switch self {
        case .monday: "lunedì"
        case .tuesday: "martedì"
        case .wednesday: "mercoledì"
        case .thursday: "giovedì"
        case .friday: "venerdì"
        case .saturday: "sabato"
        case .sunday: "domenica"
        }
    }

    /// Nome esteso in italiano con l'iniziale maiuscola (`"Lunedì"`).
    public var displayName: String {
        guard let first = italianName.first else { return italianName }
        return first.uppercased() + italianName.dropFirst()
    }

    /// Abbreviazione a tre lettere (`"Lun"`), per la striscia settimanale.
    public var shortName: String {
        String(displayName.prefix(3))
    }

    /// Iniziale singola (`"L"`, `"M"`, …), per le griglie compatte.
    public var letter: String {
        switch self {
        case .monday: "L"
        case .tuesday: "M"
        case .wednesday: "M"
        case .thursday: "G"
        case .friday: "V"
        case .saturday: "S"
        case .sunday: "D"
        }
    }

    /// Converte l'indice `Calendar` (domenica = 1) nel giorno corrispondente.
    public static func from(calendarWeekday: Int) -> Weekday? {
        allCases.first { $0.calendarWeekday == calendarWeekday }
    }

    /// Giorno della settimana di una data, secondo il calendario indicato.
    public static func from(date: Date, calendar: Calendar = Stats.weekCalendar()) -> Weekday {
        from(calendarWeekday: calendar.component(.weekday, from: date)) ?? .monday
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.order < rhs.order }
}
