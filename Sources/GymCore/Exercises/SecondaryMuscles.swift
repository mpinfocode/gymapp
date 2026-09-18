import Foundation

/// Ruolo di un muscolo secondario dentro un esercizio.
///
/// Il dataset elenca i secondari alla rinfusa, senza dire quanto lavorino: il
/// tricipite nella panca e l'avambraccio nelle trazioni stanno nella stessa lista,
/// ma il primo spinge il bilanciere e il secondo tiene soltanto la presa. La
/// distinzione serve al calcolo della ripartizione, dove pesano in modo diverso
/// (vedi ``Stats/synergistWeight`` e ``Stats/stabilizerWeight``).
public enum MuscleRole: String, Sendable, Hashable, Codable, CaseIterable {
    /// Contribuisce davvero al movimento: tricipiti nella panca, bicipiti nel
    /// rematore, glutei nello squat.
    case synergist
    /// Tiene la posizione o la presa senza produrre il movimento: avambracci nelle
    /// trazioni e negli stacchi, core negli esercizi in piedi, lombari come sostegno.
    case stabilizer

    /// Etichetta italiana, per i check e per un eventuale uso in UI.
    public var displayName: String {
        switch self {
        case .synergist: "Sinergista"
        case .stabilizer: "Stabilizzatore"
        }
    }
}

/// Un muscolo secondario già risolto: zona "da palestra" + ruolo.
public struct SecondaryMuscle: Sendable, Hashable, Identifiable {
    public let group: MuscleGroup
    public let role: MuscleRole

    public var id: MuscleGroup { group }

    public init(group: MuscleGroup, role: MuscleRole) {
        self.group = group
        self.role = role
    }
}

/// Da `secondary_muscles` (stringhe inglesi libere) ai gruppi muscolari con un ruolo.
///
/// ## Perché serve uno strato
/// `secondary_muscles` è testo libero: 40 valori distinti, dal preciso
/// (`rear deltoids`) al generico (`core`), con sinonimi (`traps` / `trapezius`,
/// `lats` / `latissimus dorsi`) e duplicati del muscolo principale
/// (`forearms` fra i secondari di un wrist curl). Gli errori grossolani vengono
/// tolti prima, al caricamento, da ``ExerciseCorrections``; qui si traduce quello
/// che resta in zone ``MuscleGroup`` e gli si assegna un ruolo.
///
/// ## Le regole del ruolo
/// Il ruolo di base è **sinergista**; si scende a **stabilizzatore** in questi casi,
/// nell'ordine (il primo che si applica vince):
///
/// | # | Regola | Esempio |
/// |---|--------|---------|
/// | 0 | Zona **Avambracci** con principale **Bicipiti**: resta sinergista anche nei curl (il brachioradiale flette il gomito) | curl, hammer curl → Avambracci |
/// | 1 | Esercizio di **isolamento** (vedi ``isIsolation(primary:name:)``): nessun secondario è motore | croci ai cavi → Spalle, Tricipiti |
/// | 2 | Zona **Avambracci** (presa) | trazioni, stacco → Avambracci |
/// | 3 | Zona **Addome** con principale diverso da Addome (core in piedi) | squat, lento avanti → Addome |
/// | 4 | Termini **lombari** (`lower back`, `spine`) | stacco → Dorso |
/// | 5 | `rotator cuff` (cuffia dei rotatori) | lento avanti → Spalle |
/// | 6 | Zona **Polpacci** in un esercizio di gamba (il soleo stabilizza la caviglia) | squat, affondi → Polpacci |
/// | 7 | Zona **Dorso** in una spinta (principale Petto, Spalle o Tricipiti): è postura | lento avanti → Dorso |
///
/// Tutto il resto resta sinergista: tricipiti e spalle nella panca, bicipiti nelle
/// trazioni e nel rematore, glutei e femorali nello squat, quadricipiti nella pressa.
public enum SecondaryMuscles {

