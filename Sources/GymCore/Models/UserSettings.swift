import Foundation

/// Preferenze dell'utente (singolo utente, nessun account).
public struct UserSettings: Codable, Sendable, Hashable {
    /// Numero massimo di esercizi tenuti in "recenti".
    public static let maxRecentExercises = 20

    public var displayName: String
    /// Scheda attualmente attiva; `nil` finché non ne esiste una.
    public var activeProgramID: UUID?
    public var unit: WeightUnit
    /// Recupero di default in secondi, usato quando la scheda non ne specifica uno.
    public var defaultRestSeconds: Int
    public var favoriteExerciseIDs: Set<String>
    /// Esercizi aperti di recente, dal più recente al meno recente.
    public var recentExerciseIDs: [String]
    public var hapticsEnabled: Bool

    public init(
        displayName: String = "Francesco",
        activeProgramID: UUID? = nil,
        unit: WeightUnit = .kg,
        defaultRestSeconds: Int = 90,
        favoriteExerciseIDs: Set<String> = [],
        recentExerciseIDs: [String] = [],
        hapticsEnabled: Bool = true
    ) {
        self.displayName = displayName
        self.activeProgramID = activeProgramID
        self.unit = unit
        self.defaultRestSeconds = max(0, defaultRestSeconds)
        self.favoriteExerciseIDs = favoriteExerciseIDs
        self.recentExerciseIDs = recentExerciseIDs
        self.hapticsEnabled = hapticsEnabled
    }

    public func isFavorite(_ exerciseID: String) -> Bool {
        favoriteExerciseIDs.contains(exerciseID)
    }

    /// Inserisce l'esercizio in cima ai recenti, deduplicando e troncando alla soglia.
    public mutating func markRecent(_ exerciseID: String) {
        guard !exerciseID.isEmpty else { return }
        recentExerciseIDs.removeAll { $0 == exerciseID }
        recentExerciseIDs.insert(exerciseID, at: 0)
        if recentExerciseIDs.count > UserSettings.maxRecentExercises {
            recentExerciseIDs.removeLast(recentExerciseIDs.count - UserSettings.maxRecentExercises)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserSettings()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? defaults.displayName
        activeProgramID = try c.decodeIfPresent(UUID.self, forKey: .activeProgramID)
        unit = try c.decodeIfPresent(WeightUnit.self, forKey: .unit) ?? defaults.unit
        defaultRestSeconds = try c.decodeIfPresent(Int.self, forKey: .defaultRestSeconds) ?? defaults.defaultRestSeconds
        favoriteExerciseIDs = try c.decodeIfPresent(Set<String>.self, forKey: .favoriteExerciseIDs) ?? []
        recentExerciseIDs = try c.decodeIfPresent([String].self, forKey: .recentExerciseIDs) ?? []
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? defaults.hapticsEnabled
    }
}

/// Una misurazione corporea.
public struct BodyMetric: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var date: Date
    public var weightKg: Double
    /// Percentuale di massa grassa, 0…100.
    public var bodyFatPct: Double?

    public init(id: UUID = UUID(), date: Date = Date(), weightKg: Double, bodyFatPct: Double? = nil) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 0
        bodyFatPct = try c.decodeIfPresent(Double.self, forKey: .bodyFatPct)
    }
}
