import Foundation

/// Come si decide l'allenamento del giorno.
public enum ProgramMode: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// I giorni si susseguono a rotazione, indipendentemente dal calendario.
    case rotation
    /// Ogni giorno della scheda è assegnato a un giorno della settimana.
    case weekdays

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rotation: "A rotazione"
        case .weekdays: "Giorni fissi"
        }
    }

    public var explanation: String {
        switch self {
        case .rotation: "I giorni si alternano in ordine, qualunque sia il giorno della settimana."
        case .weekdays: "Ogni giorno della scheda è legato a un giorno della settimana."
        }
    }
}

/// Un esercizio previsto dalla scheda, con serie, obiettivo e carico.
public struct PlanItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// `Exercise.id` del dataset.
    public var exerciseID: String
    /// Serie di lavoro previste (escluse quelle di riscaldamento).
    public var targetSets: Int
    /// Obiettivo: range di ripetizioni oppure durata.
    public var measure: SetMeasure
    /// Carico indicato dall'istruttore, in kg; `nil` se lasciato libero.
    public var targetWeightKg: Double?
    /// Serie di riscaldamento da proporre prima di quelle di lavoro.
    public var warmupSets: Int
    public var restSeconds: Int
    /// Esercizi con lo stesso valore non-nil formano un superset.
    public var supersetGroup: Int?
    /// Nota dell'istruttore ("presa stretta", "panca 30°").
    public var note: String

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        targetSets: Int = 3,
        measure: SetMeasure = .default,
        targetWeightKg: Double? = nil,
        warmupSets: Int = 0,
        restSeconds: Int = 90,
        supersetGroup: Int? = nil,
        note: String = ""
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.targetSets = max(0, targetSets)
        self.measure = measure
        self.targetWeightKg = targetWeightKg
        self.warmupSets = max(0, warmupSets)
        self.restSeconds = max(0, restSeconds)
        self.supersetGroup = supersetGroup
        self.note = note
    }

    /// Riga di riepilogo per l'editor (`"4 × 6-8 · 80 kg"`).
    public func summary(unit: WeightUnit = .kg) -> String {
        var parts = ["\(targetSets) × \(measure.displayText)"]
        if let weight = targetWeightKg { parts.append(unit.format(kilograms: weight)) }
        return parts.joined(separator: " · ")
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exerciseID = try c.decodeIfPresent(String.self, forKey: .exerciseID) ?? ""
        targetSets = max(0, try c.decodeIfPresent(Int.self, forKey: .targetSets) ?? 3)
        measure = try c.decodeIfPresent(SetMeasure.self, forKey: .measure) ?? .default
        targetWeightKg = try c.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        warmupSets = max(0, try c.decodeIfPresent(Int.self, forKey: .warmupSets) ?? 0)
        restSeconds = max(0, try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 90)
        supersetGroup = try c.decodeIfPresent(Int.self, forKey: .supersetGroup)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// Un giorno della scheda ("Giorno A", "Push"…).
public struct ProgramDay: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// Giorno della settimana assegnato; usato solo in modalità ``ProgramMode/weekdays``.
    public var weekday: Weekday?
    public var items: [PlanItem]
    public var note: String

    public init(
        id: UUID = UUID(),
        name: String,
        weekday: Weekday? = nil,
        items: [PlanItem] = [],
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.weekday = weekday
        self.items = items
        self.note = note
    }

    /// Serie di lavoro previste dal giorno.
    public var totalSets: Int { items.reduce(0) { $0 + $1.targetSets } }

    /// Id degli esercizi, nell'ordine del giorno.
    public var exerciseIDs: [String] { items.map(\.exerciseID) }

    /// Gruppi di superset presenti, in ordine.
    public var supersetGroups: [Int] {
        var seen: Set<Int> = []
        return items.compactMap(\.supersetGroup).filter { seen.insert($0).inserted }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        weekday = try c.decodeIfPresent(Weekday.self, forKey: .weekday)
        items = try c.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// La scheda dell'istruttore: un ciclo di allenamento con una durata prevista.
///
/// Una sola scheda è attiva alla volta (``UserSettings/activeProgramID``);
/// le altre restano in archivio, consultabili e duplicabili.
public struct Program: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var notes: String
    public var startDate: Date
    /// Durata prevista in settimane (tipicamente 4–8); `nil` = senza scadenza.
    public var plannedWeeks: Int?
    public var mode: ProgramMode
    public var days: [ProgramDay]
    /// Seme per il gradiente della card (vedi GymUI).
    public var accent: Int
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        startDate: Date = Date(),
        plannedWeeks: Int? = nil,
        mode: ProgramMode = .rotation,
        days: [ProgramDay] = [],
        accent: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.startDate = startDate
        self.plannedWeeks = plannedWeeks.map { max(0, $0) }
        self.mode = mode
        self.days = days
        self.accent = accent
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Contenuto

    public func day(id dayID: UUID) -> ProgramDay? { days.first { $0.id == dayID } }

    /// Serie di lavoro previste da tutta la scheda.
    public var totalSets: Int { days.reduce(0) { $0 + $1.totalSets } }

    /// Id di tutti gli esercizi usati dalla scheda, senza duplicati e in ordine.
    public var exerciseIDs: [String] {
        var seen: Set<String> = []
        return days.flatMap(\.exerciseIDs).filter { seen.insert($0).inserted }
    }

    /// Cerca la voce di piano con quell'id in tutti i giorni.
    public func item(id itemID: UUID) -> PlanItem? {
        for day in days {
            if let item = day.items.first(where: { $0.id == itemID }) { return item }
        }
        return nil
    }

    // MARK: - Durata e scadenza

    /// Primo giorno della scheda, a mezzanotte.
    public func normalizedStart(calendar: Calendar = Stats.weekCalendar()) -> Date {
        calendar.startOfDay(for: startDate)
    }

    /// Giorno in cui la scheda scade; `nil` se non ha una durata prevista.
    public func endDate(calendar: Calendar = Stats.weekCalendar()) -> Date? {
        guard let plannedWeeks, plannedWeeks > 0 else { return nil }
        return calendar.date(byAdding: .day, value: plannedWeeks * 7, to: normalizedStart(calendar: calendar))
    }

    /// Settimane intere trascorse dall'inizio (0 nella prima settimana).
    public func weeksElapsed(asOf date: Date = Date(), calendar: Calendar = Stats.weekCalendar()) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: normalizedStart(calendar: calendar),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return max(0, days / 7)
    }

    /// Settimana corrente in base 1, come la mostra la UI ("Settimana 3 di 6").
    public func currentWeek(asOf date: Date = Date(), calendar: Calendar = Stats.weekCalendar()) -> Int {
        weeksElapsed(asOf: date, calendar: calendar) + 1
    }

    /// `true` se la data di fine è già passata.
    public func isExpired(asOf date: Date = Date(), calendar: Calendar = Stats.weekCalendar()) -> Bool {
        guard let endDate = endDate(calendar: calendar) else { return false }
        return calendar.startOfDay(for: date) >= endDate
    }

    /// Giorni che mancano alla scadenza (0 se scaduta oggi o prima); `nil` senza scadenza.
    public func daysToExpiry(asOf date: Date = Date(), calendar: Calendar = Stats.weekCalendar()) -> Int? {
        guard let endDate = endDate(calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: endDate).day ?? 0
        return max(0, days)
    }

    /// Testo di stato per la card di Oggi ("Settimana 3 di 6", "Scaduta", "Senza scadenza").
    public func statusText(asOf date: Date = Date(), calendar: Calendar = Stats.weekCalendar()) -> String {
        guard let plannedWeeks, plannedWeeks > 0 else { return "Senza scadenza" }
        if isExpired(asOf: date, calendar: calendar) { return "Scheda scaduta" }
        return "Settimana \(min(currentWeek(asOf: date, calendar: calendar), plannedWeeks)) di \(plannedWeeks)"
    }

    /// `true` quando conviene avvisare l'utente che la scheda sta per finire (≤ 7 giorni).
    public func isExpiringSoon(asOf date: Date = Date(), calendar: Calendar = Stats.weekCalendar()) -> Bool {
        guard let remaining = daysToExpiry(asOf: date, calendar: calendar) else { return false }
        return remaining <= 7 && !isExpired(asOf: date, calendar: calendar)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? created
        plannedWeeks = (try c.decodeIfPresent(Int.self, forKey: .plannedWeeks)).map { max(0, $0) }
        mode = try c.decodeIfPresent(ProgramMode.self, forKey: .mode) ?? .rotation
        days = try c.decodeIfPresent([ProgramDay].self, forKey: .days) ?? []
        accent = try c.decodeIfPresent(Int.self, forKey: .accent) ?? 0
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = created
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
    }
}
