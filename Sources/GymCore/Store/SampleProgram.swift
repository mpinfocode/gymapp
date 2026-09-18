import Foundation

/// Scheda d'esempio Push / Pull / Legs, offerta come scorciatoia nell'empty state
/// della sezione Scheda. **Non viene creata automaticamente al primo avvio.**
///
/// Gli id sono id reali del dataset, verificati uno a uno:
/// 0025 barbell bench press · 0047 barbell incline bench press · 0405 dumbbell seated shoulder press ·
/// 0334 dumbbell lateral raise · 0201 cable pushdown · 0814 triceps dip ·
/// 0032 barbell deadlift · 0652 pull-up · 0027 barbell bent over row · 0861 cable seated row ·
/// 0031 barbell curl · 0313 dumbbell hammer curl ·
/// 0043 barbell full squat · 0085 barbell romanian deadlift · 0585 lever leg extension ·
/// 0599 lever seated leg curl · 0605 lever standing calf raise · 0464 front plank with twist.
public enum SampleProgram {

    /// Id degli esercizi usati dalla scheda d'esempio (per i check di integrità).
    public static let exerciseIDs: [String] = [
        "0025", "0047", "0405", "0334", "0201", "0814",
        "0032", "0652", "0027", "0861", "0031", "0313",
        "0043", "0085", "0585", "0599", "0605", "0464",
    ]

    /// Costruisce la scheda d'esempio: modalità a rotazione, 6 settimane, 3 giorni.
    ///
    /// - Parameter startDate: inizio della scheda (di norma oggi).
    public static func make(startDate: Date = Date(), now: Date = Date()) -> Program {
        Program(
            name: "Push / Pull / Legs",
            notes: "Scheda d'esempio su tre giorni a rotazione. Modificala pure: è solo un punto di partenza.",
            startDate: startDate,
            plannedWeeks: 6,
            mode: .rotation,
            days: [push, pull, legs],
            accent: 0,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Giorni

    private static var push: ProgramDay {
        ProgramDay(
            name: "Push",
            items: [
                item("0025", sets: 4, reps: 6...8, rest: 150, warmup: 2),  // barbell bench press
                item("0047", sets: 3, reps: 8...10, rest: 120),            // barbell incline bench press
                item("0405", sets: 3, reps: 8...10, rest: 120, warmup: 1), // dumbbell seated shoulder press
                item("0334", sets: 3, reps: 12...15, rest: 60, superset: 1), // dumbbell lateral raise
                item("0201", sets: 3, reps: 10...12, rest: 60, superset: 1), // cable pushdown
                item("0814", sets: 3, reps: 8...12, rest: 90),             // triceps dip
            ],
            note: "Petto, spalle e tricipiti."
        )
    }

    private static var pull: ProgramDay {
        ProgramDay(
            name: "Pull",
            items: [
                item("0032", sets: 3, reps: 5...6, rest: 180, warmup: 2),  // barbell deadlift
                item("0652", sets: 4, reps: 6...10, rest: 120),            // pull-up
                item("0027", sets: 4, reps: 8...10, rest: 120, warmup: 1), // barbell bent over row
                item("0861", sets: 3, reps: 10...12, rest: 90),            // cable seated row
                item("0031", sets: 3, reps: 8...10, rest: 60, superset: 1), // barbell curl
                item("0313", sets: 3, reps: 10...12, rest: 60, superset: 1), // dumbbell hammer curl
            ],
            note: "Schiena e bicipiti."
        )
    }

    private static var legs: ProgramDay {
        ProgramDay(
            name: "Legs",
            items: [
                item("0043", sets: 4, reps: 6...8, rest: 180, warmup: 2),  // barbell full squat
                item("0085", sets: 3, reps: 8...10, rest: 150),            // barbell romanian deadlift
                item("0585", sets: 3, reps: 12...15, rest: 75),            // lever leg extension
                item("0599", sets: 3, reps: 10...12, rest: 75),            // lever seated leg curl
                item("0605", sets: 4, reps: 12...15, rest: 60),            // lever standing calf raise
                timedItem("0464", sets: 3, seconds: 45, rest: 60),         // front plank with twist
            ],
            note: "Quadricipiti, femorali, glutei e polpacci."
        )
    }

    // MARK: - Helper

    private static func item(
        _ exerciseID: String,
        sets: Int,
        reps: ClosedRange<Int>,
        rest: Int,
        warmup: Int = 0,
        superset: Int? = nil
    ) -> PlanItem {
        PlanItem(
            exerciseID: exerciseID,
            targetSets: sets,
            measure: .reps(min: reps.lowerBound, max: reps.upperBound),
            warmupSets: warmup,
            restSeconds: rest,
            supersetGroup: superset
        )
    }

    private static func timedItem(_ exerciseID: String, sets: Int, seconds: Int, rest: Int) -> PlanItem {
        PlanItem(
            exerciseID: exerciseID,
            targetSets: sets,
            measure: .duration(seconds: seconds),
            restSeconds: rest
        )
    }
}
