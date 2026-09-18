import Foundation

extension Stats {

    /// Cosa propone la scheda per una certa data.
    public enum TodaysWorkout: Sendable, Hashable {
        /// C'è un giorno da fare.
        case day(ProgramDay)
        /// Modalità a giorni fissi e oggi non è assegnato a nessun giorno: riposo.
        case rest
        /// La scheda non ha ancora giorni.
        case empty

        /// Il giorno proposto, `nil` per riposo o scheda vuota.
        public var programDay: ProgramDay? {
            guard case .day(let day) = self else { return nil }
            return day
        }

        public var isRest: Bool { self == .rest }
    }

    /// Giorno proposto dalla scheda per una certa data.
    ///
    /// - `.weekdays`: il giorno assegnato a oggi; se non c'è, riposo.
    /// - `.rotation`: il giorno successivo all'ultimo giorno di quella scheda che
    ///   risulta completato nello storico; se non c'è storico, il primo giorno.
    ///
    /// La proposta è sempre sovrascrivibile a mano dalla UI.
    ///
    /// - Parameter sessions: storico delle sessioni concluse, in qualunque ordine.
    public static func todaysWorkout(
        for program: Program,
        on date: Date = Date(),
        sessions: [WorkoutSession],
        calendar: Calendar = weekCalendar()
    ) -> TodaysWorkout {
        guard !program.days.isEmpty else { return .empty }

        switch program.mode {
        case .weekdays:
            let today = Weekday.from(date: date, calendar: calendar)
            guard let day = program.days.first(where: { $0.weekday == today }) else { return .rest }
            return .day(day)

        case .rotation:
            guard let lastIndex = lastCompletedDayIndex(of: program, in: sessions, upTo: date) else {
                return .day(program.days[0])
            }
            let next = (lastIndex + 1) % program.days.count
            return .day(program.days[next])
        }
    }

    /// Posizione, dentro `program.days`, dell'ultimo giorno effettivamente allenato.
    ///
    /// Restituisce `nil` se la scheda non è mai stata usata (o se i giorni allenati
    /// non esistono più, ad esempio perché rimossi dall'editor).
    public static func lastCompletedDayIndex(
        of program: Program,
        in sessions: [WorkoutSession],
        upTo date: Date = .distantFuture
    ) -> Int? {
        let relevant = sessions
            .filter { $0.programID == program.id && $0.programDayID != nil && $0.startedAt <= date }
            .sorted { $0.startedAt > $1.startedAt }

        for session in relevant {
            if let index = program.days.firstIndex(where: { $0.id == session.programDayID }) {
                return index
            }
        }
        return nil
    }

    // MARK: - Suggerimento di progressione

    /// Proposta di aumento del carico per un esercizio.
    public struct ProgressionSuggestion: Sendable, Hashable {
        public let exerciseID: String
        /// Carico usato nell'ultima sessione.
        public let currentWeightKg: Double
        /// Carico proposto per oggi.
        public let suggestedWeightKg: Double
        /// Incremento proposto (2,5 kg, oppure 1,25 kg sui piccoli attrezzi).
        public let incrementKg: Double
        /// Motivazione in italiano, da mostrare come hint.
        public let reason: String

        public init(
            exerciseID: String,
            currentWeightKg: Double,
            suggestedWeightKg: Double,
            incrementKg: Double,
            reason: String
        ) {
            self.exerciseID = exerciseID
            self.currentWeightKg = currentWeightKg
            self.suggestedWeightKg = suggestedWeightKg
            self.incrementKg = incrementKg
            self.reason = reason
        }
    }

    /// Attrezzi su cui un incremento di 2,5 kg è troppo: si sale di 1,25 kg.
    public static let smallIncrementEquipment: Set<String> = [
        "dumbbell", "band", "resistance band", "cable", "kettlebell", "ez barbell", "weighted",
    ]

    /// Incremento consigliato per un attrezzo.
    public static func suggestedIncrement(forEquipment equipment: String) -> Double {
        smallIncrementEquipment.contains(equipment.lowercased()) ? 1.25 : 2.5
    }

    /// Suggerisce un aumento di carico quando nell'ultima sessione **tutte** le serie
    /// normali hanno raggiunto il massimo del range di ripetizioni al carico previsto.
    ///
    /// Restituisce `nil` (nessun hint) se l'esercizio è a tempo, se manca lo storico,
    /// se le serie fatte sono meno di quelle previste, se qualche serie è rimasta sotto
    /// il massimo del range, oppure se il carico usato è inferiore a quello della scheda.
    ///
    /// - Parameters:
    ///   - item: la voce della scheda con l'obiettivo da battere.
    ///   - lastSession: l'ultima sessione in cui quell'esercizio è stato allenato.
    ///   - equipment: attrezzo dell'esercizio, per scegliere l'incremento.
    public static func progressionSuggestion(
        for item: PlanItem,
        lastSession: WorkoutSession?,
        equipment: String = ""
    ) -> ProgressionSuggestion? {
        guard case .reps(_, let maxReps) = item.measure, maxReps > 0 else { return nil }
        guard let lastSession else { return nil }

        // Solo le serie `.normal`: warmup, drop e cedimento non fanno testo.
        let sets = lastSession.entries
            .filter { $0.exerciseID == item.exerciseID }
            .flatMap(\.sets)
            .filter { $0.isWorkingSet && $0.kind == .normal }

        guard !sets.isEmpty, sets.count >= max(1, item.targetSets) else { return nil }
        guard sets.allSatisfy({ ($0.reps ?? 0) >= maxReps }) else { return nil }
        guard let currentWeight = sets.compactMap(\.weightKg).min(), currentWeight > 0 else { return nil }
        if let target = item.targetWeightKg, currentWeight < target { return nil }

        let increment = suggestedIncrement(forEquipment: equipment)
        let suggested = currentWeight + increment
        let weightText = WeightUnit.trimmedNumber(currentWeight, fractionDigits: 2)
        let suggestedText = WeightUnit.trimmedNumber(suggested, fractionDigits: 2)
        let reason = "Ultima volta \(sets.count) serie da \(maxReps) ripetizioni a \(weightText) kg: prova \(suggestedText) kg."

        return ProgressionSuggestion(
            exerciseID: item.exerciseID,
            currentWeightKg: currentWeight,
            suggestedWeightKg: suggested,
            incrementKg: increment,
            reason: reason
        )
    }

    // MARK: - Esercizi alternativi

    /// Esercizi con cui sostituire quello indicato (macchina occupata, fastidio…).
    ///
    /// Ordine: prima chi allena lo **stesso muscolo bersaglio**, poi chi condivide la
    /// **categoria**; a parità si privilegia un **attrezzo diverso** dall'originale
    /// (è il motivo più frequente della sostituzione) e i **preferiti**.
    public static func alternatives(
        for exercise: Exercise,
        among candidates: [Exercise],
        favorites: Set<String> = [],
        limit: Int = 12
    ) -> [Exercise] {
        guard limit > 0 else { return [] }

        var scored: [(score: Int, name: String, exercise: Exercise)] = []
        for candidate in candidates where candidate.id != exercise.id {
            var score = 0
            if !exercise.target.isEmpty, candidate.target == exercise.target {
                score += 100
            } else if !exercise.category.isEmpty, candidate.category == exercise.category {
                score += 50
            } else {
                continue
            }
            if candidate.equipment != exercise.equipment { score += 20 }
            if favorites.contains(candidate.id) { score += 10 }
            scored.append((score, candidate.name, candidate))
        }

        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.name < rhs.name : lhs.score > rhs.score
        }
        return scored.prefix(limit).map(\.exercise)
    }
}
