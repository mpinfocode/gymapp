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
///
/// ## I muscoli secondari
/// Da quando i secondari entrano nel calcolo della ripartizione
/// (``Stats/muscleDistribution(items:exercise:)``) non basta più mostrarli in
/// piccolo: gli errori grossolani vanno tolti. Le regole di pulizia sono in
/// ``cleanedSecondaries(id:name:target:secondaries:)`` e riguardano solo i casi
/// **inequivocabili**; in tutti gli altri il dato resta com'è.
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
    /// target e secondari li ha scelti lui e non vanno sovrascritti.
    public static func corrected(_ exercise: Exercise) -> Exercise {
        guard !exercise.isCustom else { return exercise }
        let newTarget = correctedTarget(id: exercise.id, name: exercise.name, target: exercise.target)
        let target = newTarget ?? exercise.target
        let source = newTarget == nil
            ? exercise.secondaryMuscles
            : rebuiltSecondaries(of: exercise, newTarget: target)
        let secondaries = cleanedSecondaries(
            id: exercise.id,
            name: exercise.name,
            target: target,
            secondaries: source
        )
        guard newTarget != nil || secondaries != exercise.secondaryMuscles else { return exercise }
        return exercise.replacingMuscles(target: target, secondaryMuscles: secondaries)
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

    // MARK: - Pulizia dei muscoli secondari

    /// Motivo per cui un secondario è stato tolto, per il report e per i check.
    public enum SecondaryRule: String, Sendable, Hashable, CaseIterable {
        /// Ripete il muscolo principale (`forearms` fra i secondari di un wrist curl).
        case duplicateOfPrimary
        /// È l'antagonista in un esercizio di isolamento: quando il motore si
        /// accorcia quello lì si allunga, non lavora (leg extension → `hamstrings`).
        case antagonistInIsolation
        /// Assurdità anatomica in un esercizio di polso/presa: nel wrist curl il
        /// bicipite, il tricipite e il deltoide non fanno niente.
        case absurdInWristWork

        public var displayName: String {
            switch self {
            case .duplicateOfPrimary: "Duplicato del principale"
            case .antagonistInIsolation: "Antagonista in isolamento"
            case .absurdInWristWork: "Assurdo negli esercizi di polso"
            }
        }
    }

    /// Un secondario tolto (o aggiunto), per il report e per i check.
    public struct SecondaryChange: Sendable, Hashable {
        public let exerciseID: String
        public let name: String
        public let muscle: String
        /// `nil` quando il secondario è stato **aggiunto** (vedi ``addedSecondaries``).
        public let rule: SecondaryRule?

        public init(exerciseID: String, name: String, muscle: String, rule: SecondaryRule?) {
            self.exerciseID = exerciseID
            self.name = name
            self.muscle = muscle
            self.rule = rule
        }
    }

    /// Coppie antagoniste: quando il motore è la chiave, il valore non può lavorare
    /// in un esercizio di isolamento.
    public static let antagonists: [MuscleGroup: MuscleGroup] = [
        .quads: .hamstrings,
        .hamstrings: .quads,
        .biceps: .triceps,
        .triceps: .biceps,
    ]

    /// Pattern che identificano il lavoro di polso, dita e presa: lì l'unico muscolo
    /// coinvolto è l'avambraccio.
    public static let wristPatterns: [String] = [
        "wrist curl", "wrist roller", "wrist rollerer", "wrist circles", "wrist pull",
        "finger curl", "hand squeeze", "gripper", "pronation", "supination",
    ]

    /// Sinergisti evidenti che il dataset dimentica, aggiunti in coda ai secondari.
    ///
    /// L'elenco è volutamente cortissimo: l'audit a campione su tutti i gruppi
    /// principali ha trovato i secondari dei movimenti comuni già corretti (la panca
    /// ha tricipiti e spalle, le trazioni bicipiti e avambracci, lo squat glutei e
    /// femorali, i dip petto e spalle). Resta fuori solo lo **stacco convenzionale**,
    /// dove il quadricipite estende il ginocchio nello stacco da terra ma il dataset
    /// elenca solo femorali e lombari. Le varianti sumo e trap bar ce l'hanno già.
    public static let addedSecondaries: [String: [String]] = [
        "0032": ["quadriceps"],  // barbell deadlift
    ]

    /// Secondari ripuliti di un esercizio, nell'ordine originale.
    ///
    /// Funzione pura (id, nome, target corretto, secondari) così i check la possono
    /// interrogare senza costruire un repository. È **idempotente**: applicarla due
    /// volte dà lo stesso risultato.
    public static func cleanedSecondaries(
        id: String,
        name: String,
        target: String,
        secondaries: [String]
    ) -> [String] {
        let key = SearchText.normalize(name)
        let primary = MuscleGroup.forTarget(target)
        let isolation = SecondaryMuscles.isIsolation(primary: primary, normalizedName: key)

        var result: [String] = []
        var seen: Set<String> = []
        for muscle in secondaries {
            let term = SecondaryMuscles.normalizedTerm(muscle)
            guard !term.isEmpty, seen.insert(term).inserted else { continue }
            guard removalRule(term: term, targetTerm: target, primary: primary,
                              isolation: isolation, normalizedName: key) == nil
            else { continue }
            result.append(muscle)
        }
        for muscle in addedSecondaries[id] ?? [] where seen.insert(SecondaryMuscles.normalizedTerm(muscle)).inserted {
            result.append(muscle)
        }
        return result
    }

    /// Regola che fa cadere un secondario, `nil` se il secondario si tiene.
    public static func removalRule(
        term: String,
        targetTerm: String,
        primary: MuscleGroup,
        isolation: Bool,
        normalizedName: String
    ) -> SecondaryRule? {
        let group = MuscleGroup.forTarget(term)

        // 1. Duplicato letterale del principale (`forearms` fra i secondari di un
        //    wrist curl il cui target è già `forearms`). I duplicati di **zona**
        //    (`rhomboids` su un target `lats`, `soleus` su `calves`) restano nel dato
        //    perché alimentano la ricerca italiana ("romboidi", "soleo"): a scartarli
        //    ci pensa ``SecondaryMuscles/resolved(for:)``, che è ciò che entra nel
        //    calcolo e nella riga "Secondari" del dettaglio.
        if term == SecondaryMuscles.normalizedTerm(targetTerm) { return .duplicateOfPrimary }

        // 2. Antagonista in un isolamento: leg extension → hamstrings, leg curl →
        //    quadriceps, curl → triceps, pushdown → biceps. Fuori dagli isolamenti
        //    la co-contrazione esiste davvero (i femorali nello squat) e resta.
        if isolation, antagonists[primary] == group { return .antagonistInIsolation }

        // 3. Wrist curl e affini: tutto ciò che non è avambraccio è un errore.
        if primary == .forearms,
           wristPatterns.contains(where: { SearchText.contains(normalizedName, $0) }),
           [.biceps, .triceps, .shoulders, .chest, .back].contains(group) {
            return .absurdInWristWork
        }

        return nil
    }

    /// Elenco delle modifiche ai secondari su un'intera libreria (per report e check).
    public static func secondaryChanges(in exercises: [Exercise]) -> [SecondaryChange] {
        var result: [SecondaryChange] = []
        for exercise in exercises where !exercise.isCustom {
            let newTarget = correctedTarget(id: exercise.id, name: exercise.name, target: exercise.target)
            let target = newTarget ?? exercise.target
            let source = newTarget == nil
                ? exercise.secondaryMuscles
                : rebuiltSecondaries(of: exercise, newTarget: target)
            let key = SearchText.normalize(exercise.name)
            let primary = MuscleGroup.forTarget(target)
            let isolation = SecondaryMuscles.isIsolation(primary: primary, normalizedName: key)

            var seen: Set<String> = []
            for muscle in source {
                let term = SecondaryMuscles.normalizedTerm(muscle)
                guard !term.isEmpty, seen.insert(term).inserted else { continue }
                guard let rule = removalRule(term: term, targetTerm: target, primary: primary,
                                             isolation: isolation, normalizedName: key)
                else { continue }
                result.append(SecondaryChange(exerciseID: exercise.id, name: exercise.name, muscle: muscle, rule: rule))
            }
            for muscle in addedSecondaries[exercise.id] ?? []
            where !seen.contains(SecondaryMuscles.normalizedTerm(muscle)) {
                result.append(SecondaryChange(exerciseID: exercise.id, name: exercise.name, muscle: muscle, rule: nil))
            }
        }
        return result
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
