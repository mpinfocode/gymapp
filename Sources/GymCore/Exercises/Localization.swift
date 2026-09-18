import Foundation

/// Traduzioni italiane dei termini inglesi del dataset.
///
/// Le mappe coprono **tutti** i valori distinti presenti in `exercises.json`:
/// 10 categorie, 28 attrezzi e 50 termini muscolari (unione di `target`,
/// `muscle_group` e `secondary_muscles`). La copertura è verificata da
/// ``missingTerms(in:)`` ed è uno dei check di `GymChecks`.
///
/// I nomi degli esercizi restano in inglese (il dataset non li traduce).
public enum Localization {

    // MARK: - Categorie (10)

    public static let categoryTranslations: [String: String] = [
        "back": "Schiena",
        "cardio": "Cardio",
        "chest": "Petto",
        "lower arms": "Avambracci",
        "lower legs": "Polpacci",
        "neck": "Collo",
        "shoulders": "Spalle",
        "upper arms": "Braccia",
        "upper legs": "Gambe",
        "waist": "Addome",
    ]

    // MARK: - Attrezzi (28)

    public static let equipmentTranslations: [String: String] = [
        "assisted": "Assistito",
        "band": "Elastico",
        "barbell": "Bilanciere",
        "body weight": "Corpo libero",
        "bosu ball": "Bosu",
        "cable": "Cavi",
        "dumbbell": "Manubri",
        "elliptical machine": "Ellittica",
        "ez barbell": "Bilanciere EZ",
        "hammer": "Martello",
        "kettlebell": "Kettlebell",
        "leverage machine": "Macchina a leva",
        "medicine ball": "Palla medica",
        "olympic barbell": "Bilanciere olimpico",
        "resistance band": "Banda elastica",
        "roller": "Rullo",
        "rope": "Corda",
        "skierg machine": "SkiErg",
        "sled machine": "Pressa a slitta",
        "smith machine": "Multipower",
        "stability ball": "Fitball",
        "stationary bike": "Cyclette",
        "stepmill machine": "Stepmill",
        "tire": "Pneumatico",
        "trap bar": "Trap bar",
        "upper body ergometer": "Ergometro per braccia",
        "weighted": "Con sovraccarico",
        "wheel roller": "Ruota per addominali",
    ]

    // MARK: - Muscoli (50: target ∪ muscle_group ∪ secondary_muscles)

    public static let muscleTranslations: [String: String] = [
        "abdominals": "Addominali",
        "abductors": "Abduttori",
        "abs": "Addominali",
        "adductors": "Adduttori",
        "ankle stabilizers": "Stabilizzatori della caviglia",
        "ankles": "Caviglie",
        "back": "Schiena",
        "biceps": "Bicipiti",
        "brachialis": "Brachiale",
        "calves": "Polpacci",
        "cardiovascular system": "Sistema cardiovascolare",
        "chest": "Petto",
        "core": "Core",
        "deltoids": "Deltoidi",
        "delts": "Deltoidi",
        "feet": "Piedi",
        "forearms": "Avambracci",
        "glutes": "Glutei",
        "grip muscles": "Muscoli della presa",
        "groin": "Inguine",
        "hamstrings": "Femorali",
        "hands": "Mani",
        "hip flexors": "Flessori dell'anca",
        "inner thighs": "Interno coscia",
        "latissimus dorsi": "Gran dorsale",
        "lats": "Dorsali",
        "levator scapulae": "Elevatore della scapola",
        "lower abs": "Addominali bassi",
        "lower back": "Lombari",
        "obliques": "Obliqui",
        "pectorals": "Pettorali",
        "quadriceps": "Quadricipiti",
        "quads": "Quadricipiti",
        "rear deltoids": "Deltoidi posteriori",
        "rhomboids": "Romboidi",
        "rotator cuff": "Cuffia dei rotatori",
        "serratus anterior": "Dentato anteriore",
        "shins": "Tibiali",
        "shoulders": "Spalle",
        "soleus": "Soleo",
        "spine": "Colonna vertebrale",
        "sternocleidomastoid": "Sternocleidomastoideo",
        "trapezius": "Trapezio",
        "traps": "Trapezio",
        "triceps": "Tricipiti",
        "upper back": "Dorso alto",
        "upper chest": "Petto alto",
        "wrist extensors": "Estensori del polso",
        "wrist flexors": "Flessori del polso",
        "wrists": "Polsi",
    ]

    // MARK: - Lookup

    /// Categoria tradotta; se sconosciuta ricade sul termine inglese capitalizzato.
    public static func category(_ value: String) -> String {
        lookup(value, in: categoryTranslations)
    }

    /// Attrezzo tradotto; se sconosciuto ricade sul termine inglese capitalizzato.
    public static func equipment(_ value: String) -> String {
        lookup(value, in: equipmentTranslations)
    }

    /// Muscolo tradotto; se sconosciuto ricade sul termine inglese capitalizzato.
    public static func muscle(_ value: String) -> String {
        lookup(value, in: muscleTranslations)
    }

    /// Traduce una lista di muscoli preservando l'ordine e togliendo i duplicati
    /// che nascono dalle traduzioni (es. `lats` e `latissimus dorsi`).
    public static func muscles(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let translated = muscle(value)
            guard !translated.isEmpty, seen.insert(translated).inserted else { continue }
            result.append(translated)
        }
        return result
    }

    private static func lookup(_ value: String, in table: [String: String]) -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return "" }
        return table[key] ?? Exercise.capitalizingWords(key)
    }

    // MARK: - Verifica di copertura

    /// Termini di un insieme di esercizi che **non** hanno una traduzione esplicita.
    ///
    /// Usato dai check per garantire che il dataset sia coperto al 100%.
    /// Il risultato è ordinato, così il messaggio d'errore è stabile.
    public static func missingTerms(in exercises: [Exercise]) -> (categories: [String], equipment: [String], muscles: [String]) {
        var missingCategories: Set<String> = []
        var missingEquipment: Set<String> = []
        var missingMuscles: Set<String> = []

        func key(_ value: String) -> String? {
            let k = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return k.isEmpty ? nil : k
        }

        for exercise in exercises {
            if let k = key(exercise.category), categoryTranslations[k] == nil { missingCategories.insert(k) }
            if let k = key(exercise.bodyPart), categoryTranslations[k] == nil { missingCategories.insert(k) }
            if let k = key(exercise.equipment), equipmentTranslations[k] == nil { missingEquipment.insert(k) }
            for term in [exercise.target, exercise.muscleGroup] + exercise.secondaryMuscles {
                if let k = key(term), muscleTranslations[k] == nil { missingMuscles.insert(k) }
            }
        }

        return (missingCategories.sorted(), missingEquipment.sorted(), missingMuscles.sorted())
    }
}
