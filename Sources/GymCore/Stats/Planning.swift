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

    /// Proposta di progressione per un esercizio: più carico oppure più ripetizioni.
    public struct ProgressionSuggestion: Sendable, Hashable {

        /// Su cosa si progredisce.
        public enum Kind: String, Sendable, Hashable, CaseIterable, Identifiable {
            /// Si sale di carico, al passo dell'attrezzo (vedi ``WeightStep``).
            case weight
            /// L'attrezzo non ha un passo di carico (corpo libero, elastici):
            /// si progredisce aggiungendo ripetizioni.
            case reps

            public var id: String { rawValue }
        }

        public let exerciseID: String
        /// Carico usato nell'ultima sessione (0 a corpo libero).
        public let currentWeightKg: Double
        /// Carico proposto per oggi; uguale a ``currentWeightKg`` se si progredisce a ripetizioni.
        public let suggestedWeightKg: Double
        /// Incremento di carico proposto, già arrotondato al passo dell'attrezzo; 0 se si progredisce a ripetizioni.
        public let incrementKg: Double
        /// Motivazione in italiano, da mostrare come hint.
        public let reason: String
        /// Tipo di progressione proposta.
        public let kind: Kind
        /// Ripetizioni proposte, valorizzate solo quando ``kind`` è ``Kind/reps``.
        public let suggestedReps: Int?

        public init(
            exerciseID: String,
            currentWeightKg: Double,
            suggestedWeightKg: Double,
            incrementKg: Double,
            reason: String,
            kind: Kind = .weight,
            suggestedReps: Int? = nil
        ) {
            self.exerciseID = exerciseID
            self.currentWeightKg = currentWeightKg
            self.suggestedWeightKg = suggestedWeightKg
            self.incrementKg = incrementKg
            self.reason = reason
            self.kind = kind
            self.suggestedReps = suggestedReps
        }
    }

    /// Attrezzi su cui l'incremento era di 1,25 kg prima dell'introduzione di
    /// ``WeightStep``. Conservato per retro-compatibilità: **non è più usato**
    /// dal calcolo, che ora passa dal passo per attrezzo.
    public static let smallIncrementEquipment: Set<String> = [
        "dumbbell", "band", "resistance band", "cable", "kettlebell", "ez barbell", "weighted",
    ]

    /// Incremento di carico consigliato per un attrezzo, al passo reale della palestra
    /// (bilanciere 2,5 · manubri 2 · kettlebell 4 · cavi e macchine 5, 2,5 sotto i 20 kg).
    ///
    /// Restituisce **0** dove il carico non si regola (corpo libero, elastici): lì la
    /// progressione è a ripetizioni. Per distinguere i due casi usa direttamente
    /// ``WeightStep/step(forEquipment:currentWeightKg:)``, che restituisce `nil`.
    public static func suggestedIncrement(forEquipment equipment: String, currentWeightKg: Double = 0) -> Double {
        WeightStep.step(forEquipment: equipment, currentWeightKg: currentWeightKg) ?? 0
    }

    // MARK: - Riscaldamento

    /// Quota del carico di lavoro usata per pre-compilare le serie di riscaldamento.
    public static let warmupRatio: Double = 0.55

    /// Carico di riscaldamento a partire dal carico di lavoro: ~55%, arrotondato al
    /// passo dell'attrezzo (SPEC §5, "serie precompilate").
    ///
    /// Restituisce `nil` quando non c'è un carico di riferimento, quando l'attrezzo
    /// non ha un passo di carico (corpo libero, elastici) o quando il riscaldamento
    /// finirebbe a zero o già al carico di lavoro: in quei casi la serie resta vuota.
    public static func warmupWeight(
        forWorkingWeightKg workingWeightKg: Double?,
        equipment: String = "",
        ratio: Double = warmupRatio
    ) -> Double? {
        guard let workingWeightKg, workingWeightKg > 0 else { return nil }
        let target = workingWeightKg * ratio
        guard WeightStep.step(forEquipment: equipment, currentWeightKg: target) != nil else { return nil }
        let rounded = WeightStep.round(target, forEquipment: equipment)
        guard rounded > 0, rounded < workingWeightKg else { return nil }
        return rounded
    }

    /// Suggerisce una progressione quando nell'ultima sessione **tutte** le serie
    /// normali hanno raggiunto il massimo del range di ripetizioni al carico previsto.
    ///
    /// L'aumento è sempre al **passo dell'attrezzo** (``WeightStep``): bilanciere, ez,
    /// trap bar e multipower +2,5 kg; manubri +2 kg per manubrio; kettlebell +4 kg;
    /// cavi e macchine +5 kg (+2,5 kg sotto i 20 kg). Dove il carico non si regola
    /// (corpo libero, elastici) la proposta è di **aggiungere una ripetizione**
    /// invece che del carico (``ProgressionSuggestion/Kind/reps``).
    ///
    /// Restituisce `nil` (nessun hint) se l'esercizio è a tempo, se manca lo storico,
    /// se le serie fatte sono meno di quelle previste, se qualche serie è rimasta sotto
    /// il massimo del range, oppure se il carico usato è inferiore a quello della scheda.
    ///
    /// - Parameters:
    ///   - item: la voce della scheda con l'obiettivo da battere.
    ///   - lastSession: l'ultima sessione in cui quell'esercizio è stato allenato.
    ///   - equipment: attrezzo dell'esercizio, per scegliere il passo.
    public static func progressionSuggestion(
        for item: PlanItem,
        lastSession: WorkoutSession?,
        equipment: String = ""
    ) -> ProgressionSuggestion? {
        guard case .reps(_, let maxReps) = item.measure, maxReps > 0 else { return nil }
        guard let lastSession else { return nil }

        // Solo le serie `.normal` spuntate: warmup, drop e cedimento non fanno testo.
        // Il carico può mancare (corpo libero), le ripetizioni no.
        let sets = lastSession.entries
            .filter { $0.exerciseID == item.exerciseID }
            .flatMap(\.sets)
            .filter { $0.isCompleted && $0.kind == .normal && ($0.reps ?? 0) > 0 }

        guard !sets.isEmpty, sets.count >= max(1, item.targetSets) else { return nil }
        guard sets.allSatisfy({ ($0.reps ?? 0) >= maxReps }) else { return nil }

        let currentWeight = sets.compactMap(\.weightKg).filter { $0 > 0 }.min() ?? 0
        if let target = item.targetWeightKg, currentWeight < target { return nil }

        let doneText = "Ultima volta \(sets.count) serie da \(maxReps) ripetizioni"

        // Progressione a carico: serve un carico di partenza e un passo per l'attrezzo.
        if currentWeight > 0, let suggested = WeightStep.next(after: currentWeight, forEquipment: equipment) {
            let weightText = ItalianNumberFormat.number(currentWeight, fractionDigits: 2, grouping: false)
            let suggestedText = ItalianNumberFormat.number(suggested, fractionDigits: 2, grouping: false)
            return ProgressionSuggestion(
                exerciseID: item.exerciseID,
                currentWeightKg: currentWeight,
                suggestedWeightKg: suggested,
                incrementKg: suggested - currentWeight,
                reason: "\(doneText) a \(weightText) kg: prova \(suggestedText) kg.",
                kind: .weight
            )
        }

        // Corpo libero ed elastici: si aggiunge una ripetizione.
        let suggestedReps = maxReps + 1
        let carried = currentWeight > 0
            ? " a \(ItalianNumberFormat.number(currentWeight, fractionDigits: 2, grouping: false)) kg"
            : ""
        return ProgressionSuggestion(
            exerciseID: item.exerciseID,
            currentWeightKg: currentWeight,
            suggestedWeightKg: currentWeight,
            incrementKg: 0,
            reason: "\(doneText)\(carried): prova \(suggestedReps) ripetizioni.",
            kind: .reps,
            suggestedReps: suggestedReps
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
