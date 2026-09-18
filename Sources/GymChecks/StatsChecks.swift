import Foundation
import GymCore

@MainActor
func runStatsChecks(_ h: Harness) {

    let calendar = Fixtures.calendar

    /// Sessione di comodo: un solo esercizio, una serie per coppia (kg, reps).
    func session(
        _ exerciseID: String,
        at date: Date,
        sets: [(Double, Int)],
        kind: SetKind = .normal,
        minutes: Int = 60,
        completed: Bool = true
    ) -> WorkoutSession {
        let logs = sets.map { SetLog(kind: kind, weightKg: $0.0, reps: $0.1, completedAt: completed ? date : nil) }
        return WorkoutSession(
            name: "Test",
            startedAt: date,
            endedAt: date.addingTimeInterval(TimeInterval(minutes * 60)),
            entries: [SessionEntry(exerciseID: exerciseID, sets: logs)]
        )
    }

    // MARK: Volume

    h.section("stats · volume")

    h.checkClose("nessuna serie → 0", Stats.volume(of: [SetLog]()), 0)
    h.checkClose("solo warmup → 0", Stats.volume(of: [
        SetLog(kind: .warmup, weightKg: 40, reps: 10, completedAt: Date()),
        SetLog(kind: .warmup, weightKg: 60, reps: 8, completedAt: Date()),
    ]), 0)
    h.checkClose("serie non completate → 0", Stats.volume(of: [SetLog(kind: .normal, weightKg: 100, reps: 10)]), 0)
    h.checkClose("misto warmup + lavoro", Stats.volume(of: [
        SetLog(kind: .warmup, weightKg: 40, reps: 10, completedAt: Date()),
        SetLog(kind: .normal, weightKg: 100, reps: 5, completedAt: Date()),
        SetLog(kind: .drop, weightKg: 60, reps: 10, completedAt: Date()),
    ]), 500 + 600)
    h.checkClose("carico a corpo libero (0 kg) → 0", Stats.volume(of: [SetLog(kind: .normal, weightKg: 0, reps: 20, completedAt: Date())]), 0)
    h.checkClose("carico negativo ignorato", Stats.volume(of: [SetLog(kind: .normal, weightKg: -50, reps: 5, completedAt: Date())]), 0)

    let mixedSession = WorkoutSession(name: "x", entries: [
        SessionEntry(exerciseID: "a", sets: [SetLog(kind: .normal, weightKg: 100, reps: 5, completedAt: Date())]),
        SessionEntry(exerciseID: "b", sets: [SetLog(kind: .normal, weightKg: 50, reps: 10, completedAt: Date())]),
        SessionEntry(exerciseID: "a", sets: [SetLog(kind: .normal, weightKg: 80, reps: 5, completedAt: Date())]),
    ])
    h.checkClose("volume sessione", Stats.volume(of: mixedSession), 500 + 500 + 400)
    h.checkClose("volume per esercizio somma le righe ripetute", Stats.volume(of: mixedSession, exerciseID: "a"), 900)
    h.checkClose("volume di un esercizio assente", Stats.volume(of: mixedSession, exerciseID: "zzz"), 0)

    // MARK: Epley

    h.section("stats · massimale stimato (Epley)")

    h.checkClose("1 ripetizione = carico × 31/30", Stats.epley1RM(weightKg: 100, reps: 1) ?? -1, 100 * 31.0 / 30.0)
    h.checkClose("100 kg × 10", Stats.epley1RM(weightKg: 100, reps: 10) ?? -1, 133.333_333, tolerance: 0.001)
    h.checkClose("100 kg × 12 (limite superiore)", Stats.epley1RM(weightKg: 100, reps: 12) ?? -1, 140)
    h.check("13 ripetizioni → nil", Stats.epley1RM(weightKg: 100, reps: 13) == nil)
    h.check("0 ripetizioni → nil", Stats.epley1RM(weightKg: 100, reps: 0) == nil)
    h.check("ripetizioni negative → nil", Stats.epley1RM(weightKg: 100, reps: -5) == nil)
    h.check("carico 0 → nil", Stats.epley1RM(weightKg: 0, reps: 5) == nil)
    h.check("limite dichiarato = 12", Stats.maxRepsFor1RM == 12)

    h.check("warmup non produce 1RM", Stats.epley1RM(of: SetLog(kind: .warmup, weightKg: 100, reps: 5, completedAt: Date())) == nil)
    h.check("serie aperta non produce 1RM", Stats.epley1RM(of: SetLog(kind: .normal, weightKg: 100, reps: 5)) == nil)

    let repRange = [
        SetLog(kind: .normal, weightKg: 100, reps: 5, completedAt: Date()),   // 116.67
        SetLog(kind: .normal, weightKg: 90, reps: 10, completedAt: Date()),   // 120.00
        SetLog(kind: .normal, weightKg: 60, reps: 20, completedAt: Date()),   // fuori range
    ]
    h.checkClose("miglior 1RM fra più serie", Stats.best1RM(in: repRange) ?? -1, 120)
    h.checkClose("carico massimo fra più serie", Stats.maxWeight(in: repRange) ?? -1, 100)
    h.check("solo serie oltre 12 reps → nessun 1RM", Stats.best1RM(in: [SetLog(kind: .normal, weightKg: 60, reps: 20, completedAt: Date())]) == nil)
    h.check("nessuna serie → nessun 1RM", Stats.best1RM(in: []) == nil)
    h.check("nessuna serie → nessun carico massimo", Stats.maxWeight(in: []) == nil)

    // MARK: Record personali

    h.section("stats · record personali")

    let history = [
        session("0025", at: Fixtures.date(2025, 1, 6), sets: [(80, 8), (80, 8), (80, 6)]),    // vol 1_760, 1RM 101.3
        session("0025", at: Fixtures.date(2025, 1, 13), sets: [(85, 6), (85, 5), (85, 5)]),   // vol 1_360, 1RM 102
        session("0025", at: Fixtures.date(2025, 1, 20), sets: [(82.5, 10), (82.5, 9)]),       // vol 1_567.5, 1RM 110
    ]

    h.check("nessun record per un esercizio mai fatto", Stats.records(for: "9999", in: history) == nil)
    h.check("nessun record su storico vuoto", Stats.records(for: "0025", in: []) == nil)

    if let records = Stats.records(for: "0025", in: history) {
        h.checkClose("carico massimo", records.maxWeightKg, 85)
        h.check("data del carico massimo", records.maxWeightDate == Fixtures.date(2025, 1, 13))
        h.checkClose("miglior 1RM", records.best1RMKg, 82.5 * (1 + 10.0 / 30.0), tolerance: 0.001)
        h.check("data del miglior 1RM", records.best1RMDate == Fixtures.date(2025, 1, 20))
        h.checkClose("volume massimo in sessione", records.maxSessionVolumeKg, 1_760)
        h.check("data del volume massimo", records.maxSessionVolumeDate == Fixtures.date(2025, 1, 6))
    } else {
        h.fail("record non calcolati")
    }

    // Solo warmup → nessun record
    let warmupOnly = [session("0099", at: Fixtures.date(2025, 1, 6), sets: [(40, 10)], kind: .warmup)]
    h.check("storico di soli warmup → nessun record", Stats.records(for: "0099", in: warmupOnly) == nil)

    // Solo serie oltre le 12 reps: carico e volume sì, 1RM no
    let highReps = [session("0098", at: Fixtures.date(2025, 1, 6), sets: [(30, 20)])]
    if let records = Stats.records(for: "0098", in: highReps) {
        h.checkClose("oltre 12 reps: carico massimo registrato", records.maxWeightKg, 30)
        h.checkClose("oltre 12 reps: 1RM non stimabile → 0", records.best1RMKg, 0)
        h.checkClose("oltre 12 reps: volume registrato", records.maxSessionVolumeKg, 600)
    } else {
        h.fail("record con reps alte non calcolati")
    }

    // MARK: PR in tempo reale

    h.section("stats · PR in tempo reale")

    let newWeightPR = SetLog(kind: .normal, weightKg: 90, reps: 5, completedAt: Date())
    let achieved = Stats.records(for: "0025", achievedBy: newWeightPR, sessionVolumeKg: 450, history: history)
    h.check("nuovo carico massimo rilevato", achieved.contains(.maxWeight))
    h.check("nuovo carico non batte il miglior 1RM (105 < 110)", !achieved.contains(.best1RM))
    h.check("volume di sessione ancora sotto il record", !achieved.contains(.sessionVolume))

    let heavyVolume = Stats.records(for: "0025", achievedBy: newWeightPR, sessionVolumeKg: 2_000, history: history)
    h.check("nuovo volume di sessione rilevato", heavyVolume.contains(.sessionVolume))

    let weakSet = SetLog(kind: .normal, weightKg: 60, reps: 5, completedAt: Date())
    h.check("serie leggera non genera record", Stats.records(for: "0025", achievedBy: weakSet, sessionVolumeKg: 300, history: history).isEmpty)

    let warmupSet = SetLog(kind: .warmup, weightKg: 200, reps: 1, completedAt: Date())
    h.check("il warmup non genera mai record", Stats.records(for: "0025", achievedBy: warmupSet, sessionVolumeKg: 5_000, history: history).isEmpty)

    let openSet = SetLog(kind: .normal, weightKg: 200, reps: 1)
    h.check("una serie non spuntata non genera record", Stats.records(for: "0025", achievedBy: openSet, sessionVolumeKg: 5_000, history: history).isEmpty)

    let firstEver = Stats.records(for: "nuovo", achievedBy: newWeightPR, sessionVolumeKg: 450, history: history)
    h.check("prima volta assoluta → tutti i record", firstEver == [.maxWeight, .best1RM, .sessionVolume])

    let firstEverHighReps = Stats.records(
        for: "nuovo",
        achievedBy: SetLog(kind: .normal, weightKg: 30, reps: 20, completedAt: Date()),
        sessionVolumeKg: 600,
        history: history
    )
    h.check("prima volta con reps alte: nessun PR di 1RM", firstEverHighReps == [.maxWeight, .sessionVolume])

    // MARK: Prestazione precedente

    h.section("stats · prestazione precedente")

    h.check("nessuno storico → nil", Stats.previousPerformance(for: "0025", in: []) == nil)
    h.check("esercizio mai fatto → nil", Stats.previousPerformance(for: "9999", in: history) == nil)

    if let previous = Stats.previousPerformance(for: "0025", in: history) {
        h.check("prende la sessione più recente", previous.date == Fixtures.date(2025, 1, 20))
        h.check("restituisce le serie di lavoro", previous.sets.count == 2)
        h.check("testo per la colonna PRECEDENTE", previous.text(forSetAt: 0) == "82.5 × 10")
        h.check("oltre l'ultima serie ripete l'ultima", previous.text(forSetAt: 5) == "82.5 × 9")
        h.check("testo in libbre", previous.text(forSetAt: 0, unit: .lb)?.hasSuffix("× 10") == true)
    } else {
        h.fail("prestazione precedente non trovata")
    }

    if let previous = Stats.previousPerformance(for: "0025", in: history, before: Fixtures.date(2025, 1, 20)) {
        h.check("il taglio `before` esclude la sessione stessa", previous.date == Fixtures.date(2025, 1, 13))
    } else {
        h.fail("prestazione precedente con taglio non trovata")
    }
    h.check("taglio prima di ogni sessione → nil", Stats.previousPerformance(for: "0025", in: history, before: Fixtures.date(2024, 1, 1)) == nil)

    let onlyWarmupHistory = [session("0097", at: Fixtures.date(2025, 1, 6), sets: [(40, 10)], kind: .warmup)]
    h.check("storico di soli warmup → nessuna precedente", Stats.previousPerformance(for: "0097", in: onlyWarmupHistory) == nil)

    let noSets = Stats.PreviousPerformance(sessionID: UUID(), date: Date(), sets: [])
    h.check("prestazione senza serie → nessun testo", noSets.text(forSetAt: 0) == nil)

    // MARK: Settimane

    h.section("stats · aggregati settimanali")

    h.check("lunedì è l'inizio settimana", Stats.startOfWeek(for: Fixtures.date(2025, 1, 8), calendar: calendar) == Fixtures.date(2025, 1, 6, 0, 0))
    h.check("la domenica appartiene alla settimana che l'ha aperta", Stats.startOfWeek(for: Fixtures.date(2025, 1, 12, 23), calendar: calendar) == Fixtures.date(2025, 1, 6, 0, 0))

    // Settimana a cavallo dell'anno: lun 30/12/2024 → dom 05/01/2025
    let startOfNewYearWeek = Fixtures.date(2024, 12, 30, 0, 0)
    h.check("31/12/2024 e 02/01/2025 nella stessa settimana",
            Stats.startOfWeek(for: Fixtures.date(2024, 12, 31), calendar: calendar) == startOfNewYearWeek
            && Stats.startOfWeek(for: Fixtures.date(2025, 1, 2), calendar: calendar) == startOfNewYearWeek)
    h.check("06/01/2025 apre la settimana successiva",
            Stats.startOfWeek(for: Fixtures.date(2025, 1, 6), calendar: calendar) == Fixtures.date(2025, 1, 6, 0, 0))

    let exercises: [String: Exercise] = [
        "0025": Exercise(id: "0025", name: "barbell bench press", category: "chest"),
        "0043": Exercise(id: "0043", name: "barbell full squat", category: "upper legs"),
    ]

    let yearBoundary = [
        session("0025", at: Fixtures.date(2024, 12, 31), sets: [(80, 8), (80, 8)], minutes: 50),
        session("0043", at: Fixtures.date(2025, 1, 2), sets: [(100, 5)], minutes: 70),
        session("0025", at: Fixtures.date(2025, 1, 8), sets: [(85, 5)], minutes: 45),
    ]

    let summaries = Stats.weeklySummaries(sessions: yearBoundary, exercisesByID: exercises, calendar: calendar)
    h.check("due settimane distinte", summaries.count == 2)
    h.check("ordinate dalla più recente", summaries.first?.weekStart == Fixtures.date(2025, 1, 6, 0, 0))

    if let newYearWeek = summaries.first(where: { $0.weekStart == startOfNewYearWeek }) {
        h.check("settimana a cavallo d'anno: 2 allenamenti", newYearWeek.workouts == 2)
        h.checkClose("settimana a cavallo d'anno: volume", newYearWeek.volumeKg, 80 * 8 * 2 + 100 * 5)
        h.check("settimana a cavallo d'anno: minuti", newYearWeek.minutes == 120)
        h.check("settimana a cavallo d'anno: serie", newYearWeek.completedSets == 3)
        h.check("serie per gruppo muscolare", newYearWeek.setsByCategory == ["chest": 2, "upper legs": 1])
    } else {
        h.fail("settimana a cavallo d'anno non trovata")
    }

    h.check("senza libreria esercizi le categorie restano vuote",
            Stats.weeklySummaries(sessions: yearBoundary, calendar: calendar).allSatisfy { $0.setsByCategory.isEmpty })
    h.check("nessuna sessione → nessun riepilogo", Stats.weeklySummaries(sessions: [], calendar: calendar).isEmpty)

    let currentWeek = Stats.weekSummary(containing: Fixtures.date(2025, 1, 9), sessions: yearBoundary, exercisesByID: exercises, calendar: calendar)
    h.check("riepilogo della settimana richiesta", currentWeek.workouts == 1 && currentWeek.weekStart == Fixtures.date(2025, 1, 6, 0, 0))

    let emptyWeek = Stats.weekSummary(containing: Fixtures.date(2025, 6, 4), sessions: yearBoundary, calendar: calendar)
    h.check("settimana senza allenamenti → riepilogo a zero", emptyWeek.workouts == 0 && emptyWeek.volumeKg == 0)

    // MARK: Streak

    h.section("stats · streak settimanale")

    h.check("nessuna sessione → streak 0", Stats.weekStreak(sessions: [], asOf: Fixtures.date(2025, 1, 8), calendar: calendar) == 0)

    // 3 settimane consecutive a cavallo dell'anno: 30/12, 06/01, 13/01
    let consecutive = [
        session("0025", at: Fixtures.date(2024, 12, 31), sets: [(80, 8)]),
        session("0025", at: Fixtures.date(2025, 1, 8), sets: [(80, 8)]),
        session("0025", at: Fixtures.date(2025, 1, 15), sets: [(80, 8)]),
    ]
    h.check("3 settimane consecutive a cavallo d'anno", Stats.weekStreak(sessions: consecutive, asOf: Fixtures.date(2025, 1, 16), calendar: calendar) == 3)
    h.check("settimana corrente ancora vuota non spezza la serie",
            Stats.weekStreak(sessions: consecutive, asOf: Fixtures.date(2025, 1, 22), calendar: calendar) == 3)
    h.check("due settimane vuote spezzano la serie",
            Stats.weekStreak(sessions: consecutive, asOf: Fixtures.date(2025, 1, 29), calendar: calendar) == 0)

    let withGap = [
        session("0025", at: Fixtures.date(2025, 1, 8), sets: [(80, 8)]),
        session("0025", at: Fixtures.date(2025, 1, 22), sets: [(80, 8)]),
    ]
    h.check("un buco azzera la serie precedente", Stats.weekStreak(sessions: withGap, asOf: Fixtures.date(2025, 1, 22), calendar: calendar) == 1)

    // MARK: Griglia di attività

    h.section("stats · griglia attività")

    let asOf = Fixtures.date(2025, 1, 30)
    let grid = Stats.activityGrid(sessions: yearBoundary, days: 30, asOf: asOf, calendar: calendar)
    h.check("30 giorni", grid.count == 30)
    h.check("ordine crescente", zip(grid, grid.dropFirst()).allSatisfy { $0.date < $1.date })
    h.check("ultimo giorno = oggi", grid.last?.date == calendar.startOfDay(for: asOf))
    h.check("primo giorno = 29 giorni fa", grid.first?.date == calendar.startOfDay(for: Fixtures.date(2025, 1, 1)))
    h.check("giorni attivi nella finestra", grid.filter(\.isActive).count == 2)
    h.check("31/12/2024 fuori dalla finestra di 30 giorni", !grid.contains { $0.date == calendar.startOfDay(for: Fixtures.date(2024, 12, 31)) })

    if let day = grid.first(where: { $0.date == calendar.startOfDay(for: Fixtures.date(2025, 1, 2)) }) {
        h.check("giorno con allenamento", day.workouts == 1 && day.isActive)
        h.checkClose("volume del giorno", day.volumeKg, 500)
    } else {
        h.fail("giorno 02/01 non presente nella griglia")
    }

    h.check("days = 0 → griglia vuota", Stats.activityGrid(sessions: yearBoundary, days: 0, asOf: asOf, calendar: calendar).isEmpty)
    h.check("days negativo → griglia vuota", Stats.activityGrid(sessions: yearBoundary, days: -5, asOf: asOf, calendar: calendar).isEmpty)
    h.check("senza sessioni la griglia è tutta spenta",
            Stats.activityGrid(sessions: [], days: 7, asOf: asOf, calendar: calendar).allSatisfy { !$0.isActive })

    let twoSameDay = [
        session("0025", at: Fixtures.date(2025, 1, 20, 9), sets: [(80, 5)]),
        session("0025", at: Fixtures.date(2025, 1, 20, 19), sets: [(80, 5)]),
    ]
    let sameDayGrid = Stats.activityGrid(sessions: twoSameDay, days: 30, asOf: asOf, calendar: calendar)
    h.check("due sessioni nello stesso giorno si sommano", sameDayGrid.first { $0.workouts == 2 } != nil)

    // MARK: Serie storica

    h.section("stats · serie storica per esercizio")

    let series = Stats.series(for: "0025", in: history, calendar: calendar)
    h.check("un punto per giorno allenato", series.count == 3)
    h.check("ordine cronologico", zip(series, series.dropFirst()).allSatisfy { $0.date < $1.date })
    h.check("date a mezzanotte", series.allSatisfy { $0.date == calendar.startOfDay(for: $0.date) })
    h.checkClose("primo punto: carico massimo", series[0].maxWeightKg, 80)
    h.checkClose("primo punto: volume", series[0].volumeKg, 1_760)
    h.checkClose("ultimo punto: miglior 1RM", series[2].best1RMKg, 82.5 * (1 + 10.0 / 30.0), tolerance: 0.001)
    h.check("esercizio mai fatto → serie vuota", Stats.series(for: "9999", in: history, calendar: calendar).isEmpty)
    h.check("storico vuoto → serie vuota", Stats.series(for: "0025", in: [], calendar: calendar).isEmpty)
    h.check("solo warmup → serie vuota", Stats.series(for: "0099", in: warmupOnly, calendar: calendar).isEmpty)

    let sameDaySeries = Stats.series(for: "0025", in: twoSameDay, calendar: calendar)
    h.check("due sessioni nello stesso giorno danno un solo punto", sameDaySeries.count == 1)
    h.checkClose("i volumi dello stesso giorno si sommano", sameDaySeries[0].volumeKg, 800)

    // MARK: Formattazione

    h.section("stats · formattazione")

    h.check("durata in ore e minuti", Stats.formatDuration(4_320) == "1h 12m")
    h.check("durata in minuti", Stats.formatDuration(2_700) == "45m")
    h.check("durata in secondi", Stats.formatDuration(30) == "30s")
    h.check("durata zero", Stats.formatDuration(0) == "0s")
    h.check("durata negativa", Stats.formatDuration(-60) == "0s")
    h.check("volume sotto le 10 t", Stats.formatVolume(4_820) == "4820 kg")
    h.check("volume oltre le 10 t abbreviato", Stats.formatVolume(12_400) == "12.4k kg")
    h.check("volume in libbre", Stats.formatVolume(100, unit: .lb) == "220 lb")

    // MARK: Calendario

    h.section("stats · calendario")

    h.check("settimana che inizia di lunedì", Stats.weekCalendar().firstWeekday == 2)
    h.check("calendario gregoriano", Stats.weekCalendar().identifier == .gregorian)
    h.check("fuso iniettabile", Stats.weekCalendar(timeZone: .gmt).timeZone == .gmt)
}
