import Foundation
import GymCore

/// Verifica di `Stats.muscleDistribution(...)`: pesi di principale e secondari,
/// ordinamento, arrotondamenti che devono sommare a 100, zone mai allenate e zone
/// allenate solo di riflesso, esercizi personalizzati e sconosciuti.
///
/// **Cambio di regola (2026-09-18).** Fino a oggi questi check dichiaravano che "i
/// muscoli secondari NON contano". Ora contano: 1,0 al principale, 0,5 a ogni
/// secondario sinergista, 0,25 a ogni stabilizzatore. I check che codificavano la
/// vecchia regola sono stati riscritti, non tolti: ognuno ha il suo corrispettivo
/// qui sotto, e la vecchia regola resta verificabile passando `includesSecondary: false`.
@MainActor
func runMuscleDistributionChecks(_ h: Harness, repository: ExerciseRepository?) {

    // MARK: Esercizi finti, uno per gruppo, per controllare l'aritmetica senza dataset.

    func fake(_ id: String, target: String, category: String = "", secondary: [String] = []) -> Exercise {
        Exercise(id: id, name: id, category: category, target: target, secondaryMuscles: secondary)
    }

    let library: [String: Exercise] = [
        "chest": fake("chest", target: "pectorals"),
        "back": fake("back", target: "lats"),
        "shoulders": fake("shoulders", target: "delts"),
        "biceps": fake("biceps", target: "biceps"),
        "triceps": fake("triceps", target: "triceps"),
        "quads": fake("quads", target: "quads"),
        "abs": fake("abs", target: "abs"),
        "custom-1": Exercise(id: "custom-1", name: "Face pull", category: "shoulders",
                             target: "rear deltoids", isCustom: true),
        // Con secondari, per i pesi 1 / 0,5 / 0,25.
        "panca": Exercise(id: "panca", name: "panca piana", target: "pectorals",
                          secondaryMuscles: ["triceps", "shoulders"]),
        "lento": Exercise(id: "lento", name: "lento avanti", target: "delts",
                          secondaryMuscles: ["triceps", "upper back"]),
        // `upper back` e `rhomboids` sono la stessa zona del target: contano una volta
        // sola come duplicato del principale, cioè zero.
        "rematore": Exercise(id: "rematore", name: "rematore", target: "lats",
                             secondaryMuscles: ["biceps", "rhomboids", "upper back", "biceps"]),
        // Sei secondari: due sinergisti, poi gli stabilizzatori. Ne entrano tre.
        "affollato": Exercise(id: "affollato", name: "affollato", target: "quads",
                              secondaryMuscles: ["glutes", "hamstrings", "core", "calves", "lower back"]),
    ]

    func item(_ exerciseID: String, sets: Int, warmup: Int = 0) -> PlanItem {
        PlanItem(exerciseID: exerciseID, targetSets: sets, warmupSets: warmup)
    }

    func day(_ name: String, _ items: [PlanItem]) -> ProgramDay {
        ProgramDay(name: name, items: items)
    }

    func distribution(_ items: [PlanItem]) -> Stats.MuscleDistribution {
        Stats.muscleDistribution(items: items) { library[$0] }
    }

    /// Distribuzione alla vecchia maniera: solo il muscolo principale.
    func primaryOnly(_ items: [PlanItem]) -> Stats.MuscleDistribution {
        Stats.muscleDistribution(items: items, includesSecondary: false) { library[$0] }
    }

    // MARK: Pesi e serie di riscaldamento

    h.section("muscoli · pesi")

    let basic = distribution([
        item("chest", sets: 4, warmup: 2),
        item("back", sets: 6, warmup: 3),
    ])
    h.check("il totale conta solo le serie di lavoro", basic.totalSets == 10)
    h.check("il riscaldamento non pesa", basic.sets(of: .chest) == 4 && basic.sets(of: .back) == 6)
    h.check("ordinate per quota decrescente", basic.shares.map(\.group) == [.back, .chest])
    h.check("percentuali 60 e 40", basic.percent(of: .back) == 60 && basic.percent(of: .chest) == 40)
    h.checkClose("frazione esatta del petto", basic.shares[1].fraction, 0.4)

    let zeroSets = distribution([item("chest", sets: 0, warmup: 3)])
    h.check("una voce a zero serie non entra", zeroSets.isEmpty && zeroSets.totalSets == 0)

    h.check("i pesi pubblici sono 1 · 0,5 · 0,25",
            Stats.directWeight == 1 && Stats.synergistWeight == 0.5 && Stats.stabilizerWeight == 0.25)
    h.check("al massimo tre secondari per esercizio", SecondaryMuscles.maximumPerExercise == 3)

    // MARK: Secondari: l'esempio numerico verificabile a mano
    //
    // Giorno con 4 serie di panca + 3 di lento avanti.
    //   panca (Petto) → tricipiti e spalle sinergisti
    //     Petto 4 × 1     = 4,0 diretto
    //     Tricipiti 4 × 0,5 = 2,0 · Spalle 4 × 0,5 = 2,0
    //   lento (Spalle) → tricipiti sinergisti, dorso alto stabilizzatore (postura)
    //     Spalle 3 × 1    = 3,0 diretto
    //     Tricipiti 3 × 0,5 = 1,5 · Dorso 3 × 0,25 = 0,75
    // Totale pesato 4,0 + 5,0 + 3,5 + 0,75 = 13,25
    // Percentuali (resto maggiore): Spalle 38 · Petto 30 · Tricipiti 26 · Dorso 6.

    h.section("muscoli · secondari")

    let pushDay = distribution([item("panca", sets: 4, warmup: 2), item("lento", sets: 3)])
    h.check("Petto: 4,0 dirette e niente indiretto",
            pushDay.directSets(of: .chest) == 4 && pushDay.indirectSets(of: .chest) == 0)
    h.check("Spalle: 3,0 dirette + 2,0 indirette",
            pushDay.directSets(of: .shoulders) == 3 && pushDay.indirectSets(of: .shoulders) == 2)
    h.check("Tricipiti: 3,5 solo indirette",
            pushDay.directSets(of: .triceps) == 0 && pushDay.indirectSets(of: .triceps) == 3.5)
    h.check("Dorso: 0,75 indirette (stabilizzatore del lento)",
            pushDay.indirectSets(of: .back) == 0.75)
    h.checkClose("totale pesato 13,25", pushDay.totalWeightedSets, 13.25)
    h.check("le serie vere restano 7", pushDay.totalSets == 7)
    h.check("ordine per quota pesata", pushDay.shares.map(\.group) == [.shoulders, .chest, .triceps, .back])
    h.check("percentuali 38 · 30 · 26 · 6", pushDay.shares.map(\.percent) == [38, 30, 26, 6])
    h.check("le percentuali sommano a 100", pushDay.shares.reduce(0) { $0 + $1.percent } == 100)
    h.check("Tricipiti e Dorso sono allenati solo indirettamente",
            pushDay.indirectOnlyGroups == [.back, .triceps])
    h.check("le zone di gamba non sono allenate affatto",
            pushDay.neverTrainedGroups == [.biceps, .quads, .hamstrings, .glutes, .calves, .abs])
    h.check("missingGroups resta un alias di neverTrainedGroups",
            pushDay.missingGroups == pushDay.neverTrainedGroups)

    // Lo stesso giorno con la regola vecchia: solo il principale.
    let pushDayPrimaryOnly = primaryOnly([item("panca", sets: 4), item("lento", sets: 3)])
    h.check("senza secondari restano solo Petto e Spalle",
            pushDayPrimaryOnly.shares.map(\.group) == [.chest, .shoulders])
    h.check("senza secondari il totale pesato è il numero di serie",
            pushDayPrimaryOnly.totalWeightedSets == 7)
    h.check("senza secondari i Tricipiti tornano fra i mai allenati",
            pushDayPrimaryOnly.neverTrainedGroups.contains(.triceps)
                && pushDayPrimaryOnly.indirectOnlyGroups.isEmpty)

    // Uno stesso gruppo citato due volte fra i secondari conta una volta sola.
    let repeated = distribution([item("rematore", sets: 4)])
    h.check("secondari nello stesso gruppo contano una volta sola",
            repeated.indirectSets(of: .biceps) == 2)
    h.check("il duplicato del principale non conta", repeated.directSets(of: .back) == 4
            && repeated.indirectSets(of: .back) == 0)

    // Più di tre secondari: si tengono i tre più rilevanti (prima i sinergisti).
    let crowded = distribution([item("affollato", sets: 2)])
    h.check("al massimo tre secondari entrano nel conto", crowded.shares.count == 4)
    h.check("i sinergisti hanno la precedenza sugli stabilizzatori",
            crowded.indirectSets(of: .glutes) == 1 && crowded.indirectSets(of: .hamstrings) == 1
                && crowded.indirectSets(of: .abs) == 0.5 && crowded.indirectSets(of: .calves) == 0)

    // MARK: Scheda vuota

    h.section("muscoli · scheda vuota")

    let emptyProgram = Program(name: "Vuota", days: [day("A", []), day("B", [])])
    let emptyDistribution = Stats.muscleDistribution(of: emptyProgram) { library[$0] }
    h.check("scheda senza esercizi → vuota", emptyDistribution.isEmpty)
    h.check("scheda vuota → totale 0", emptyDistribution.totalSets == 0)
    h.check("scheda vuota → mancano tutte le zone rilevanti",
            emptyDistribution.missingGroups == Stats.relevantMuscleGroups)
    h.check("scheda vuota → nessuna macro area", emptyDistribution.macroAreas.isEmpty)
    h.check("Stats.MuscleDistribution.empty coerente", Stats.MuscleDistribution.empty.isEmpty)

    // MARK: Personalizzati ed esercizi sconosciuti

    h.section("muscoli · personalizzati e sconosciuti")

    let mixed = distribution([
        item("custom-1", sets: 3),
        item("shoulders", sets: 5),
        item("0000-non-esiste", sets: 4),
    ])
    h.check("l'esercizio personalizzato porta il suo gruppo", mixed.sets(of: .shoulders) == 8)
    h.check("l'esercizio sconosciuto è escluso dal totale", mixed.totalSets == 8)
    h.check("le sue serie sono contate a parte", mixed.unresolvedSets == 4 && mixed.unresolvedItems == 1)
    h.check("le spalle restano al 100%", mixed.percent(of: .shoulders) == 100)

    let onlyUnknown = distribution([item("ignoto", sets: 3)])
    h.check("solo sconosciuti → distribuzione vuota", onlyUnknown.isEmpty)
    h.check("solo sconosciuti → serie non risolte contate", onlyUnknown.unresolvedSets == 3)

    // MARK: Zone non allenate direttamente

    h.section("muscoli · zone mancanti")

    let upperOnly = distribution([
        item("chest", sets: 4),
        item("back", sets: 4),
        item("shoulders", sets: 3),
        item("biceps", sets: 3),
        item("triceps", sets: 3),
    ])
    h.check("mancano le zone non toccate, in ordine di visualizzazione",
            upperOnly.missingGroups == [.quads, .hamstrings, .glutes, .calves, .abs])
    h.check("una zona allenata non è mai fra le mancanti",
            !upperOnly.missingGroups.contains(.chest))
    h.check("Cardio, Avambracci e Altro non entrano mai fra le mancanti",
            !Stats.relevantMuscleGroups.contains(.cardio)
                && !Stats.relevantMuscleGroups.contains(.forearms)
                && !Stats.relevantMuscleGroups.contains(.other))

    // MARK: Arrotondamenti: le percentuali mostrate sommano sempre a 100

    h.section("muscoli · arrotondamenti")

    let thirds = distribution([
        item("chest", sets: 1),
        item("back", sets: 1),
        item("shoulders", sets: 1),
    ])
    h.check("tre quote uguali sommano a 100", thirds.shares.reduce(0) { $0 + $1.percent } == 100)
    h.check("tre quote uguali → 34 + 33 + 33",
            thirds.shares.map(\.percent) == [34, 33, 33])

    let sixths = distribution([
        item("chest", sets: 1), item("back", sets: 1), item("shoulders", sets: 1),
        item("biceps", sets: 1), item("triceps", sets: 1), item("abs", sets: 1),
    ])
    h.check("sei quote uguali sommano a 100", sixths.shares.reduce(0) { $0 + $1.percent } == 100)

    var roundingOK = true
    for total in 1...60 {
        for parts in 1...min(total, 7) {
            // Ripartizione irregolare ma deterministica del totale fra `parts` gruppi.
            var counts = Array(repeating: total / parts, count: parts)
            counts[0] += total % parts
            let groups = ["chest", "back", "shoulders", "biceps", "triceps", "quads", "abs"]
            let items = counts.enumerated()
                .filter { $0.element > 0 }
                .map { item(groups[$0.offset], sets: $0.element) }
            let result = distribution(items)
            if result.shares.reduce(0, { $0 + $1.percent }) != 100 { roundingOK = false }
        }
    }
    h.check("ogni ripartizione fino a 60 serie somma esattamente a 100", roundingOK)

    // MARK: Macro aree

    h.section("muscoli · macro aree")

    let balanced = distribution([
        item("chest", sets: 6), item("back", sets: 6),
        item("quads", sets: 6),
        item("abs", sets: 2),
    ])
    let areas = balanced.macroAreas
    h.check("tre macro aree", areas.map(\.area) == [.upperBody, .legs, .core])
    h.check("serie per macro area", areas.map(\.sets) == [12, 6, 2])
    h.check("le macro aree sommano a 100", areas.reduce(0) { $0 + $1.percent } == 100)
    h.check("Avambracci, Cardio e Altro non hanno macro area",
            Stats.MuscleMacroArea.containing(.forearms) == nil
                && Stats.MuscleMacroArea.containing(.cardio) == nil
                && Stats.MuscleMacroArea.containing(.other) == nil)

    // MARK: Scheda d'esempio Push / Pull / Legs sul dataset vero

    h.section("muscoli · scheda d'esempio")

    guard let repository else {
        h.fail("libreria esercizi non disponibile: scheda d'esempio non verificata")
        return
    }
    let byID = repository.exercisesByID()
    let sample = SampleProgram.make(startDate: Fixtures.date(2026, 9, 1), now: Fixtures.date(2026, 9, 1))
    let whole = Stats.muscleDistribution(of: sample, exercisesByID: byID)

    if ProcessInfo.processInfo.environment["GYMCHECKS_VERBOSE"] == "1" {
        for (label, dist) in [("TUTTA", whole)] + sample.days.map({ ($0.name, Stats.muscleDistribution(of: $0, exercisesByID: byID)) }) {
            print("   --- \(label): dirette \(dist.totalSets) pesate \(dist.totalWeightedSets)")
            for sh in dist.shares { print("      \(sh.group.displayName) \(sh.percent)% dir \(sh.directSets) ind \(sh.indirectSets)") }
            print("      mai: \(dist.neverTrainedGroups.map(\.displayName)) · indiretti: \(dist.indirectOnlyGroups.map(\.displayName))")
        }
        for id in SampleProgram.exerciseIDs {
            if let e = byID[id] {
                print("   \(id) \(e.name) [\(e.muscleGroupKind.displayName)] -> \(e.secondaryMuscleRoles.map { "\($0.group.displayName):\($0.role.rawValue)" })")
            }
        }
    }
    h.check("tutti gli esercizi d'esempio sono risolvibili", whole.unresolvedItems == 0)
    h.check("totale = somma delle serie di lavoro dei tre giorni", whole.totalSets == sample.totalSets)
    h.check("le percentuali della scheda d'esempio sommano a 100",
            whole.shares.reduce(0) { $0 + $1.percent } == 100)
    h.check("la scheda d'esempio è ordinata per quota pesata decrescente",
            whole.shares.map(\.weightedSets) == whole.shares.map(\.weightedSets).sorted(by: >))
    h.check("il dorso è la zona più allenata", whole.shares.first?.group == .back)
    h.check("petto, spalle, braccia, quadricipiti e femorali sono tutti presenti",
            whole.sets(of: .chest) > 0 && whole.sets(of: .shoulders) > 0
                && whole.sets(of: .biceps) > 0 && whole.sets(of: .triceps) > 0
                && whole.sets(of: .quads) > 0 && whole.sets(of: .hamstrings) > 0)
    h.check("lo squat conta sui quadricipiti, non sui glutei (correzione del dataset)",
            whole.sets(of: .quads) >= 7)
    h.check("polpacci e addome della scheda d'esempio sono allenati",
            whole.sets(of: .calves) == 4 && whole.sets(of: .abs) == 3)
    h.check("la scheda d'esempio non lascia fuori nessuna zona",
            whole.neverTrainedGroups.isEmpty && whole.indirectOnlyGroups.isEmpty)
    h.check("i glutei della scheda d'esempio lavorano più di riflesso che direttamente",
            whole.directSets(of: .glutes) == 3 && whole.indirectSets(of: .glutes) == 3.5)
    h.check("gli avambracci compaiono solo come secondari",
            whole.directSets(of: .forearms) == 0 && whole.indirectSets(of: .forearms) > 0)
    h.check("il totale pesato supera le serie vere", whole.totalWeightedSets > Double(whole.totalSets))

    // Giorno singolo: Push. 4+3 serie di petto, 3+3 di spalle, 3+3 di tricipiti.
    if let push = sample.days.first {
        let pushDistribution = Stats.muscleDistribution(of: push, exercisesByID: byID)
        h.check("giorno Push: totale coerente col giorno", pushDistribution.totalSets == push.totalSets)
        h.check("giorno Push: le percentuali sommano a 100",
                pushDistribution.shares.reduce(0) { $0 + $1.percent } == 100)
        h.check("giorno Push: petto, spalle e tricipiti sono le zone dirette",
                Set(pushDistribution.shares.filter { $0.directSets > 0 }.map(\.group))
                    == Set([.chest, .shoulders, .triceps]))
        h.check("giorno Push: i tricipiti guadagnano 5,0 serie indirette da panca, inclinata e lento",
                pushDistribution.directSets(of: .triceps) == 6
                    && pushDistribution.indirectSets(of: .triceps) == 5)
        h.check("giorno Push: il dorso entra solo come stabilizzatore",
                pushDistribution.indirectOnlyGroups == [.back])
        h.check("giorno Push: le gambe restano fra le zone mai allenate",
                pushDistribution.neverTrainedGroups.contains(.quads)
                    && pushDistribution.neverTrainedGroups.contains(.glutes))
        h.check("giorno Push: prime tre quote disponibili per la Home",
                pushDistribution.topShares(3).count == 3)

        // La vecchia regola, per confronto: senza secondari il dorso spariva del tutto.
        let pushPrimaryOnly = Stats.muscleDistribution(of: push, exercisesByID: byID, includesSecondary: false)
        h.check("giorno Push senza secondari: solo petto, spalle e tricipiti",
                Set(pushPrimaryOnly.shares.map(\.group)) == Set([.chest, .shoulders, .triceps]))
        h.check("giorno Push senza secondari: il dorso risulta mai allenato",
                pushPrimaryOnly.neverTrainedGroups.contains(.back))
    } else {
        h.fail("la scheda d'esempio non ha giorni")
    }

    // Giorno Pull: nessun esercizio di tricipiti, ma i bicipiti lavorano anche
    // fuori dai curl (trazioni e rematori).
    if sample.days.count >= 2 {
        let pull = Stats.muscleDistribution(of: sample.days[1], exercisesByID: byID)
        h.check("giorno Pull: i bicipiti hanno 6,0 dirette e 5,5 indirette",
                pull.directSets(of: .biceps) == 6 && pull.indirectSets(of: .biceps) == 5.5)
        h.check("giorno Pull: quadricipiti e femorali entrano solo dallo stacco",
                pull.indirectOnlyGroups == [.quads, .hamstrings])
        h.check("giorno Pull: i tricipiti non sono toccati nemmeno di riflesso",
                pull.neverTrainedGroups.contains(.triceps))
        h.check("giorno Pull: la presa lavora in ogni tirata",
                pull.indirectSets(of: .forearms) > 0)
    }

    // Giorno Legs: nessuna zona della parte alta a parte l'addome.
    if sample.days.count >= 3 {
        let legs = Stats.muscleDistribution(of: sample.days[2], exercisesByID: byID)
        h.check("giorno Legs: la macro area più grande sono le gambe",
                legs.macroAreas.first?.area == .legs)
        h.check("giorno Legs: petto, bicipiti e tricipiti mai allenati",
                legs.neverTrainedGroups == [.chest, .biceps, .triceps])
        h.check("giorno Legs: il dorso resta solo come stabilizzatore dello stacco rumeno",
                legs.indirectOnlyGroups.contains(.back) && legs.directSets(of: .back) == 0)
        h.check("giorno Legs: i glutei sono allenati solo di riflesso",
                legs.directSets(of: .glutes) == 0 && legs.indirectSets(of: .glutes) == 3.5)
    }
}
