import Foundation
import GymCore

/// Verifica di `Stats.muscleDistribution(...)`: pesi, ordinamento, arrotondamenti
/// che devono sommare a 100, zone mancanti, esercizi personalizzati e sconosciuti.
@MainActor
func runMuscleDistributionChecks(_ h: Harness, repository: ExerciseRepository?) {

    // MARK: Esercizi finti, uno per gruppo, per controllare l'aritmetica senza dataset.

    func fake(_ id: String, target: String, category: String = "") -> Exercise {
        Exercise(id: id, name: id, category: category, target: target)
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

    h.check("tutti gli esercizi d'esempio sono risolvibili", whole.unresolvedItems == 0)
    h.check("totale = somma delle serie di lavoro dei tre giorni", whole.totalSets == sample.totalSets)
    h.check("le percentuali della scheda d'esempio sommano a 100",
            whole.shares.reduce(0) { $0 + $1.percent } == 100)
    h.check("la scheda d'esempio è ordinata per quota decrescente",
            whole.shares.map(\.sets) == whole.shares.map(\.sets).sorted(by: >))
    h.check("il dorso è la zona più allenata", whole.shares.first?.group == .back)
    h.check("petto, spalle, braccia, quadricipiti e femorali sono tutti presenti",
            whole.sets(of: .chest) > 0 && whole.sets(of: .shoulders) > 0
                && whole.sets(of: .biceps) > 0 && whole.sets(of: .triceps) > 0
                && whole.sets(of: .quads) > 0 && whole.sets(of: .hamstrings) > 0)
    h.check("lo squat conta sui quadricipiti, non sui glutei (correzione del dataset)",
            whole.sets(of: .quads) >= 7)
    h.check("polpacci e addome della scheda d'esempio sono allenati",
            whole.sets(of: .calves) == 4 && whole.sets(of: .abs) == 3)

    // Giorno singolo: Push.
    if let push = sample.days.first {
        let pushDistribution = Stats.muscleDistribution(of: push, exercisesByID: byID)
        h.check("giorno Push: totale coerente col giorno", pushDistribution.totalSets == push.totalSets)
        h.check("giorno Push: le percentuali sommano a 100",
                pushDistribution.shares.reduce(0) { $0 + $1.percent } == 100)
        h.check("giorno Push: solo petto, spalle e tricipiti",
                Set(pushDistribution.shares.map(\.group)) == Set([.chest, .shoulders, .triceps]))
        h.check("giorno Push: dorso e gambe fra le zone mancanti",
                pushDistribution.missingGroups.contains(.back)
                    && pushDistribution.missingGroups.contains(.quads))
        h.check("giorno Push: prime tre quote disponibili per la Home",
                pushDistribution.topShares(3).count == 3)
    } else {
        h.fail("la scheda d'esempio non ha giorni")
    }

    // Giorno Legs: nessuna zona della parte alta a parte l'addome.
    if sample.days.count >= 3 {
        let legs = Stats.muscleDistribution(of: sample.days[2], exercisesByID: byID)
        h.check("giorno Legs: la macro area più grande sono le gambe",
                legs.macroAreas.first?.area == .legs)
        h.check("giorno Legs: petto e dorso fra le zone mancanti",
                legs.missingGroups.contains(.chest) && legs.missingGroups.contains(.back))
    }
}
