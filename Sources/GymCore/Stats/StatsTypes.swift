import Foundation

extension Stats {

    /// Tipo di record personale.
    public enum RecordKind: String, Sendable, Hashable, CaseIterable, Identifiable {
        /// Carico massimo sollevato in una serie.
        case maxWeight
        /// Miglior massimale stimato (Epley).
        case best1RM
        /// Volume massimo accumulato in una singola sessione.
        case sessionVolume

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .maxWeight: "Carico record"
            case .best1RM: "Massimale stimato"
            case .sessionVolume: "Volume record"
            }
        }

        /// Etichetta compatta per il badge in sessione.
        public var badge: String {
            switch self {
            case .maxWeight: "PR carico"
            case .best1RM: "PR 1RM"
            case .sessionVolume: "PR volume"
            }
        }
    }

    /// Record personali per un esercizio.
    public struct ExerciseRecords: Sendable, Hashable {
        public let exerciseID: String
        public let maxWeightKg: Double
        public let maxWeightDate: Date
        public let best1RMKg: Double
        public let best1RMDate: Date
        public let maxSessionVolumeKg: Double
        public let maxSessionVolumeDate: Date

        public init(
            exerciseID: String,
            maxWeightKg: Double,
            maxWeightDate: Date,
            best1RMKg: Double,
            best1RMDate: Date,
            maxSessionVolumeKg: Double,
            maxSessionVolumeDate: Date
        ) {
            self.exerciseID = exerciseID
            self.maxWeightKg = maxWeightKg
            self.maxWeightDate = maxWeightDate
            self.best1RMKg = best1RMKg
            self.best1RMDate = best1RMDate
            self.maxSessionVolumeKg = maxSessionVolumeKg
            self.maxSessionVolumeDate = maxSessionVolumeDate
        }
    }

    /// Ultima prestazione registrata per un esercizio: serve a pre-compilare le serie
    /// e a riempire la colonna PRECEDENTE della tabella in sessione.
    public struct PreviousPerformance: Sendable, Hashable {
        public let sessionID: UUID
        public let date: Date
        /// Serie di lavoro completate, nell'ordine originale.
        public let sets: [SetLog]

        public init(sessionID: UUID, date: Date, sets: [SetLog]) {
            self.sessionID = sessionID
            self.date = date
            self.sets = sets
        }

        /// Testo per la colonna PRECEDENTE di una certa serie (`"80 × 8"`), `nil` se non c'è.
        public func text(forSetAt position: Int, unit: WeightUnit = .kg) -> String? {
            guard let set = sets.indices.contains(position) ? sets[position] : sets.last,
                  let weight = set.weightKg, let reps = set.reps else { return nil }
            return "\(unit.format(kilograms: weight, includeSymbol: false)) × \(reps)"
        }
    }

    /// Aggregati di una settimana (che inizia di lunedì).
    public struct WeekSummary: Sendable, Hashable, Identifiable {
        /// Lunedì della settimana, a mezzanotte.
        public let weekStart: Date
        public let workouts: Int
        public let volumeKg: Double
        /// Durata totale arrotondata ai minuti.
        public let minutes: Int
        public let completedSets: Int
        /// Serie completate per categoria dell'esercizio (chiave inglese del dataset).
        public let setsByCategory: [String: Int]
        /// Serie completate per zona colpita "da palestra".
        ///
        /// È l'aggregato da mostrare in Progressi: parte dal `target` **corretto**
        /// (vedi ``ExerciseCorrections``), mai dal campo `muscle_group` del dataset
        /// né dai muscoli secondari (SPEC §2, punti 2 e 3).
        public let setsByMuscleGroup: [MuscleGroup: Int]

        public var id: Date { weekStart }

        public init(
            weekStart: Date,
            workouts: Int,
            volumeKg: Double,
            minutes: Int,
            completedSets: Int,
            setsByCategory: [String: Int],
            setsByMuscleGroup: [MuscleGroup: Int] = [:]
        ) {
            self.weekStart = weekStart
            self.workouts = workouts
            self.volumeKg = volumeKg
            self.minutes = minutes
            self.completedSets = completedSets
            self.setsByCategory = setsByCategory
            self.setsByMuscleGroup = setsByMuscleGroup
        }

        /// Serie per zona colpita, ordinate per volume di lavoro decrescente e poi
        /// per ordine anatomico: pronte da mettere in una card.
        public var muscleGroupBreakdown: [MuscleGroupFacet] {
            setsByMuscleGroup
                .map { MuscleGroupFacet(group: $0.key, count: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    let order = MuscleGroup.displayOrder
                    return (order.firstIndex(of: lhs.group) ?? 0) < (order.firstIndex(of: rhs.group) ?? 0)
                }
        }
    }

    /// Un giorno nella griglia di attività.
    public struct ActivityDay: Sendable, Hashable, Identifiable {
        /// Mezzanotte del giorno.
        public let date: Date
        public let workouts: Int
        public let volumeKg: Double

        public var id: Date { date }
        public var isActive: Bool { workouts > 0 }

        public init(date: Date, workouts: Int, volumeKg: Double) {
            self.date = date
            self.workouts = workouts
            self.volumeKg = volumeKg
        }
    }

    /// Un punto della serie storica di un esercizio (un punto per giorno di allenamento).
    public struct ExerciseDataPoint: Sendable, Hashable, Identifiable {
        /// Mezzanotte del giorno.
        public let date: Date
        public let maxWeightKg: Double
        public let best1RMKg: Double
        public let volumeKg: Double

        public var id: Date { date }

        public init(date: Date, maxWeightKg: Double, best1RMKg: Double, volumeKg: Double) {
            self.date = date
            self.maxWeightKg = maxWeightKg
            self.best1RMKg = best1RMKg
            self.volumeKg = volumeKg
        }
    }
}
