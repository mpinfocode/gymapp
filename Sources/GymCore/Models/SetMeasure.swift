import Foundation

/// Come si misura una serie: a ripetizioni o a tempo.
public enum MeasureKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case reps
    case duration

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .reps: "Ripetizioni"
        case .duration: "Durata"
        }
    }

    /// Intestazione della colonna nella tabella di sessione.
    public var columnTitle: String {
        switch self {
        case .reps: "REPS"
        case .duration: "TEMPO"
        }
    }
}

/// Obiettivo di una serie prevista dalla scheda: un range di ripetizioni oppure una durata.
///
/// Serializzato con un discriminante esplicito (`{"kind":"reps","min":8,"max":12}`)
/// per restare leggibile e stabile se in futuro si aggiungono altri modi di misurare.
public enum SetMeasure: Codable, Sendable, Hashable {
    case reps(min: Int, max: Int)
    case duration(seconds: Int)

    /// Valore di ripiego quando il JSON non è interpretabile.
    public static let `default` = SetMeasure.reps(min: 8, max: 12)

    public var kind: MeasureKind {
        switch self {
        case .reps: .reps
        case .duration: .duration
        }
    }

    /// Range di ripetizioni, `nil` per gli esercizi a tempo.
    public var repsRange: ClosedRange<Int>? {
        guard case .reps(let min, let max) = self else { return nil }
        return min...Swift.max(min, max)
    }

    /// Durata prevista in secondi, `nil` per gli esercizi a ripetizioni.
    public var durationSeconds: Int? {
        guard case .duration(let seconds) = self else { return nil }
        return seconds
    }

    /// Testo per l'editor e per la tabella (`"8-12"`, `"10"`, `"45s"`, `"1:30"`).
    public var displayText: String {
        switch self {
        case .reps(let min, let max):
            min == max ? "\(min)" : "\(min)-\(max)"
        case .duration(let seconds):
            SetMeasure.formatDuration(seconds)
        }
    }

    /// Durata compatta: `"45s"` sotto il minuto, `"1:30"` sopra.
    public static func formatDuration(_ seconds: Int) -> String {
        let total = Swift.max(0, seconds)
        guard total >= 60 else { return "\(total)s" }
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case kind, min, max, seconds }

    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        let kind = try container.decodeIfPresent(MeasureKind.self, forKey: .kind) ?? .reps
        switch kind {
        case .reps:
            let min = try container.decodeIfPresent(Int.self, forKey: .min) ?? 8
            let max = try container.decodeIfPresent(Int.self, forKey: .max) ?? min
            self = .reps(min: Swift.max(0, min), max: Swift.max(min, max))
        case .duration:
            self = .duration(seconds: Swift.max(0, try container.decodeIfPresent(Int.self, forKey: .seconds) ?? 30))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .reps(let min, let max):
            try container.encode(min, forKey: .min)
            try container.encode(max, forKey: .max)
        case .duration(let seconds):
            try container.encode(seconds, forKey: .seconds)
        }
    }
}
