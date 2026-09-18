import Foundation

/// Tipo di serie.
public enum SetKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case warmup, normal, drop, failure

    public var id: String { rawValue }

    /// Le serie di riscaldamento non contribuiscono al volume né ai record.
    public var countsTowardVolume: Bool { self != .warmup }

    /// Etichetta italiana estesa.
    public var displayName: String {
        switch self {
        case .warmup: "Riscaldamento"
        case .normal: "Normale"
        case .drop: "Drop set"
        case .failure: "A cedimento"
        }
    }

    /// Simbolo compatto per la colonna SERIE della tabella.
    public var symbol: String {
        switch self {
        case .warmup: "R"
        case .normal: ""
        case .drop: "D"
        case .failure: "C"
        }
    }
}

/// Una singola serie registrata.
public struct SetLog: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var kind: SetKind
    /// Carico in kg (sempre in kg: la conversione è solo di presentazione).
    public var weightKg: Double?
    public var reps: Int?
    /// Durata in secondi, per esercizi a tempo (plank, cardio).
    public var durationSec: Int?
    /// Sforzo percepito (RPE), opzionale: 6…10 a passi di 0,5.
    public var rpe: Double?
    /// Istante di completamento; `nil` finché la serie non è spuntata.
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: SetKind = .normal,
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSec: Int? = nil,
        rpe: Double? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.rpe = rpe
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }

    /// Valori ammessi per l'RPE nel selettore rapido: 6, 6.5, … 10.
    public static let rpeScale: [Double] = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    /// Riporta un RPE nella scala ammessa (arrotondato a 0,5 e limitato a 6…10).
    public static func normalizedRPE(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return Swift.min(10, Swift.max(6, (value * 2).rounded() / 2))
    }

    /// Volume della serie (kg × reps); 0 per warmup, serie non completate o dati mancanti.
    public var volumeKg: Double {
        guard isCompleted, kind.countsTowardVolume,
              let weight = weightKg, let reps, weight > 0, reps > 0 else { return 0 }
        return weight * Double(reps)
    }

    /// `true` se la serie ha carico e ripetizioni valorizzati e conta per i record.
    public var isWorkingSet: Bool {
        isCompleted && kind.countsTowardVolume && (weightKg ?? 0) > 0 && (reps ?? 0) > 0
    }

    /// `true` se la serie è stata svolta davvero e ha qualcosa da mostrare.
    ///
    /// Più larga di ``isWorkingSet``: comprende anche gli esercizi **a durata**
    /// (plank, cardio) e il **corpo libero** (ripetizioni senza carico), che non
    /// entrano nel volume né nei record ma devono comparire nella colonna
    /// PRECEDENTE e pre-compilare le serie. Riscaldamento e serie non spuntate
    /// restano fuori.
    public var isLoggedSet: Bool {
        isCompleted && kind.countsTowardVolume && ((reps ?? 0) > 0 || (durationSec ?? 0) > 0)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(SetKind.self, forKey: .kind) ?? .normal
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps)
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
        rpe = try c.decodeIfPresent(Double.self, forKey: .rpe)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// Un esercizio dentro una sessione, con le sue serie.
public struct SessionEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var exerciseID: String
    /// Voce della scheda da cui nasce questa riga; `nil` se aggiunta a mano.
    public var planItemID: UUID?
    /// Se l'esercizio si misura a ripetizioni o a tempo.
    public var measureKind: MeasureKind
    public var sets: [SetLog]
    public var note: String
    /// Recupero da usare per questo esercizio, in secondi.
    public var restSeconds: Int
    /// Righe con lo stesso valore non-nil sono un superset.
    public var supersetGroup: Int?

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        planItemID: UUID? = nil,
        measureKind: MeasureKind = .reps,
        sets: [SetLog] = [],
        note: String = "",
        restSeconds: Int = 90,
        supersetGroup: Int? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.planItemID = planItemID
        self.measureKind = measureKind
        self.sets = sets
        self.note = note
        self.restSeconds = max(0, restSeconds)
        self.supersetGroup = supersetGroup
    }

    public var volumeKg: Double { sets.reduce(0) { $0 + $1.volumeKg } }
    public var completedSets: Int { sets.reduce(0) { $0 + ($1.isCompleted ? 1 : 0) } }
    /// Serie completate che contano per volume e record.
    public var workingSets: [SetLog] { sets.filter(\.isWorkingSet) }
    /// Serie completate da mostrare, compresi durata e corpo libero (vedi ``SetLog/isLoggedSet``).
    public var loggedSets: [SetLog] { sets.filter(\.isLoggedSet) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exerciseID = try c.decodeIfPresent(String.self, forKey: .exerciseID) ?? ""
        planItemID = try c.decodeIfPresent(UUID.self, forKey: .planItemID)
        measureKind = try c.decodeIfPresent(MeasureKind.self, forKey: .measureKind) ?? .reps
        sets = try c.decodeIfPresent([SetLog].self, forKey: .sets) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 90
        supersetGroup = try c.decodeIfPresent(Int.self, forKey: .supersetGroup)
    }
}

/// Una sessione di allenamento (in corso o conclusa).
public struct WorkoutSession: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Scheda da cui è partita la sessione; `nil` per un allenamento libero.
    public var programID: UUID?
    /// Giorno della scheda da cui è partita; `nil` per un allenamento libero.
    public var programDayID: UUID?
    public var name: String
    public var startedAt: Date
    /// `nil` finché la sessione è in corso.
    public var endedAt: Date?
    public var entries: [SessionEntry]
    public var notes: String

    public init(
        id: UUID = UUID(),
        programID: UUID? = nil,
        programDayID: UUID? = nil,
        name: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        entries: [SessionEntry] = [],
        notes: String = ""
    ) {
        self.id = id
        self.programID = programID
        self.programDayID = programDayID
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.entries = entries
        self.notes = notes
    }

    /// `true` finché la sessione non è stata terminata.
    public var isActive: Bool { endedAt == nil }

    /// Durata della sessione conclusa; 0 se ancora in corso (usa ``elapsed(asOf:)``).
    public var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// Durata trascorsa a una certa data: utile per il cronometro della sessione attiva.
    public func elapsed(asOf date: Date) -> TimeInterval {
        max(0, (endedAt ?? date).timeIntervalSince(startedAt))
    }

    /// Volume totale in kg (escluse le serie di riscaldamento e quelle non completate).
    public var totalVolumeKg: Double { entries.reduce(0) { $0 + $1.volumeKg } }

    /// Numero di serie spuntate.
    public var completedSets: Int { entries.reduce(0) { $0 + $1.completedSets } }

    /// `true` se non c'è nulla di registrato (usata per scartare sessioni vuote).
    public var hasLoggedWork: Bool { completedSets > 0 }

    /// Id degli esercizi presenti, nell'ordine della sessione.
    public var exerciseIDs: [String] { entries.map(\.exerciseID) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        programID = try c.decodeIfPresent(UUID.self, forKey: .programID)
        programDayID = try c.decodeIfPresent(UUID.self, forKey: .programDayID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        entries = try c.decodeIfPresent([SessionEntry].self, forKey: .entries) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}
