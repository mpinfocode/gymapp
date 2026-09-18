import Foundation
import GymCore

/// Check sui **muscoli secondari**: copertura della mappa termine → zona, ruolo
/// (sinergista / stabilizzatore), pulizia degli errori grossolani del dataset e
/// verifica a mano dei movimenti più comuni.
@MainActor
func runSecondaryMuscleChecks(_ h: Harness, repository: ExerciseRepository?) async {
    guard let repository else {
        h.section("secondari")
        h.fail("repository non caricato")
        return
    }
    guard let raw = try? await ExerciseRepository.loadFromBundle(applyingCorrections: false) else {
        h.section("secondari")
        h.fail("dataset grezzo non caricato")
        return
    }
    let verbose = ProcessInfo.processInfo.environment["GYMCHECKS_VERBOSE"] == "1"

    // MARK: Copertura della mappa

    h.section("secondari · mappa")

    var terms: Set<String> = []
    for exercise in raw.all {
        for muscle in exercise.secondaryMuscles {
            let key = muscle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty { terms.insert(key) }
        }
    }
    let unmapped = terms.filter { MuscleGroup.targetGroups[$0] == nil }.sorted()
    h.check("40 valori distinti di secondary_muscles (ottenuti \(terms.count))", terms.count == 40)
    h.check("la mappa copre il 100% dei secondari del dataset: \(unmapped)", unmapped.isEmpty)
    h.check("copre anche tutti i target", repository.allTargets.allSatisfy { MuscleGroup.targetGroups[$0] != nil })

    // Scelte di mappatura che vale la pena inchiodare.
    h.check("triceps → Tricipiti", MuscleGroup.forTarget("triceps") == .triceps)
    h.check("shoulders, deltoids, rear deltoids → Spalle",
            MuscleGroup.forTarget("shoulders") == .shoulders
                && MuscleGroup.forTarget("deltoids") == .shoulders
                && MuscleGroup.forTarget("rear deltoids") == .shoulders)
    h.check("lats, rhomboids, trapezius, upper back, traps, lower back, spine → Dorso",
            ["lats", "latissimus dorsi", "rhomboids", "trapezius", "upper back", "traps", "back", "lower back", "spine"]
                .allSatisfy { MuscleGroup.forTarget($0) == .back })
    h.check("core, obliques, abdominals, lower abs, hip flexors → Addome",
            ["core", "obliques", "abdominals", "lower abs", "hip flexors"]
                .allSatisfy { MuscleGroup.forTarget($0) == .abs })
    h.check("quadriceps → Quadricipiti, hamstrings → Femorali, glutes → Glutei",
            MuscleGroup.forTarget("quadriceps") == .quads
                && MuscleGroup.forTarget("hamstrings") == .hamstrings
                && MuscleGroup.forTarget("glutes") == .glutes)
    h.check("calves, soleus, ankles, feet, shins → Polpacci",
            ["calves", "soleus", "ankles", "ankle stabilizers", "feet", "shins"]
                .allSatisfy { MuscleGroup.forTarget($0) == .calves })
    h.check("forearms, grip muscles, wrists, hands → Avambracci",
            ["forearms", "grip muscles", "wrists", "wrist flexors", "wrist extensors", "hands"]
                .allSatisfy { MuscleGroup.forTarget($0) == .forearms })
    h.check("brachialis → Bicipiti (è un flessore di gomito)", MuscleGroup.forTarget("brachialis") == .biceps)
    h.check("chest, pectorals, upper chest → Petto",
            ["chest", "pectorals", "upper chest"].allSatisfy { MuscleGroup.forTarget($0) == .chest })
    h.check("inner thighs, groin, adductors restano Altro e non entrano nel conto",
            ["inner thighs", "groin", "adductors"].allSatisfy { MuscleGroup.forTarget($0) == .other })
    h.check("abductors → Glutei (il medio gluteo è l'abduttore dell'anca)",
            MuscleGroup.forTarget("abductors") == .glutes)

    // MARK: Ruoli

    h.section("secondari · ruoli")

    func roles(_ id: String) -> [String: MuscleRole] {
        guard let exercise = repository.exercise(id: id) else { return [:] }
        var result: [String: MuscleRole] = [:]
        for secondary in exercise.secondaryMuscleRoles { result[secondary.group.displayName] = secondary.role }
        return result
    }

    h.check("panca: tricipiti e spalle sinergisti",
            roles("0025") == ["Tricipiti": .synergist, "Spalle": .synergist])
    h.check("panca inclinata: idem", roles("0047") == ["Spalle": .synergist, "Tricipiti": .synergist])
    h.check("lento avanti: tricipiti sinergisti, dorso stabilizzatore (postura)",
            roles("0405") == ["Tricipiti": .synergist, "Dorso": .stabilizer])
    h.check("alzate laterali: il trapezio è solo stabilizzatore (isolamento)",
            roles("0334") == ["Dorso": .stabilizer])
    h.check("pushdown: la presa è stabilizzatore", roles("0201") == ["Avambracci": .stabilizer])
    h.check("dip: petto e spalle sinergisti (non è un isolamento)",
            roles("0814") == ["Petto": .synergist, "Spalle": .synergist])
    h.check("push-up: tricipiti e spalle sinergisti, core di sostegno",
            roles("0662") == ["Tricipiti": .synergist, "Spalle": .synergist, "Addome": .stabilizer])
    h.check("trazioni: bicipiti sinergisti, avambracci di presa",
            roles("0652") == ["Bicipiti": .synergist, "Avambracci": .stabilizer])
    h.check("lat machine: bicipiti sinergisti, dorso duplicato via",
            roles("2330") == ["Bicipiti": .synergist, "Spalle": .synergist])
    h.check("rematore: bicipiti sinergisti, presa stabilizzatrice",
            roles("0027") == ["Bicipiti": .synergist, "Avambracci": .stabilizer])
    h.check("squat: glutei e femorali sinergisti, polpacci stabilizzatori",
            roles("0043") == ["Glutei": .synergist, "Femorali": .synergist, "Polpacci": .stabilizer])
    h.check("pressa: glutei e femorali sinergisti",
            roles("0739")["Glutei"] == .synergist && roles("0739")["Femorali"] == .synergist)
    h.check("affondi: glutei e femorali sinergisti",
            roles("0054")["Glutei"] == .synergist && roles("0054")["Femorali"] == .synergist)
    h.check("stacco: femorali e quadricipiti sinergisti, lombari di sostegno",
            roles("0032") == ["Femorali": .synergist, "Quadricipiti": .synergist, "Dorso": .stabilizer])
    h.check("stacco rumeno: glutei sinergisti, lombari di sostegno",
            roles("0085") == ["Glutei": .synergist, "Dorso": .stabilizer])
    h.check("hip thrust: femorali e quadricipiti sinergisti",
            roles("3236") == ["Femorali": .synergist, "Quadricipiti": .synergist])
    h.check("curl: l'avambraccio resta sinergista (brachioradiale)",
            roles("0031") == ["Avambracci": .synergist])
    h.check("french press: le spalle sono solo stabilizzatrici",
            roles("0056") == ["Spalle": .stabilizer])
    h.check("plank: le spalle tengono, non spingono", roles("0464") == ["Spalle": .stabilizer])
    h.check("calf raise: nessun secondario (tutti duplicati del polpaccio)", roles("0605").isEmpty)
    h.check("leg extension: nessun secondario (l'antagonista è stato tolto)", roles("0585").isEmpty)

    h.check("regola: il core in piedi è sempre stabilizzatore",
            SecondaryMuscles.role(term: "core", group: .abs, primary: .quads, isolation: false) == .stabilizer)
    h.check("regola: i lombari sono sempre sostegno",
            SecondaryMuscles.role(term: "lower back", group: .back, primary: .glutes, isolation: false) == .stabilizer)
    h.check("regola: la cuffia dei rotatori è sostegno",
            SecondaryMuscles.role(term: "rotator cuff", group: .shoulders, primary: .shoulders, isolation: false) == .stabilizer)
    h.check("regola: i polpacci nello squat stabilizzano la caviglia",
            SecondaryMuscles.role(term: "calves", group: .calves, primary: .quads, isolation: false) == .stabilizer)
    h.check("regola: i polpacci nelle trazioni non sono un caso previsto e restano sinergisti",
            SecondaryMuscles.role(term: "calves", group: .calves, primary: .back, isolation: false) == .synergist)

    // MARK: Ordine e tetto di tre

    h.section("secondari · ordine e tetto")

    let crowded = SecondaryMuscles.resolved(
        terms: ["core", "glutes", "lower back", "hamstrings", "calves"],
        primary: .quads,
        name: "barbell full squat"
    )
    h.check("i sinergisti vengono prima", crowded.map(\.role) == [.synergist, .synergist, .stabilizer])
    h.check("al massimo tre", crowded.count == SecondaryMuscles.maximumPerExercise)
    h.check("l'ordine del dataset è rispettato a parità di ruolo",
            crowded.map(\.group) == [.glutes, .hamstrings, .abs])

    let deduped = SecondaryMuscles.resolved(
        terms: ["rhomboids", "upper back", "traps"],
        primary: .biceps,
        name: "barbell bent over row"
    )
    h.check("tre sinonimi della schiena diventano una voce sola", deduped.map(\.group) == [.back])

    h.check("nessun esercizio supera i tre secondari",
            repository.all.allSatisfy { $0.secondaryMuscleGroups.count <= 3 })
    h.check("nessun secondario ripete il gruppo principale",
            repository.all.allSatisfy { exercise in
                !exercise.secondaryMuscleGroups.contains(exercise.muscleGroupKind)
            })
    h.check("nessun secondario duplicato nella stessa lista",
            repository.all.allSatisfy { Set($0.secondaryMuscleGroups).count == $0.secondaryMuscleGroups.count })
    h.check("Altro e Cardio non compaiono mai fra i secondari",
            repository.all.allSatisfy { !$0.secondaryMuscleGroups.contains(.other)
                && !$0.secondaryMuscleGroups.contains(.cardio) })
    h.check("gli esercizi personalizzati non hanno secondari", {
        let custom = Exercise.custom(name: "Face pull", category: "shoulders", target: "rear deltoids")
        return custom.secondaryMuscleGroups.isEmpty
    }())

    // MARK: Pulizia del dataset

    h.section("secondari · pulizia")

    let cleanups = ExerciseCorrections.secondaryChanges(in: raw.all)
    let byRule = Dictionary(grouping: cleanups.filter { $0.rule != nil }, by: { $0.rule! }).mapValues(\.count)
    h.check("2 duplicati letterali del principale (ottenuti \(byRule[.duplicateOfPrimary] ?? 0))",
            byRule[.duplicateOfPrimary] == 2)
    h.check("2 antagonisti in isolamento (ottenuti \(byRule[.antagonistInIsolation] ?? 0))",
            byRule[.antagonistInIsolation] == 2)
    h.check("54 assurdità nei lavori di polso (ottenute \(byRule[.absurdInWristWork] ?? 0))",
            byRule[.absurdInWristWork] == 54)
    h.check("1 sinergista aggiunto (lo stacco convenzionale)", cleanups.filter { $0.rule == nil }.count == 1)
    h.check("59 modifiche ai secondari in tutto (ottenute \(cleanups.count))", cleanups.count == 59)

    h.check("leg extension perde i femorali",
            repository.exercise(id: "0585")?.secondaryMuscles.isEmpty == true)
    h.check("il wrist curl perde bicipiti e brachiale",
            repository.exercise(id: "0126")?.secondaryMuscles.isEmpty == true)
    h.check("il reverse wrist curl perde il duplicato forearms",
            repository.exercise(id: "0994")?.secondaryMuscles.isEmpty == true)
    h.check("lo stacco convenzionale guadagna i quadricipiti",
            repository.exercise(id: "0032")?.secondaryMuscles.contains("quadriceps") == true)
    h.check("lo stacco sumo li aveva già e non viene toccato",
            repository.exercise(id: "0117")?.secondaryMuscles == ["hamstrings", "quadriceps", "lower back"])
    h.check("i femorali nello squat restano (non è un isolamento)",
            repository.exercise(id: "0043")?.secondaryMuscles.contains("hamstrings") == true)
    h.check("pulizia idempotente",
            ExerciseCorrections.apply(to: repository.all) == repository.all)
    h.check("nessun secondario vuoto",
            repository.all.allSatisfy { $0.secondaryMuscles.allSatisfy { !$0.isEmpty } })

    h.check("regola: l'antagonista cade solo negli isolamenti",
            ExerciseCorrections.removalRule(term: "hamstrings", targetTerm: "quads", primary: .quads,
                                            isolation: true, normalizedName: "lever leg extension") != nil
                && ExerciseCorrections.removalRule(term: "hamstrings", targetTerm: "quads", primary: .quads,
                                                   isolation: false, normalizedName: "barbell full squat") == nil)
    h.check("regola: i romboidi restano nel dato (servono alla ricerca)",
            ExerciseCorrections.removalRule(term: "rhomboids", targetTerm: "lats", primary: .back,
                                            isolation: false, normalizedName: "cable lat pulldown") == nil)

    if verbose {
        for cleanup in cleanups {
            let rule = cleanup.rule?.displayName ?? "AGGIUNTO"
            print("   \(rule) · \(cleanup.exerciseID) \(cleanup.name): \(cleanup.muscle)")
        }
    }
}