    /// Quanti secondari al massimo entrano nel conto per un esercizio.
    ///
    /// Oltre il terzo si scende nel rumore: il dataset arriva a 6 secondari e
    /// sommarli tutti gonfierebbe le zone "di contorno" fino a superare il muscolo
    /// che l'esercizio allena davvero.
    public static let maximumPerExercise = 3

    // MARK: - Risoluzione

    /// Secondari di un esercizio, tradotti in zone, senza duplicati e al massimo
    /// ``maximumPerExercise``.
    ///
    /// Passaggi, nell'ordine:
    /// 1. ogni termine diventa una ``MuscleGroup`` (``MuscleGroup/forTarget(_:)``);
    /// 2. si scartano ``MuscleGroup/other`` e ``MuscleGroup/cardio`` (non sono zone
    ///    su cui abbia senso attribuire lavoro) e la zona del muscolo **principale**
    ///    (sarebbe contata due volte);
    /// 3. si assegna il ruolo (vedi la tabella di ``SecondaryMuscles``);
    /// 4. si deduplica per zona, tenendo il ruolo migliore (`rhomboids` + `upper back`
    ///    sono una sola voce "Dorso");
    /// 5. si ordina mettendo i sinergisti prima degli stabilizzatori, a parità
    ///    nell'ordine del dataset, e si tengono i primi tre.
    public static func resolved(for exercise: Exercise) -> [SecondaryMuscle] {
        resolved(
            terms: exercise.secondaryMuscles,
            primary: MuscleGroup.forExercise(exercise),
            name: exercise.name
        )
    }

    /// Variante pura, senza `Exercise`: comoda per i check.
    public static func resolved(terms: [String], primary: MuscleGroup, name: String) -> [SecondaryMuscle] {
        let key = SearchText.normalize(name)
        let isolation = isIsolation(primary: primary, normalizedName: key)

        var order: [MuscleGroup] = []
        var roles: [MuscleGroup: MuscleRole] = [:]

        for term in terms {
            let normalized = normalizedTerm(term)
            guard !normalized.isEmpty else { continue }
            let group = MuscleGroup.forTarget(normalized)
            guard group != .other, group != .cardio, group != primary else { continue }

            let role = self.role(term: normalized, group: group, primary: primary, isolation: isolation)
            if let existing = roles[group] {
                if existing == .stabilizer && role == .synergist { roles[group] = .synergist }
            } else {
                roles[group] = role
                order.append(group)
            }
        }

        let resolved = order.map { SecondaryMuscle(group: $0, role: roles[$0] ?? .stabilizer) }
        let sorted = resolved.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.role != rhs.element.role { return lhs.element.role == .synergist }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        return Array(sorted.prefix(maximumPerExercise))
    }

    /// Solo le zone secondarie, nell'ordine di ``resolved(for:)``: è la riga
    /// "Secondari: …" del dettaglio esercizio.
    public static func groups(for exercise: Exercise) -> [MuscleGroup] {
        resolved(for: exercise).map(\.group)
    }

    // MARK: - Ruolo

    /// Termini che indicano presa, polso e mano: reggono il carico, non lo muovono.
    public static let gripTerms: Set<String> = [
        "forearms", "grip muscles", "wrists", "wrist flexors", "wrist extensors", "hands",
    ]

    /// Termini della zona lombare e della colonna: sostegno, mai motore.
    public static let lowerBackTerms: Set<String> = ["lower back", "spine"]

