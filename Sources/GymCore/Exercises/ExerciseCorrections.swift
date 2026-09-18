import Foundation

/// Correzioni anatomiche applicate al dataset **al caricamento** del repository.
///
/// Il JSON di `Resources/exercises.json` resta quello upstream (SPEC §2): qui si
/// riscrivono solo `target` e `secondaryMuscles` dei record sbagliati, in modo
/// dichiarativo e verificabile (regole per pattern sul nome + liste di eccezioni).
///
/// ## Il difetto
/// Nel dataset 144 esercizi di `upper legs` hanno `target = glutes` con
/// `quadriceps` solo fra i secondari: è un'eredità di ExerciseDB. Squat, affondi,
/// leg press e step-up hanno però il **quadricipite come motore primario**, e
/// stacchi rumeni / a gambe tese / good morning hanno i **femorali**.
///
/// ## Le regole
/// 1. Si interviene solo su esercizi con `target == "glutes"`.
/// 2. Gli esercizi di mobilità (nome contenente `stretch`) non si toccano mai.
/// 3. Nomi con pattern "cerniera d'anca a ginocchio fermo" (romanian deadlift,
///    stiff leg, straight leg deadlift, good morning, leg curl) → `hamstrings`.
/// 4. Nomi con pattern di accosciata/affondo/spinta di gamba (squat, lunge,
///    leg press, step up, hack, sissy, wall sit) → `quads`.
/// 5. ``keptAsGlutes`` elenca gli id che il pattern peschebbe ma che restano
///    glutei perché il pattern è solo descrittivo (turkish get up "squat style")
///    o perché sono drill di mobilità (potty squat).
/// 6. ``forcedToQuads`` elenca gli id che il pattern non pesca ma che sono
///    chiaramente lavoro di quadricipite (leg **wide** press, march sit al muro).
///
/// In entrambi i casi il muscolo che perde il ruolo di target passa **in testa** ai
/// secondari, così l'informazione non si perde (SPEC §2, punto 1).
///
/// Quello che **non** si tocca, per scelta: stacchi (anche sumo, rack pull, trap
/// bar, single leg), hip thrust, glute bridge, kickback, pull through, hip
/// extension, kettlebell swing e tutti gli allungamenti. Lì il dataset è corretto
/// o comunque difendibile.
public enum ExerciseCorrections {

    /// Una singola correzione applicata, per il report e per i check.
    public struct Change: Sendable, Hashable, Identifiable {
        public let exerciseID: String
        public let name: String
        public let previousTarget: String
        public let newTarget: String

        public var id: String { exerciseID }

        public init(exerciseID: String, name: String, previousTarget: String, newTarget: String) {
            self.exerciseID = exerciseID
            self.name = name
            self.previousTarget = previousTarget
            self.newTarget = newTarget
        }
    }

    // MARK: - Regole

    /// Pattern (su nome normalizzato) che identificano un movimento a dominanza quadricipite.
    public static let quadsPatterns: [String] = [
        "squat",
        "lunge",
        "leg press",
        "step up",
        "hack",
        "sissy",
        "wall sit",
    ]

    /// Pattern (su nome normalizzato) che identificano una cerniera d'anca a dominanza femorali.
    public static let hamstringsPatterns: [String] = [
        "romanian deadlift",
        "stiff leg",
        "straight leg deadlift",
        "good morning",
        "leg curl",
        "hamstring curl",
        "femoral",
    ]

    /// Id che i pattern pescherebbero ma che restano `glutes`.
    ///
    /// - `0551` kettlebell turkish get up (squat style): "squat" è solo lo stile di
    ///   risalita, il movimento è un get up di tutto il corpo.
    /// - `3132` potty squat with support: drill di mobilità d'anca (nel dataset il
    ///   gemello `3119 potty squat` sta perfino in `waist`).
    public static let keptAsGlutes: Set<String> = ["0551", "3132"]

    /// Id senza pattern utile ma inequivocabilmente di quadricipite.
    ///
    /// - `0740` sled 45° leg **wide** press: è una leg press, il pattern
    ///   "leg press" non la pesca per via dell'aggettivo in mezzo.
    /// - `0624` march sit (wall): è un wall sit con marcia, isometria di quadricipite.
    public static let forcedToQuads: Set<String> = ["0740", "0624"]

    /// Sotto-stringa che marca gli esercizi di allungamento: non si correggono mai.
    public static let stretchMarker = "stretch"

    // MARK: - Applicazione

    /// Nuovo target per un esercizio, `nil` se va lasciato com'è.
    ///
    /// Funzione pura: dipende solo da id, nome e target correnti, così è facile
    /// verificarla dai check senza costruire un repository.
    public static func correctedTarget(id: String, name: String, target: String) -> String? {
        guard target.lowercased() == "glutes" else { return nil }
        guard !keptAsGlutes.contains(id) else { return nil }

        let key = SearchText.normalize(name)
        guard !SearchText.contains(key, stretchMarker) else { return nil }

        if hamstringsPatterns.contains(where: { SearchText.contains(key, $0) }) { return "hamstrings" }
        if forcedToQuads.contains(id) { return "quads" }
        if quadsPatterns.contains(where: { SearchText.contains(key, $0) }) { return "quads" }
        return nil
    }

    /// Esercizio corretto. Gli esercizi personalizzati dell'utente passano intatti:
    /// il target lo ha scelto lui e non va sovrascritto.
    public static func corrected(_ exercise: Exercise) -> Exercise {
        guard !exercise.isCustom else { return exercise }
        guard let newTarget = correctedTarget(id: exercise.id, name: exercise.name, target: exercise.target) else {
            return exercise
        }
        return exercise.replacingMuscles(
            target: newTarget,
            secondaryMuscles: rebuiltSecondaries(of: exercise, newTarget: newTarget)
        )
    }

    /// Correzioni applicate a un'intera libreria, nell'ordine di ingresso.
    public static func apply(to exercises: [Exercise]) -> [Exercise] {
        exercises.map(corrected)
    }

    /// Elenco delle correzioni che verrebbero applicate (per report e check).
    public static func changes(in exercises: [Exercise]) -> [Change] {
        exercises.compactMap { exercise in
            guard !exercise.isCustom,
                  let newTarget = correctedTarget(id: exercise.id, name: exercise.name, target: exercise.target)
            else { return nil }
            return Change(
                exerciseID: exercise.id,
                name: exercise.name,
                previousTarget: exercise.target,
                newTarget: newTarget
            )
        }
    }

    /// Secondari ricostruiti: il vecchio target va in testa, il nuovo target sparisce
    /// dai secondari (non ha senso essere primario e secondario insieme).
    private static func rebuiltSecondaries(of exercise: Exercise, newTarget: String) -> [String] {
        // `quads` nel dataset compare fra i secondari con il nome esteso `quadriceps`.
        let removed: Set<String> = newTarget == "quads" ? ["quads", "quadriceps"] : [newTarget]
        var result = [exercise.target]
        for muscle in exercise.secondaryMuscles where !removed.contains(muscle.lowercased()) {
            if !result.contains(muscle) { result.append(muscle) }
        }
        return result
    }
}
