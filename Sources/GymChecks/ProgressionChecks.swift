import Foundation
import GymCore

/// Passo di carico per attrezzo, progressione realistica, riscaldamento
/// pre-compilato e prestazione precedente per tutti i tipi di esercizio.
@MainActor
func runProgressionChecks(_ h: Harness) {

    // MARK: Passo di carico per attrezzo

    h.section("progressione · passo per attrezzo")

    h.check("bilanciere +2,5", WeightStep.step(forEquipment: "barbell") == 2.5)
    h.check("bilanciere olimpico +2,5", WeightStep.step(forEquipment: "olympic barbell") == 2.5)
    h.check("ez +2,5", WeightStep.step(forEquipment: "ez barbell") == 2.5)
    h.check("trap bar +2,5", WeightStep.step(forEquipment: "trap bar") == 2.5)
    h.check("multipower +2,5", WeightStep.step(forEquipment: "smith machine") == 2.5)
    h.check("manubri +2 (per manubrio)", WeightStep.step(forEquipment: "dumbbell") == 2)
    h.check("kettlebell +4", WeightStep.step(forEquipment: "kettlebell") == 4)
    h.check("cavi +5 a carico pieno", WeightStep.step(forEquipment: "cable", currentWeightKg: 40) == 5)
    h.check("cavi +2,5 sotto i 20 kg", WeightStep.step(forEquipment: "cable", currentWeightKg: 15) == 2.5)
    h.check("soglia dei 20 kg inclusa nel passo grande", WeightStep.step(forEquipment: "cable", currentWeightKg: 20) == 5)
    h.check("macchine a leve +5", WeightStep.step(forEquipment: "leverage machine", currentWeightKg: 60) == 5)
    h.check("slitta +5", WeightStep.step(forEquipment: "sled machine", currentWeightKg: 60) == 5)
    h.check("corpo libero senza passo", WeightStep.step(forEquipment: "body weight") == nil)
    h.check("elastici senza passo", WeightStep.step(forEquipment: "band") == nil)
    h.check("elastici di resistenza senza passo", WeightStep.step(forEquipment: "resistance band") == nil)
    h.check("attrezzo sconosciuto: passo standard", WeightStep.step(forEquipment: "attrezzo inventato") == 2.5)
    h.check("attrezzo vuoto: passo standard", WeightStep.step(forEquipment: "") == 2.5)
    h.check("maiuscole e spazi ignorati", WeightStep.step(forEquipment: "  DUMBBELL ") == 2)

    h.check("famiglia del bilanciere", WeightStep.kind(forEquipment: "smith machine") == .barbell)
    h.check("famiglia dei manubri", WeightStep.kind(forEquipment: "dumbbell") == .dumbbell)
    h.check("famiglia del pacco piastre", WeightStep.kind(forEquipment: "cable") == .stack)
    h.check("famiglia del corpo libero", WeightStep.kind(forEquipment: "body weight") == .bodyweight)
    h.check("nomi italiani delle famiglie", WeightStep.Kind.dumbbell.displayName == "Manubri")
    h.check("solo corpo libero ed elastici progrediscono a ripetizioni",
            WeightStep.progressesByReps(forEquipment: "body weight")
            && !WeightStep.progressesByReps(forEquipment: "dumbbell"))

    h.checkClose("manubri: 21,25 kg arrotondato a 22", WeightStep.round(21.25, forEquipment: "dumbbell"), 22)
    h.checkClose("bilanciere: 81,3 kg arrotondato a 82,5", WeightStep.round(81.3, forEquipment: "barbell"), 82.5)
    h.checkClose("kettlebell: 18 kg arrotondato a 20", WeightStep.round(18, forEquipment: "kettlebell"), 20)
    h.checkClose("corpo libero: nessun arrotondamento", WeightStep.round(13.7, forEquipment: "body weight"), 13.7)

    h.checkClose("+ sul bilanciere", WeightStep.next(after: 80, forEquipment: "barbell") ?? -1, 82.5)
    h.checkClose("+ sui manubri", WeightStep.next(after: 12, forEquipment: "dumbbell") ?? -1, 14)
    h.checkClose("+ da un carico fuori passo", WeightStep.next(after: 21.25, forEquipment: "dumbbell") ?? -1, 22)
    h.checkClose("- sul bilanciere", WeightStep.previous(before: 82.5, forEquipment: "barbell") ?? -1, 80)
    h.checkClose("- da un carico fuori passo", WeightStep.previous(before: 21.25, forEquipment: "dumbbell") ?? -1, 20)
    h.check("- non scende sotto lo zero", WeightStep.previous(before: 2, forEquipment: "dumbbell") == nil)
    h.check("+ e - non esistono a corpo libero",
            WeightStep.next(after: 10, forEquipment: "body weight") == nil
            && WeightStep.previous(before: 10, forEquipment: "body weight") == nil)

    // MARK: Suggerimento di progressione

    h.section("progressione · suggerimento realistico")

    let date = Fixtures.date(2025, 5, 12)
    func session(_ exerciseID: String, _ sets: [(Double?, Int)]) -> WorkoutSession {
        WorkoutSession(
            name: "x",
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            entries: [SessionEntry(
                exerciseID: exerciseID,
                sets: sets.map { SetLog(kind: .normal, weightKg: $0.0, reps: $0.1, completedAt: date) }
            )]
        )
    }

    let item = PlanItem(exerciseID: "0025", targetSets: 3, measure: .reps(min: 6, max: 8))

    if let suggestion = Stats.progressionSuggestion(
        for: item, lastSession: session("0025", [(12, 8), (12, 8), (12, 8)]), equipment: "dumbbell"
    ) {
        h.check("manubri: progressione a carico", suggestion.kind == .weight)
        h.checkClose("manubri: +2 kg", suggestion.incrementKg, 2)
        h.checkClose("manubri: nuovo carico", suggestion.suggestedWeightKg, 14)
        h.check("manubri: niente 21,25 kg nel testo", suggestion.reason.contains("14 kg"))
        h.check("manubri: nessuna proposta di ripetizioni", suggestion.suggestedReps == nil)
    } else {
        h.fail("nessun suggerimento sui manubri")
    }

    if let suggestion = Stats.progressionSuggestion(
        for: item, lastSession: session("0025", [(16, 8), (16, 8), (16, 8)]), equipment: "kettlebell"
    ) {
        h.checkClose("kettlebell: +4 kg", suggestion.incrementKg, 4)
        h.checkClose("kettlebell: campana successiva", suggestion.suggestedWeightKg, 20)
    } else {
        h.fail("nessun suggerimento sul kettlebell")
    }

    if let suggestion = Stats.progressionSuggestion(
        for: item, lastSession: session("0025", [(40, 8), (40, 8), (40, 8)]), equipment: "cable"
    ) {
        h.checkClose("cavi: +5 kg", suggestion.incrementKg, 5)
        h.checkClose("cavi: nuova piastra", suggestion.suggestedWeightKg, 45)
    } else {
        h.fail("nessun suggerimento sui cavi")
    }

    if let suggestion = Stats.progressionSuggestion(
        for: item, lastSession: session("0025", [(15, 8), (15, 8), (15, 8)]), equipment: "cable"
    ) {
        h.checkClose("cavi leggeri: +2,5 kg", suggestion.incrementKg, 2.5)
        h.checkClose("cavi leggeri: nuovo carico", suggestion.suggestedWeightKg, 17.5)
    } else {
        h.fail("nessun suggerimento sui cavi leggeri")
    }

    if let suggestion = Stats.progressionSuggestion(
        for: item, lastSession: session("0025", [(81.3, 8), (81.3, 8), (81.3, 8)]), equipment: "barbell"
    ) {
        h.checkClose("carico fuori passo: si risale al multiplo successivo", suggestion.suggestedWeightKg, 82.5)
    } else {
        h.fail("nessun suggerimento da carico fuori passo")
    }

    if let suggestion = Stats.progressionSuggestion(
        for: item, lastSession: session("0025", [(nil, 8), (nil, 8), (nil, 8)]), equipment: "body weight"
    ) {
        h.check("corpo libero: progressione a ripetizioni", suggestion.kind == .reps)
        h.check("corpo libero: una ripetizione in più", suggestion.suggestedReps == 9)
        h.checkClose("corpo libero: nessun incremento di carico", suggestion.incrementKg, 0)
        h.checkClose("corpo libero: carico invariato", suggestion.suggestedWeightKg, 0)
        h.check("corpo libero: motivazione a ripetizioni",
                suggestion.reason.contains("9 ripetizioni") && !suggestion.reason.contains("kg"))
    } else {
        h.fail("nessun suggerimento a corpo libero")
    }

    if let suggestion = Stats.progressionSuggestion(
        for: item, lastSession: session("0025", [(10, 8), (10, 8), (10, 8)]), equipment: "band"
    ) {
        h.check("elastici: progressione a ripetizioni", suggestion.kind == .reps)
        h.check("elastici: il carico usato resta citato", suggestion.reason.contains("10 kg"))
    } else {
        h.fail("nessun suggerimento con gli elastici")
    }

    h.check("il range non completato non dà suggerimenti a corpo libero",
            Stats.progressionSuggestion(
                for: item, lastSession: session("0025", [(nil, 8), (nil, 7), (nil, 8)]), equipment: "body weight"
            ) == nil)
    h.check("esercizio a tempo: nessun suggerimento",
            Stats.progressionSuggestion(
                for: PlanItem(exerciseID: "0025", targetSets: 2, measure: .duration(seconds: 45)),
                lastSession: session("0025", [(nil, 8), (nil, 8)]),
                equipment: "body weight"
            ) == nil)

    // MARK: Riscaldamento pre-compilato

    h.section("progressione · carico di riscaldamento")

    h.checkClose("bilanciere: 55% di 80 kg arrotondato", Stats.warmupWeight(forWorkingWeightKg: 80, equipment: "barbell") ?? -1, 45)
    h.checkClose("bilanciere: 55% di 100 kg", Stats.warmupWeight(forWorkingWeightKg: 100, equipment: "barbell") ?? -1, 55)
    h.checkClose("manubri: 55% di 24 kg al passo da 2", Stats.warmupWeight(forWorkingWeightKg: 24, equipment: "dumbbell") ?? -1, 14)
    h.checkClose("cavi: 55% di 60 kg al passo da 5", Stats.warmupWeight(forWorkingWeightKg: 60, equipment: "cable") ?? -1, 35)
    h.check("il riscaldamento sta sotto il carico di lavoro",
            (Stats.warmupWeight(forWorkingWeightKg: 80, equipment: "barbell") ?? 999) < 80)
    h.check("senza carico di riferimento resta vuoto", Stats.warmupWeight(forWorkingWeightKg: nil, equipment: "barbell") == nil)
    h.check("carico zero resta vuoto", Stats.warmupWeight(forWorkingWeightKg: 0, equipment: "barbell") == nil)
    h.check("a corpo libero resta vuoto", Stats.warmupWeight(forWorkingWeightKg: 40, equipment: "body weight") == nil)
    h.check("carico troppo piccolo per scaldare resta vuoto",
            Stats.warmupWeight(forWorkingWeightKg: 2, equipment: "dumbbell") == nil)
    h.check("quota dichiarata fra 50% e 60%", Stats.warmupRatio >= 0.5 && Stats.warmupRatio <= 0.6)

    // MARK: Prestazione precedente per tutti i tipi di esercizio

    h.section("progressione · precedente a durata e corpo libero")

    let plankDate = Fixtures.date(2025, 5, 5)
    let timed = WorkoutSession(
        name: "core",
        startedAt: plankDate,
        endedAt: plankDate.addingTimeInterval(1_800),
        entries: [SessionEntry(exerciseID: "0464", measureKind: .duration, sets: [
            SetLog(kind: .warmup, durationSec: 20, completedAt: plankDate),
            SetLog(kind: .normal, durationSec: 45, completedAt: plankDate),
            SetLog(kind: .normal, durationSec: 90, completedAt: plankDate),
            SetLog(kind: .normal, durationSec: 60),
        ])]
    )
    if let previous = Stats.previousPerformance(for: "0464", in: [timed]) {
        h.check("esercizio a tempo: due serie completate", previous.sets.count == 2)
        h.check("esercizio a tempo: il riscaldamento resta fuori", previous.sets.allSatisfy { $0.kind == .normal })
        h.check("esercizio a tempo: testo in secondi", previous.text(forSetAt: 0) == "45s")
        h.check("esercizio a tempo: testo oltre il minuto", previous.text(forSetAt: 1) == "1:30")
    } else {
        h.fail("prestazione precedente a tempo non trovata")
    }

    let bodyweightDate = Fixtures.date(2025, 5, 6)
    let bodyweight = WorkoutSession(
        name: "pull",
        startedAt: bodyweightDate,
        endedAt: bodyweightDate.addingTimeInterval(1_800),
        entries: [SessionEntry(exerciseID: "0662", sets: [
            SetLog(kind: .normal, reps: 12, completedAt: bodyweightDate),
            SetLog(kind: .normal, weightKg: 0, reps: 10, completedAt: bodyweightDate),
        ])]
    )
    if let previous = Stats.previousPerformance(for: "0662", in: [bodyweight]) {
        h.check("corpo libero: entrambe le serie contano", previous.sets.count == 2)
        h.check("corpo libero: testo con le sole ripetizioni", previous.text(forSetAt: 0) == "12 rip.")
        h.check("corpo libero: il carico zero non inventa un peso", previous.text(forSetAt: 1) == "10 rip.")
    } else {
        h.fail("prestazione precedente a corpo libero non trovata")
    }

    let weightedPlankDate = Fixtures.date(2025, 5, 7)
    let weightedPlank = WorkoutSession(
        name: "core",
        startedAt: weightedPlankDate,
        endedAt: weightedPlankDate.addingTimeInterval(900),
        entries: [SessionEntry(exerciseID: "0465", measureKind: .duration, sets: [
            SetLog(kind: .normal, weightKg: 10, durationSec: 45, completedAt: weightedPlankDate),
        ])]
    )
    if let previous = Stats.previousPerformance(for: "0465", in: [weightedPlank]) {
        h.check("durata con zavorra: carico e tempo", previous.text(forSetAt: 0) == "10 × 45s")
    } else {
        h.fail("prestazione precedente con zavorra non trovata")
    }

    h.check("una serie senza nulla non produce testo",
            Stats.performanceText(for: SetLog(kind: .normal, completedAt: bodyweightDate)) == nil)
    h.check("il volume ignora le serie senza carico", Stats.volume(of: bodyweight) == 0)
    h.check("le serie senza carico non diventano record", Stats.records(for: "0662", in: [bodyweight]) == nil)
    h.check("serie a corpo libero contata come svolta",
            SetLog(kind: .normal, reps: 10, completedAt: bodyweightDate).isLoggedSet)
    h.check("serie a corpo libero non è una serie di lavoro",
            !SetLog(kind: .normal, reps: 10, completedAt: bodyweightDate).isWorkingSet)
    h.check("il riscaldamento non è mai una serie svolta",
            !SetLog(kind: .warmup, weightKg: 40, reps: 10, completedAt: bodyweightDate).isLoggedSet)
    h.check("una serie non spuntata non è svolta", !SetLog(kind: .normal, reps: 10).isLoggedSet)
}
