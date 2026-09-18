import Foundation
import GymCore

/// Verifica la selezione curata di esercizi: è il pezzo su cui poggia tutta la
/// qualità delle schede generate, quindi va controllato riga per riga contro il
/// dataset vero.
@MainActor
func runGeneratorPoolChecks(_ harness: Harness, repository: ExerciseRepository?) {
    harness.section("generatore · selezione")
    guard let repository else {
        harness.fail("repository non caricato")
        return
    }

    let pool = CuratedExercisePool.all
    harness.check(
        "la selezione ha fra 220 e 280 esercizi (ne ha \(pool.count))",
        (220...280).contains(pool.count)
    )

    // Id unici
    var seen: Set<String> = []
    let duplicates = pool.map(\.id).filter { !seen.insert($0).inserted }
    harness.check("nessun id ripetuto nella selezione (\(duplicates.joined(separator: ", ")))", duplicates.isEmpty)

    // Id esistenti
    let missing = CuratedExercisePool.missingIDs(in: repository)
    harness.check("ogni id della selezione esiste nel dataset (\(missing.joined(separator: ", ")))", missing.isEmpty)

    let resolved = CuratedExercisePool.resolved(in: repository)
    guard harness.check("tutti gli esercizi si risolvono sulla libreria", resolved.count == pool.count) else { return }

    // Coerenza fra etichetta e dataset
    var wrongGroup: [String] = []
    var wrongEquipment: [String] = []
    var redundant: [String] = []
    var emptyName: [String] = []
    for item in resolved {
        if item.group == .other || !item.pattern.plausibleGroups.contains(item.group) {
            wrongGroup.append("\(item.id) \(item.exercise.name) → \(item.group.displayName) con schema \(item.pattern.displayName)")
        }
        if EquipmentClass.forEquipment(item.exercise.equipment) != item.equipmentClass {
            wrongEquipment.append("\(item.id) \(item.exercise.equipment) ≠ \(item.equipmentClass.rawValue)")
        }
        if item.exercise.isRedundantVariant { redundant.append("\(item.id) \(item.exercise.name)") }
        if item.shortName.trimmingCharacters(in: .whitespaces).isEmpty { emptyName.append(item.id) }
    }
    harness.check("il gruppo muscolare è coerente con lo schema motorio (\(wrongGroup.prefix(4).joined(separator: "; ")))", wrongGroup.isEmpty)
    harness.check("la classe di attrezzatura corrisponde all'attrezzo del dataset (\(wrongEquipment.prefix(4).joined(separator: "; ")))", wrongEquipment.isEmpty)
    harness.check("nessuna variante ridondante nella selezione (\(redundant.joined(separator: "; ")))", redundant.isEmpty)
    harness.check("ogni esercizio ha un titolo breve non vuoto (\(emptyName.joined(separator: ", ")))", emptyName.isEmpty)

    // Copertura: tutti i gruppi, tutte le classi
    let groups = Set(resolved.map(\.group))
    for group in MuscleGroup.displayOrder where group != .other {
        harness.check("la selezione copre \(group.displayName)", groups.contains(group))
    }
    for equipmentClass in EquipmentClass.allCases {
        let count = resolved.filter { $0.equipmentClass == equipmentClass }.count
        harness.check("almeno 40 esercizi per \(equipmentClass.displayName) (ne ha \(count))", count >= 40)
    }

    // Minimi per gruppo × attrezzatura (le classi sono annidate)
    for (available, minimums) in CuratedExercisePool.minimumPerGroup {
        let usable = resolved.filter { $0.equipmentClass.rank <= available.rank }
        for (group, minimum) in minimums {
            let count = usable.filter { $0.group == group }.count
            harness.check(
                "\(available.displayName): almeno \(minimum) esercizi per \(group.displayName) (ne ha \(count))",
                count >= minimum
            )
        }
    }

    // Priorità valide e almeno un classico per schema motorio
    for pattern in MovementPattern.allCases {
        let entries = resolved.filter { $0.pattern == pattern }
        harness.check("lo schema \(pattern.displayName) ha almeno 3 esercizi (ne ha \(entries.count))", entries.count >= 3)
        harness.check("lo schema \(pattern.displayName) ha almeno un esercizio di priorità 1", entries.contains { $0.priority == 1 })
    }

    // Ogni schema motorio deve esistere in tutte e tre le classi, tranne quelli
    // che a corpo libero non esistono davvero (croci, pulldown a braccia tese).
    let patternsMissingAtHome: Set<MovementPattern> = [.chestIsolation, .backIsolation]
    for pattern in MovementPattern.allCases where !patternsMissingAtHome.contains(pattern) {
        let hasHome = resolved.contains { $0.pattern == pattern && $0.equipmentClass == .bodyweightBands }
        harness.check("lo schema \(pattern.displayName) esiste anche a corpo libero", hasHome)
    }
}