    /// Ruolo di un singolo secondario già normalizzato.
    ///
    /// - Parameters:
    ///   - term: termine inglese del dataset, minuscolo e senza spazi ai bordi.
    ///   - group: zona a cui il termine è stato ricondotto.
    ///   - primary: zona del muscolo principale dell'esercizio.
    ///   - isolation: l'esercizio è un isolamento (vedi ``isIsolation(primary:name:)``).
    public static func role(
        term: String,
        group: MuscleGroup,
        primary: MuscleGroup,
        isolation: Bool
    ) -> MuscleRole {
        // L'eccezione degli avambracci viene prima dell'isolamento: il curl è
        // monoarticolare, ma il brachioradiale flette il gomito insieme al bicipite.
        // Lì l'avambraccio è un motore, non una presa.
        if group == .forearms, primary == .biceps { return .synergist }       // 2
        if isolation { return .stabilizer }                                   // 1
        if group == .forearms { return .stabilizer }                          // 2
        if group == .abs { return .stabilizer }                               // 3 (primary == .abs già escluso)
        if lowerBackTerms.contains(term) { return .stabilizer }               // 4
        if term == "rotator cuff" { return .stabilizer }                      // 5
        if group == .calves, primary == .quads || primary == .hamstrings || primary == .glutes {
            return .stabilizer                                                // 6
        }
        if group == .back, primary == .chest || primary == .shoulders || primary == .triceps {
            return .stabilizer                                                // 7
        }
        return .synergist
    }

    // MARK: - Isolamento

    /// Pattern di nome che identificano un isolamento, per zona del muscolo principale.
    ///
    /// Un isolamento è un movimento a una sola articolazione: intorno al motore non
    /// c'è nessun altro muscolo che *produce* il movimento, quindi tutto ciò che il
    /// dataset elenca come secondario è al massimo uno stabilizzatore (nelle croci ai
    /// cavi il tricipite non spinge: tiene il gomito fermo).
    ///
    /// L'elenco è per gruppo perché la stessa parola cambia senso: "extension" è un
    /// isolamento per i tricipiti (french press) ma non per il dorso
    /// (back extension, che è una cerniera d'anca con glutei e femorali motori).
    public static let isolationPatterns: [MuscleGroup: [String]] = [
        .chest: ["fly", "flye", "crossover", "cross over", "pec deck"],
        .back: ["shrug", "straight arm", "pullover", "pull over"],
        .shoulders: ["raise", "reverse fly", "rear delt"],
        .biceps: ["curl"],
        .triceps: ["extension", "pushdown", "push down", "kickback", "kick back", "skull", "french"],
        .quads: ["leg extension", "knee extension"],
        .hamstrings: ["leg curl", "hamstring curl"],
    ]

    /// Zone che si allenano **solo** con esercizi di isolamento: qualunque sia il
    /// nome, nessun secondario è un motore del movimento.
    ///
    /// Addome e Polpacci sono monoarticolari per definizione (un crunch non ha
    /// sinergisti: le spalle che il dataset elenca nel plank tengono la posizione);
    /// Avambracci idem (wrist curl, presa).
    public static let alwaysIsolationGroups: Set<MuscleGroup> = [.abs, .calves, .forearms]

    /// L'esercizio è un isolamento monoarticolare?
    public static func isIsolation(primary: MuscleGroup, name: String) -> Bool {
        isIsolation(primary: primary, normalizedName: SearchText.normalize(name))
    }

    static func isIsolation(primary: MuscleGroup, normalizedName: String) -> Bool {
        if alwaysIsolationGroups.contains(primary) { return true }
        guard let patterns = isolationPatterns[primary] else { return false }
        return patterns.contains { SearchText.contains(normalizedName, $0) }
    }

    // MARK: - Utility

    static func normalizedTerm(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Exercise {

    /// Muscoli secondari già risolti in zone con il loro ruolo (vedi ``SecondaryMuscles``).
    public var secondaryMuscleRoles: [SecondaryMuscle] { SecondaryMuscles.resolved(for: self) }

    /// Zone secondarie dell'esercizio, senza duplicati e al massimo tre.
    public var secondaryMuscleGroups: [MuscleGroup] { SecondaryMuscles.groups(for: self) }

    /// Nomi italiani delle zone secondarie, pronti per la riga "Secondari: …".
    public var localizedSecondaryMuscleGroups: [String] {
        secondaryMuscleGroups.map(\.displayName)
    }
}
