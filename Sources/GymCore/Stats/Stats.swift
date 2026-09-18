import Foundation

/// Statistiche e progressi: **solo funzioni pure**, nessuno stato.
///
/// Il `Calendar` è sempre iniettabile (default: gregoriano con la settimana che
/// inizia di lunedì) così i check possono fissare fuso orario e settimana.
public enum Stats {

    /// Calendario gregoriano con lunedì come primo giorno della settimana.
    public static func weekCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // lunedì
        calendar.minimumDaysInFirstWeek = 4 // ISO 8601
        calendar.timeZone = timeZone
        return calendar
    }

    /// Ripetizioni oltre le quali la formula di Epley non è più attendibile (SPEC §4).
    public static let maxRepsFor1RM = 12

    // MARK: - Volume

    /// Volume in kg di un insieme di serie (kg × reps), escluse warmup e serie non completate.
    public static func volume(of sets: [SetLog]) -> Double {
        sets.reduce(0) { $0 + $1.volumeKg }
    }

    public static func volume(of entry: SessionEntry) -> Double { entry.volumeKg }

    public static func volume(of session: WorkoutSession) -> Double { session.totalVolumeKg }

    /// Volume di un solo esercizio dentro una sessione (l'esercizio può comparire più volte).
    public static func volume(of session: WorkoutSession, exerciseID: String) -> Double {
        session.entries
            .filter { $0.exerciseID == exerciseID }
            .reduce(0) { $0 + $1.volumeKg }
    }

    // MARK: - Massimale stimato

    /// Massimale stimato con la formula di Epley: `peso × (1 + reps / 30)`.
    ///
    /// Restituisce `nil` fuori dall'intervallo 1…12 ripetizioni o con carico non positivo:
    /// oltre le 12 reps la stima diverge troppo per essere mostrata come record.
    public static func epley1RM(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1, reps <= maxRepsFor1RM else { return nil }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// Massimale stimato di una serie, `nil` se la serie non è valida per il calcolo.
    public static func epley1RM(of set: SetLog) -> Double? {
        guard set.isWorkingSet, let weight = set.weightKg, let reps = set.reps else { return nil }
        return epley1RM(weightKg: weight, reps: reps)
    }

    /// Miglior massimale stimato fra più serie.
    public static func best1RM(in sets: [SetLog]) -> Double? {
        sets.compactMap(epley1RM(of:)).max()
    }

    /// Carico massimo fra più serie di lavoro completate.
    public static func maxWeight(in sets: [SetLog]) -> Double? {
        sets.filter(\.isWorkingSet).compactMap(\.weightKg).max()
    }

    // MARK: - Record personali

    /// Record personali di un esercizio sullo storico fornito.
    ///
    /// Restituisce `nil` se l'esercizio non ha mai avuto serie di lavoro completate.
    public static func records(for exerciseID: String, in sessions: [WorkoutSession]) -> ExerciseRecords? {
        var maxWeight: (value: Double, date: Date)?
        var best1RM: (value: Double, date: Date)?
        var maxVolume: (value: Double, date: Date)?

        for session in sessions {
            let sets = workingSets(for: exerciseID, in: session)
            guard !sets.isEmpty else { continue }
            let date = session.startedAt

            if let weight = sets.compactMap(\.weightKg).max(), maxWeight == nil || weight > maxWeight!.value {
                maxWeight = (weight, date)
            }
            if let oneRM = Stats.best1RM(in: sets), best1RM == nil || oneRM > best1RM!.value {
                best1RM = (oneRM, date)
            }
            let volume = sets.reduce(0) { $0 + $1.volumeKg }
            if volume > 0, maxVolume == nil || volume > maxVolume!.value {
                maxVolume = (volume, date)
            }
        }

        guard let maxWeight else { return nil }
        // Se nessuna serie è nel range 1…12 reps il massimale stimato resta 0 (non stimabile).
        let oneRM = best1RM ?? (value: 0, date: maxWeight.date)
        let volume = maxVolume ?? (value: 0, date: maxWeight.date)

        return ExerciseRecords(
            exerciseID: exerciseID,
            maxWeightKg: maxWeight.value,
            maxWeightDate: maxWeight.date,
            best1RMKg: oneRM.value,
            best1RMDate: oneRM.date,
            maxSessionVolumeKg: volume.value,
            maxSessionVolumeDate: volume.date
        )
    }

    /// Record raggiunti **in tempo reale** da una serie appena spuntata.
    ///
    /// - Parameters:
    ///   - exerciseID: esercizio della serie.
    ///   - set: la serie appena completata.
    ///   - sessionVolumeKg: volume accumulato finora nella sessione in corso per quell'esercizio.
    ///   - history: sessioni **concluse** (la sessione in corso non va inclusa).
    ///   - earlierSetsInSession: serie di lavoro già completate oggi per lo stesso esercizio,
    ///     escludendo `set`. Servono a non segnalare un PR a ogni serie uguale della stessa
    ///     sessione. Il volume, invece, si confronta solo con lo storico.
    /// - Returns: i record battuti, vuoto se nessuno.
    ///
    /// Se l'esercizio non ha storico, la prima serie di lavoro valida è considerata
    /// un record (è il primo dato disponibile, e in palestra fa piacere vederlo).
    public static func records(
        for exerciseID: String,
        achievedBy set: SetLog,
        sessionVolumeKg: Double,
        history: [WorkoutSession],
        earlierSetsInSession: [SetLog] = []
    ) -> Set<RecordKind> {
        guard set.isWorkingSet, let weight = set.weightKg else { return [] }
        let previous = records(for: exerciseID, in: history)
        let earlier = earlierSetsInSession.filter { $0.id != set.id }

        let weightToBeat = max(previous?.maxWeightKg ?? 0, maxWeight(in: earlier) ?? 0)
        let oneRMToBeat = max(previous?.best1RMKg ?? 0, best1RM(in: earlier) ?? 0)

        var achieved: Set<RecordKind> = []
        if weight > weightToBeat { achieved.insert(.maxWeight) }
        if let oneRM = epley1RM(of: set), oneRM > oneRMToBeat { achieved.insert(.best1RM) }
        if sessionVolumeKg > 0, sessionVolumeKg > (previous?.maxSessionVolumeKg ?? 0) { achieved.insert(.sessionVolume) }

        return achieved
    }

    // MARK: - Prestazione precedente

    /// Ultima sessione (strettamente precedente a `date`) in cui l'esercizio è stato allenato.
    ///
    /// - Parameter sessions: storico, in qualunque ordine.
    public static func previousPerformance(
        for exerciseID: String,
        in sessions: [WorkoutSession],
        before date: Date = .distantFuture
    ) -> PreviousPerformance? {
        var best: WorkoutSession?
        for session in sessions where session.startedAt < date {
            guard !workingSets(for: exerciseID, in: session).isEmpty else { continue }
            if best == nil || session.startedAt > best!.startedAt { best = session }
        }
        guard let best else { return nil }
        return PreviousPerformance(
            sessionID: best.id,
            date: best.startedAt,
            sets: workingSets(for: exerciseID, in: best)
        )
    }

    // MARK: - Aggregati settimanali

    /// Riepiloghi settimanali, una voce per ogni settimana in cui c'è almeno un allenamento,
    /// ordinati dalla più recente alla più vecchia.
    ///
    /// - Parameter exercisesByID: serve per attribuire le serie al gruppo muscolare
    ///   (si usa la `category` dell'esercizio, vedi SPEC §4). Se vuoto, `setsByCategory` resta vuoto.
    public static func weeklySummaries(
        sessions: [WorkoutSession],
        exercisesByID: [String: Exercise] = [:],
        calendar: Calendar = weekCalendar()
    ) -> [WeekSummary] {
        var byWeek: [Date: (workouts: Int, volume: Double, seconds: TimeInterval, sets: Int, categories: [String: Int])] = [:]

        for session in sessions {
            guard let weekStart = startOfWeek(for: session.startedAt, calendar: calendar) else { continue }
            var bucket = byWeek[weekStart] ?? (0, 0, 0, 0, [:])
            bucket.workouts += 1
            bucket.volume += session.totalVolumeKg
            bucket.seconds += session.duration
            bucket.sets += session.completedSets
            for entry in session.entries {
                let completed = entry.sets.reduce(0) { $0 + ($1.isCompleted ? 1 : 0) }
                guard completed > 0 else { continue }
                let category = exercisesByID[entry.exerciseID]?.category ?? ""
                guard !category.isEmpty else { continue }
                bucket.categories[category, default: 0] += completed
            }
            byWeek[weekStart] = bucket
        }

        return byWeek
            .map { weekStart, bucket in
                WeekSummary(
                    weekStart: weekStart,
                    workouts: bucket.workouts,
                    volumeKg: bucket.volume,
                    minutes: Int((bucket.seconds / 60).rounded()),
                    completedSets: bucket.sets,
                    setsByCategory: bucket.categories
                )
            }
            .sorted { $0.weekStart > $1.weekStart }
    }

    /// Riepilogo della settimana che contiene `date`, anche se vuota.
    public static func weekSummary(
        containing date: Date,
        sessions: [WorkoutSession],
        exercisesByID: [String: Exercise] = [:],
        calendar: Calendar = weekCalendar()
    ) -> WeekSummary {
        let start = startOfWeek(for: date, calendar: calendar) ?? calendar.startOfDay(for: date)
        let summaries = weeklySummaries(sessions: sessions, exercisesByID: exercisesByID, calendar: calendar)
        return summaries.first { $0.weekStart == start }
            ?? WeekSummary(weekStart: start, workouts: 0, volumeKg: 0, minutes: 0, completedSets: 0, setsByCategory: [:])
    }

    /// Numero di settimane consecutive con almeno un allenamento, guardando indietro da `date`.
    ///
    /// La settimana corrente conta se ha allenamenti; se è ancora vuota la serie
    /// non si considera interrotta e il conteggio parte dalla settimana precedente.
    public static func weekStreak(
        sessions: [WorkoutSession],
        asOf date: Date = Date(),
        calendar: Calendar = weekCalendar()
    ) -> Int {
        let weeks = Set(sessions.compactMap { startOfWeek(for: $0.startedAt, calendar: calendar) })
        guard !weeks.isEmpty, var cursor = startOfWeek(for: date, calendar: calendar) else { return 0 }

        if !weeks.contains(cursor) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }

        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Lunedì (a mezzanotte) della settimana che contiene la data.
    public static func startOfWeek(for date: Date, calendar: Calendar = weekCalendar()) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    // MARK: - Griglia di attività

    /// Griglia degli ultimi `days` giorni (incluso quello di `date`), dal più vecchio al più recente.
    public static func activityGrid(
        sessions: [WorkoutSession],
        days: Int = 30,
        asOf date: Date = Date(),
        calendar: Calendar = weekCalendar()
    ) -> [ActivityDay] {
        guard days > 0 else { return [] }

        var byDay: [Date: (workouts: Int, volume: Double)] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            var bucket = byDay[day] ?? (0, 0)
            bucket.workouts += 1
            bucket.volume += session.totalVolumeKg
            byDay[day] = bucket
        }

        let today = calendar.startOfDay(for: date)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let bucket = byDay[day] ?? (0, 0)
            return ActivityDay(date: day, workouts: bucket.workouts, volumeKg: bucket.volume)
        }
    }

    // MARK: - Serie storica per esercizio

    /// Un punto per ogni giorno in cui l'esercizio è stato allenato, dal più vecchio al più recente.
    public static func series(
        for exerciseID: String,
        in sessions: [WorkoutSession],
        calendar: Calendar = weekCalendar()
    ) -> [ExerciseDataPoint] {
        var byDay: [Date: (maxWeight: Double, best1RM: Double, volume: Double)] = [:]

        for session in sessions {
            let sets = workingSets(for: exerciseID, in: session)
            guard !sets.isEmpty else { continue }
            let day = calendar.startOfDay(for: session.startedAt)
            var bucket = byDay[day] ?? (0, 0, 0)
            bucket.maxWeight = max(bucket.maxWeight, sets.compactMap(\.weightKg).max() ?? 0)
            bucket.best1RM = max(bucket.best1RM, Stats.best1RM(in: sets) ?? 0)
            bucket.volume += sets.reduce(0) { $0 + $1.volumeKg }
            byDay[day] = bucket
        }

        return byDay
            .map { ExerciseDataPoint(date: $0.key, maxWeightKg: $0.value.maxWeight, best1RMKg: $0.value.best1RM, volumeKg: $0.value.volume) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Utilità

    /// Serie di lavoro completate di un esercizio dentro una sessione, nell'ordine originale.
    public static func workingSets(for exerciseID: String, in session: WorkoutSession) -> [SetLog] {
        session.entries
            .filter { $0.exerciseID == exerciseID }
            .flatMap(\.workingSets)
    }

    /// Durata formattata in italiano (`"1h 12m"`, `"45m"`, `"30s"`).
    public static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    /// Volume formattato con il separatore delle migliaia (`"12.4k kg"` oltre le 10 t).
    public static func formatVolume(_ kilograms: Double, unit: WeightUnit = .kg) -> String {
        let value = unit.value(fromKilograms: kilograms)
        if value >= 10_000 {
            return "\(WeightUnit.trimmedNumber(value / 1000, fractionDigits: 1))k \(unit.symbol)"
        }
        return "\(WeightUnit.trimmedNumber(value, fractionDigits: 0)) \(unit.symbol)"
    }
}
