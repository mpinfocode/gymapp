import Foundation
import GymCore

/// Cronologia dei record nel tempo, aggregato degli esercizi migliorati e
/// ricostruzione dei badge PR di una sessione in corso.
@MainActor
func runRecordHistoryChecks(_ h: Harness) {

    func session(
        _ exerciseID: String,
        at date: Date,
        _ sets: [(Double, Int)],
        kind: SetKind = .normal
    ) -> WorkoutSession {
        WorkoutSession(
            name: "x",
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            entries: [SessionEntry(
                exerciseID: exerciseID,
                sets: sets.map { SetLog(kind: kind, weightKg: $0.0, reps: $0.1, completedAt: date) }
            )]
        )
    }

    // MARK: Cronologia dei record

    h.section("record · cronologia nel tempo")

    let d1 = Fixtures.date(2025, 1, 6)
    let d2 = Fixtures.date(2025, 1, 13)
    let d3 = Fixtures.date(2025, 1, 20)
    let d4 = Fixtures.date(2025, 2, 3)

    let history = [
        session("0025", at: d1, [(80, 8), (80, 8)]),
        session("0025", at: d2, [(80, 8), (82.5, 6)]),
        session("0025", at: d3, [(82.5, 8)]),
        session("0025", at: d4, [(85, 5)]),
    ]

    let events = Stats.recordHistory(in: history)
    h.check("la prima comparsa non è un record", !events.contains { $0.date == d1 })
    h.check("un record per sessione che migliora", events.count == 2)
    h.check("ordinati dal più recente", events.first?.date == d4)
    h.check("il pareggio non è un record", !events.contains { $0.date == d3 })

    if let latest = events.first {
        h.check("esercizio del record", latest.exerciseID == "0025")
        h.check("tipo di record", latest.kind == .maxWeight)
        h.checkClose("valore del record", latest.value, 85)
        h.checkClose("valore precedente", latest.previousValue, 82.5)
        h.checkClose("miglioramento", latest.improvement, 2.5)
        h.check("record legato alla sua sessione", latest.sessionID == history[3].id)
        h.check("id stabile", latest.id == "\(history[3].id.uuidString)-0025-maxWeight")
    } else {
        h.fail("nessun record nella cronologia")
    }

    h.check("storico vuoto → nessun record", Stats.recordHistory(in: []).isEmpty)
    h.check("nessun tipo richiesto → nessun record", Stats.recordHistory(in: history, kinds: []).isEmpty)
    h.check("un solo allenamento non produce record", Stats.recordHistory(in: [history[0]]).isEmpty)
    h.check("l'ordine di ingresso non conta",
            Stats.recordHistory(in: history.reversed()).map(\.id) == events.map(\.id))

    let warmupOnly = [
        session("0099", at: d1, [(40, 10)], kind: .warmup),
        session("0099", at: d2, [(60, 10)], kind: .warmup),
    ]
    h.check("le serie di riscaldamento non fanno record", Stats.recordHistory(in: warmupOnly).isEmpty)

    let notCompleted = [
        session("0098", at: d1, [(80, 8)]),
        WorkoutSession(name: "x", startedAt: d2, endedAt: d2, entries: [
            SessionEntry(exerciseID: "0098", sets: [SetLog(kind: .normal, weightKg: 100, reps: 5)]),
        ]),
    ]
    h.check("le serie non spuntate non fanno record", Stats.recordHistory(in: notCompleted).isEmpty)

    // Più tipi di record insieme: 60×10 → 70×10 batte carico, massimale e volume.
    let allKinds: Set<Stats.RecordKind> = [.maxWeight, .best1RM, .sessionVolume]
    let growing = [
        session("0077", at: d1, [(60, 10)]),
        session("0077", at: d2, [(70, 10)]),
    ]
    let multi = Stats.recordHistory(in: growing, kinds: allKinds)
    h.check("tre record nella stessa sessione", multi.count == 3)
    h.check("i tipi richiesti sono tutti rappresentati", Set(multi.map(\.kind)) == allKinds)
    h.check("tutti nella sessione che ha migliorato", multi.allSatisfy { $0.date == d2 })
    h.check("un solo tipo se si chiede solo quello",
            Stats.recordHistory(in: growing, kinds: [.sessionVolume]).count == 1)

    if let volumeRecord = multi.first(where: { $0.kind == .sessionVolume }) {
        h.checkClose("volume di sessione record", volumeRecord.value, 700)
        h.checkClose("volume di sessione precedente", volumeRecord.previousValue, 600)
    } else {
        h.fail("record di volume non trovato")
    }
    if let oneRM = multi.first(where: { $0.kind == .best1RM }) {
        h.checkClose("massimale stimato record", oneRM.value, 70 * (1 + 10.0 / 30.0), tolerance: 0.001)
        h.checkClose("massimale stimato precedente", oneRM.previousValue, 60 * (1 + 10.0 / 30.0), tolerance: 0.001)
    } else {
        h.fail("record di massimale non trovato")
    }
    h.check("a parità di data l'ordine dei tipi è stabile",
            multi.map(\.kind) == [.maxWeight, .best1RM, .sessionVolume])

    // MARK: Esercizi migliorati nel periodo

    h.section("record · esercizi migliorati")

    let twoExercises = history + [
        session("0043", at: d2, [(100, 5)]),
        session("0043", at: d3, [(110, 5)]),
        session("0043", at: d4, [(120, 5)]),
    ]
    let all = Stats.recordHistory(in: twoExercises)
    h.check("record di due esercizi", Set(all.map(\.exerciseID)) == ["0025", "0043"])

    let improved = Stats.improvedExercises(in: twoExercises)
    h.check("un solo record per esercizio", improved.count == 2)
    h.check("esercizi migliorati senza duplicati", Set(improved.map(\.exerciseID)).count == improved.count)
    h.check("di ogni esercizio si tiene il più recente",
            improved.first { $0.exerciseID == "0043" }?.date == d4)
    h.checkClose("valore del più recente", improved.first { $0.exerciseID == "0043" }?.value ?? 0, 120)

    let inWindow = Stats.improvedExercises(in: twoExercises, from: d3, to: d3)
    h.check("finestra temporale rispettata", inWindow.count == 1 && inWindow[0].exerciseID == "0043")
    h.check("estremi della finestra inclusi", inWindow[0].date == d3)
    h.check("finestra senza record → vuoto",
            Stats.improvedExercises(in: twoExercises, from: Fixtures.date(2026, 1, 1)).isEmpty)
    h.check("aggregato su storico vuoto", Stats.improvedExercises(in: []).isEmpty)
    h.check("latestPerExercise coerente con l'aggregato",
            Stats.latestPerExercise(all).map(\.id) == improved.map(\.id))

    let bySession = Stats.records(inSession: twoExercises[0].id, entries: all)
    h.check("record della prima sessione: nessuno", bySession.isEmpty)
    let lastSessionRecords = Stats.records(inSession: history[3].id, entries: all)
    h.check("record di una sessione per esercizio", lastSessionRecords.count == 1)
    h.checkClose("carico del record di sessione", lastSessionRecords["0025"]?.value ?? 0, 85)

    // MARK: Ricostruzione dei badge PR

    h.section("record · badge PR ricostruibili")

    let liveDate = Fixtures.date(2025, 2, 10)
    let active = WorkoutSession(
        name: "Push",
        startedAt: liveDate,
        entries: [SessionEntry(exerciseID: "0025", sets: [
            SetLog(kind: .warmup, weightKg: 45, reps: 8, completedAt: liveDate),
            SetLog(kind: .normal, weightKg: 87.5, reps: 5, completedAt: liveDate.addingTimeInterval(200)),
            SetLog(kind: .normal, weightKg: 87.5, reps: 5, completedAt: liveDate.addingTimeInterval(400)),
            SetLog(kind: .normal, weightKg: 90, reps: 5, completedAt: liveDate.addingTimeInterval(600)),
            SetLog(kind: .normal, weightKg: 92.5, reps: 5),
        ])]
    )
    let sets = active.entries[0].sets
    let rebuilt = Stats.liveRecords(in: active, history: history)

    h.check("il riscaldamento non prende badge", rebuilt[sets[0].id] == nil)
    h.check("la prima serie che batte lo storico è un PR", rebuilt[sets[1].id]?.contains(.maxWeight) == true)
    h.check("la serie uguale della stessa sessione non è un nuovo PR", rebuilt[sets[2].id]?.contains(.maxWeight) != true)
    h.check("la serie più pesante è di nuovo un PR", rebuilt[sets[3].id]?.contains(.maxWeight) == true)
    h.check("la serie più pesante batte anche massimale e volume",
            rebuilt[sets[3].id] == [.maxWeight, .best1RM, .sessionVolume])
    h.check("le serie non spuntate non hanno badge", rebuilt[sets[4].id] == nil)
    h.check("solo le serie con record compaiono", rebuilt.count == 2)
    h.check("ricostruzione deterministica", Stats.liveRecords(in: active, history: history) == rebuilt)
    h.check("sessione senza serie spuntate → nessun badge",
            Stats.liveRecords(in: WorkoutSession(name: "vuota", startedAt: liveDate), history: history).isEmpty)

    // Stesso esito del calcolo in tempo reale, serie per serie.
    var live: [UUID: Set<Stats.RecordKind>] = [:]
    var replayed = WorkoutSession(
        name: "Push",
        startedAt: liveDate,
        entries: [SessionEntry(exerciseID: "0025", sets: sets.map { original in
            SetLog(id: original.id, kind: original.kind, weightKg: original.weightKg, reps: original.reps)
        })]
    )
    for (index, original) in sets.enumerated() where original.isCompleted {
        replayed.entries[0].sets[index].completedAt = original.completedAt
        let achieved = Stats.records(
            for: "0025",
            achievedBy: replayed.entries[0].sets[index],
            sessionVolumeKg: Stats.volume(of: replayed, exerciseID: "0025"),
            history: history,
            earlierSetsInSession: Stats.workingSets(for: "0025", in: replayed)
        )
        if !achieved.isEmpty { live[original.id] = achieved }
    }
    h.check("ricostruzione identica al calcolo live", rebuilt == live)

    // Ordine di completamento diverso dall'ordine in tabella
    let outOfOrder = WorkoutSession(
        name: "Push",
        startedAt: liveDate,
        entries: [SessionEntry(exerciseID: "0025", sets: [
            SetLog(kind: .normal, weightKg: 90, reps: 5, completedAt: liveDate.addingTimeInterval(600)),
            SetLog(kind: .normal, weightKg: 87.5, reps: 5, completedAt: liveDate.addingTimeInterval(200)),
        ])]
    )
    let outOfOrderRecords = Stats.liveRecords(in: outOfOrder, history: history)
    h.check("conta l'ordine di completamento, non quello in tabella",
            outOfOrderRecords[outOfOrder.entries[0].sets[1].id]?.contains(.maxWeight) == true
            && outOfOrderRecords[outOfOrder.entries[0].sets[0].id]?.contains(.maxWeight) == true)

    // Senza storico la prima serie valida è comunque un badge (come in palestra).
    let firstEver = Stats.liveRecords(in: active, history: [])
    h.check("senza storico la prima serie è un record", firstEver[sets[1].id]?.contains(.maxWeight) == true)
}
