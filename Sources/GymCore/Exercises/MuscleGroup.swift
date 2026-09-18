import Foundation

/// Gruppo muscolare "da palestra": la zona che l'utente dice di aver colpito.
///
/// È la dimensione con cui l'app ragiona nelle statistiche e nel filtro "zona colpita".
/// Non è il muscolo anatomico del dataset (`target`) ma la sua famiglia: serve una
/// mappa **stabile** e piccola, perché con 19 target diversi le card dei progressi
/// diventerebbero illeggibili.
///
/// La mappa parte sempre dal `target` **corretto** (vedi ``ExerciseCorrections``) e
/// ricade sulla `category` solo se il target è sconosciuto (tipico degli esercizi
/// personalizzati). Il campo `muscle_group` del dataset non viene mai usato: è una
/// copia del primo muscolo secondario ed è inaffidabile (SPEC §2, punto 2).
public enum MuscleGroup: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case abs
    case quads
    case hamstrings
    case glutes
    case calves
    case cardio
    case other

    public var id: String { rawValue }

    /// Nome italiano da palestra, da mostrare nei chip e nelle statistiche.
    public var displayName: String {
        switch self {
        case .chest: "Petto"
        case .back: "Dorso"
        case .shoulders: "Spalle"
        case .biceps: "Bicipiti"
        case .triceps: "Tricipiti"
        case .forearms: "Avambracci"
        case .abs: "Addome"
        case .quads: "Quadricipiti"
        case .hamstrings: "Femorali"
        case .glutes: "Glutei"
        case .calves: "Polpacci"
        case .cardio: "Cardio"
        case .other: "Altro"
        }
    }

    /// Ordine stabile per la UI (dall'alto verso il basso del corpo, cardio e residui in fondo).
    ///
    /// Coincide con l'ordine di ``allCases``: è esplicito perché i chip non devono
    /// cambiare posizione da una build all'altra.
    public static let displayOrder: [MuscleGroup] = allCases

    // MARK: - Mappa target → gruppo

    /// Tutti i termini muscolari del dataset (target e secondari) ricondotti al gruppo.
    ///
    /// Scelte non ovvie, prese con criterio da preparatore atletico:
    /// - `serratus anterior` → Petto (è un muscolo della gabbia toracica, e nel dataset
    ///   quei 5 esercizi stanno in categoria `chest`);
    /// - `traps`, `spine`, `levator scapulae` → Dorso (in palestra "schiena");
    /// - `abductors` → Glutei (l'abduttore principale dell'anca è il medio gluteo);
    /// - `adductors`, `hip flexors`, `groin`, `inner thighs` e il collo → Altro: non
    ///   esiste una zona "da palestra" fra quelle previste che li rappresenti onestamente.
    public static let targetGroups: [String: MuscleGroup] = [
        // Petto
        "pectorals": .chest,
        "chest": .chest,
        "upper chest": .chest,
        "serratus anterior": .chest,
        // Dorso
        "lats": .back,
        "latissimus dorsi": .back,
        "upper back": .back,
        "back": .back,
        "lower back": .back,
        "spine": .back,
        "traps": .back,
        "trapezius": .back,
        "rhomboids": .back,
        "levator scapulae": .back,
        // Spalle
        "delts": .shoulders,
        "deltoids": .shoulders,
        "shoulders": .shoulders,
        "rear deltoids": .shoulders,
        "rotator cuff": .shoulders,
        // Braccia
        "biceps": .biceps,
        "brachialis": .biceps,
        "triceps": .triceps,
        "forearms": .forearms,
        "grip muscles": .forearms,
        "wrist extensors": .forearms,
        "wrist flexors": .forearms,
        "wrists": .forearms,
        "hands": .forearms,
        // Addome
        "abs": .abs,
        "abdominals": .abs,
        "lower abs": .abs,
        "obliques": .abs,
        "core": .abs,
        // Gambe
        "quads": .quads,
        "quadriceps": .quads,
        "hamstrings": .hamstrings,
        "glutes": .glutes,
        "abductors": .glutes,
        "calves": .calves,
        "soleus": .calves,
        "shins": .calves,
        "ankles": .calves,
        "ankle stabilizers": .calves,
        "feet": .calves,
        // Cardio
        "cardiovascular system": .cardio,
        // Senza una zona da palestra sensata
        "adductors": .other,
        "inner thighs": .other,
        "hip flexors": .other,
        "groin": .other,
        "sternocleidomastoid": .other,
        "neck": .other,
    ]

    /// Ripiego sulla categoria del dataset quando il target non è riconosciuto.
    ///
    /// `upper arms` e `upper legs` restano ``other``: contengono muscoli opposti
    /// (bicipiti/tricipiti, quadricipiti/femorali) e tirare a indovinare falserebbe
    /// le statistiche.
    public static let categoryGroups: [String: MuscleGroup] = [
        "back": .back,
        "cardio": .cardio,
        "chest": .chest,
        "lower arms": .forearms,
        "lower legs": .calves,
        "neck": .other,
        "shoulders": .shoulders,
        "upper arms": .other,
        "upper legs": .other,
        "waist": .abs,
    ]

    /// Gruppo di un muscolo del dataset (termine inglese), ``other`` se sconosciuto.
    public static func forTarget(_ target: String) -> MuscleGroup {
        targetGroups[normalizedKey(target)] ?? .other
    }

    /// Gruppo di un muscolo, con ripiego sulla categoria quando il target non basta.
    public static func forTarget(_ target: String, category: String) -> MuscleGroup {
        if let group = targetGroups[normalizedKey(target)] { return group }
        return categoryGroups[normalizedKey(category)] ?? .other
    }

    /// Gruppo di un esercizio: usa `target` (già corretto) e poi `category`.
    public static func forExercise(_ exercise: Exercise) -> MuscleGroup {
        forTarget(exercise.target, category: exercise.category)
    }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Exercise {
    /// Zona colpita "da palestra" dell'esercizio (vedi ``MuscleGroup``).
    public var muscleGroupKind: MuscleGroup { MuscleGroup.forExercise(self) }

    /// Nome italiano della zona colpita, pronto per la UI.
    public var localizedMuscleGroupKind: String { muscleGroupKind.displayName }
}
