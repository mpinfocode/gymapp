import Foundation
import GymCore

/// Verifica di `Exercise.shortDisplayName`: il titolo mostrato nelle liste, nel
/// dettaglio, nella scheda e nel picker (SPEC §0, "Nomi esercizi").
@MainActor
func runExerciseNameChecks(_ h: Harness, repository: ExerciseRepository?) {

    h.section("nomi · prefisso dell'attrezzo")

    func short(_ name: String) -> String {
        Exercise(id: "x", name: name).shortDisplayName
    }

    // Gli esempi della specifica, uno per uno.
    h.check("dumbbell lateral raise → Lateral Raise", short("dumbbell lateral raise") == "Lateral Raise")
    h.check("barbell bench press → Bench Press", short("barbell bench press") == "Bench Press")
    h.check("cable pushdown → Pushdown", short("cable pushdown") == "Pushdown")
    h.check("ez barbell curl → Curl", short("ez barbell curl") == "Curl")
    h.check("smith squat → Squat", short("smith squat") == "Squat")
    h.check("lever leg extension → Leg Extension", short("lever leg extension") == "Leg Extension")
    h.check("sled 45° leg press → 45° Leg Press", short("sled 45° leg press") == "45° Leg Press")
    h.check("band front raise → Front Raise", short("band front raise") == "Front Raise")
    h.check("kettlebell arnold press → Arnold Press", short("kettlebell arnold press") == "Arnold Press")
    h.check("weighted russian twist → Russian Twist", short("weighted russian twist") == "Russian Twist")
    h.check("resistance band leg extension → Leg Extension", short("resistance band leg extension") == "Leg Extension")
    h.check("medicine ball chest pass → Chest Pass", short("medicine ball chest pass") == "Chest Pass")
    h.check("bodyweight standing row → Standing Row", short("bodyweight standing row") == "Standing Row")
    h.check("exercise ball crunch → Crunch", short("exercise ball crunch") == "Crunch")

    // Il prefisso più lungo vince su quello più corto.
    h.check("smith machine bicep curl → Bicep Curl", short("smith machine bicep curl") == "Bicep Curl")
    h.check("olympic barbell hammer curl → Hammer Curl", short("olympic barbell hammer curl") == "Hammer Curl")
    h.check("trap bar deadlift → Deadlift", short("trap bar deadlift") == "Deadlift")

    // MARK: Casi in cui NON si accorcia

    h.section("nomi · quando non si accorcia")

    h.check("barbell (solo attrezzo) resta intero", short("barbell") == "Barbell")
    h.check("barbell press resta intero", short("barbell press") == "Barbell Press")
    h.check("cable row resta intero", short("cable row") == "Cable Row")
    h.check("dumbbell raise resta intero", short("dumbbell raise") == "Dumbbell Raise")
    h.check("rope climb resta intero", short("rope climb") == "Rope Climb")
    h.check("exercise ball hug resta intero", short("exercise ball hug") == "Exercise Ball Hug")
    h.check(
        "exercise ball on the wall calf raise resta intero",
        short("exercise ball on the wall calf raise") == "Exercise Ball On The Wall Calf Raise"
    )
    h.check("assisted pull-up non è un attrezzo", short("assisted pull-up") == "Assisted Pull-up")
    h.check("sledge hammer non inizia con sled", short("sledge hammer") == "Sledge Hammer")
    h.check("bandana non inizia con band", short("bandana row") == "Bandana Row")
    h.check("il prefisso vale solo in testa", short("incline dumbbell press") == "Incline Dumbbell Press")

    let custom = Exercise.custom(name: "Cable Face Pull", equipment: "cable")
    h.check("personalizzato: nome intatto", custom.shortDisplayName == custom.displayName)

    // MARK: Sull'intero dataset

    guard let repository else {
        h.fail("libreria non caricata: check dataset saltati")
        return
    }

    h.section("nomi · dataset")

    let all = repository.all
    var shortened = 0
    var empty = 0
    var ambiguous = 0
    var unchanged = 0

    for exercise in all {
        let value = exercise.shortDisplayName
        if value.isEmpty { empty += 1 }
        if value == exercise.displayName {
            unchanged += 1
        } else {
            shortened += 1
            if value.split(separator: " ").count == 1,
               Exercise.ambiguousShortNames.contains(value.lowercased()) {
                ambiguous += 1
            }
        }
    }

    h.check("nessun titolo vuoto", empty == 0)
    h.check("nessun titolo ridotto a una parola ambigua", ambiguous == 0)
    h.check("il titolo si accorcia su una buona parte della libreria (\(shortened))", shortened > 800)
    h.check("resta un residuo non toccato (\(unchanged))", unchanged > 300)
    h.check(
        "displayName resta il nome completo capitalizzato",
        all.allSatisfy { $0.displayName.lowercased() == $0.name.lowercased() }
    )
    h.check(
        "il titolo corto è sempre un suffisso del nome completo",
        all.allSatisfy { $0.displayName.hasSuffix($0.shortDisplayName) }
    )

    // La ricerca resta sul nome completo.
    let byFullName = repository.search(ExerciseFilter(query: "dumbbell lateral raise"))
    h.check("ricerca sul nome completo ancora viva", !byFullName.isEmpty)
}
