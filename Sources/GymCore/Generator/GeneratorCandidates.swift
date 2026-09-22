import Foundation

/// Un esercizio proposto al modello, con le sole informazioni che gli servono
/// per sceglierlo.
public struct GeneratorCandidate: Sendable, Hashable, Identifiable {

    public let id: String
    /// Titolo senza il prefisso dell'attrezzo (SPEC §0): `"Lateral Raise"`.
    public let shortName: String
    public let group: MuscleGroup
    /// Attrezzo in italiano (`"Manubri"`, `"Cavi"`…).
    public let equipment: String
    public let pattern: MovementPattern
    public let kind: ExerciseKind
    public let level: TrainingLevel
    public let equipmentClass: EquipmentClass
    public let priority: Int
    /// Tutte le zone toccate, a qualunque livello (compatibilità e rapporti).
    public let stress: Set<StressZone>
    /// Zone che escludono l'esercizio dai candidati.
    public let avoidZones: Set<StressZone>
    /// Zone che lo ammettono con cautela: uno per seduta, mai per primo.
    public let cautionZones: Set<StressZone>

    public init(resolved: ResolvedExercise) {
        id = resolved.id
        shortName = resolved.shortName
        group = resolved.group
        equipment = resolved.localizedEquipment
        pattern = resolved.pattern
        kind = resolved.kind
        level = resolved.level
        equipmentClass = resolved.equipmentClass
        priority = resolved.priority
        stress = resolved.stress
        avoidZones = resolved.avoidZones
        cautionZones = resolved.cautionZones
    }

    /// `true` se con quelle zone da proteggere l'esercizio va usato con cautela.
    public func needsCare(protectedZones: Set<StressZone>) -> Bool {
        !cautionZones.isDisjoint(with: protectedZones)
    }

    /// Riga compatta per il modello:
    /// `id|nome breve|gruppo|attrezzo|schema motorio|M o I`.
    ///
    /// Un separatore solo, nessun JSON: è la forma più corta che un modello
    /// economico legge senza sbagliare, e costa circa 20 token a riga.
    public var compactLine: String { compactLine(protectedZones: []) }

    /// La riga compatta, con `!` in fondo quando l'esercizio tocca una zona da
    /// proteggere e va quindi usato con cautela.
    ///
    /// Un carattere solo: il modello deve capire "questo è ammesso ma
    /// delicato" senza che la riga raddoppi di lunghezza.
    public func compactLine(protectedZones: Set<StressZone>) -> String {
        let base = "\(id)|\(shortName)|\(group.displayName)|\(equipment)|\(pattern.displayName)|\(kind.compactCode)"
        return needsCare(protectedZones: protectedZones) ? base + "|!" : base
    }
}

/// L'elenco ristretto di esercizi fra cui scegliere, ricavato dalle risposte.
///
/// Il telefono fa il lavoro di selezione (attrezzatura, livello, zone da
/// proteggere, priorità) e manda al modello 90-140 righe invece di 1.324
/// esercizi: costa meno, sbaglia meno, e gli id restano verificabili.
public struct GeneratorCandidates: Sendable {

    /// Quanti esercizi al massimo per gruppo muscolare.
    public static let defaultLimitPerGroup = 14
    /// Tetto complessivo di righe mandate al modello.
    public static let defaultLimitTotal = 140
    /// Quanti esercizi si tengono comunque per ogni schema motorio richiesto
    /// dalla scheda, prima di riempire il resto.
    public static let reservedPerPattern = 5

    public let answers: GeneratorAnswers
    public let items: [GeneratorCandidate]

    private let index: [String: GeneratorCandidate]

    public init(answers: GeneratorAnswers, items: [GeneratorCandidate]) {
        self.answers = answers
        self.items = items
        index = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Costruzione

    /// Calcola i candidati per quelle risposte.
    ///
    /// Passi: si scarta ciò che non è fattibile (attrezzatura, esperienza, zone
    /// da proteggere), si riservano i posti agli schemi motori che la scheda
    /// richiede davvero, poi si riempie fino al tetto seguendo la priorità.
    public static func make(
        answers: GeneratorAnswers,
        library: some ExerciseSource,
        parameters: GeneratorPlanParameters? = nil,
        limitPerGroup: Int = defaultLimitPerGroup,
        limitTotal: Int = defaultLimitTotal
    ) -> GeneratorCandidates {
        let plan = parameters ?? GeneratorPlanParameters(answers: answers)
        let available = answers.equipment.equipmentClass
        let maxLevel = answers.experience.maxExerciseLevel

        let eligible = CuratedExercisePool.resolved(in: library)
            .filter { resolved in
                guard resolved.group != .other else { return false }
                guard resolved.curated.suits(equipment: available) else { return false }
                guard resolved.curated.suits(level: maxLevel) else { return false }
                // Solo le zone `avoid` escludono: quelle `caution` restano
                // nell'elenco, segnalate, e il resto del motore le tiene a bada.
                guard resolved.curated.respects(protectedZones: answers.protectedZones) else { return false }
                // Il cardio entra solo se richiesto: altrimenti sono righe sprecate.
                if resolved.pattern == .cardio { return answers.includeCardio }
                return true
            }
            .map(GeneratorCandidate.init(resolved:))
            .sorted { isBetter($0, $1, protectedZones: answers.protectedZones) }

        var neededPatterns: Set<MovementPattern> = []
        for day in plan.days { neededPatterns.formUnion(day.allPatterns) }
        if answers.includeCardio { neededPatterns.insert(.cardio) }

        var chosen: [GeneratorCandidate] = []
        var takenIDs: Set<String> = []
        var perGroup: [MuscleGroup: Int] = [:]

        func take(_ candidate: GeneratorCandidate, ignoringGroupLimit: Bool) -> Bool {
            guard !takenIDs.contains(candidate.id), chosen.count < limitTotal else { return false }
            let used = perGroup[candidate.group] ?? 0
            let cap = answers.focusGroups.contains(candidate.group) ? limitPerGroup + 2 : limitPerGroup
            guard ignoringGroupLimit || used < cap else { return false }
            chosen.append(candidate)
            takenIDs.insert(candidate.id)
            perGroup[candidate.group] = used + 1
            return true
        }

        // 1. Posti riservati agli schemi motori che servono ai giorni previsti.
        for pattern in MovementPattern.allCases where neededPatterns.contains(pattern) {
            var kept = 0
            for candidate in eligible where candidate.pattern == pattern {
                guard kept < reservedPerPattern else { break }
                if take(candidate, ignoringGroupLimit: true) { kept += 1 }
            }
        }

        // 2. Il resto per priorità, rispettando i tetti.
        for candidate in eligible {
            guard chosen.count < limitTotal else { break }
            guard neededPatterns.contains(candidate.pattern) else { continue }
            _ = take(candidate, ignoringGroupLimit: false)
        }

        // Ordine finale: per gruppo e schema motorio, così l'elenco si legge.
        let ordered = chosen.sorted { lhs, rhs in
            let l = MuscleGroup.displayOrder.firstIndex(of: lhs.group) ?? 99
            let r = MuscleGroup.displayOrder.firstIndex(of: rhs.group) ?? 99
            if l != r { return l < r }
            if lhs.pattern != rhs.pattern {
                let lp = MovementPattern.allCases.firstIndex(of: lhs.pattern) ?? 99
                let rp = MovementPattern.allCases.firstIndex(of: rhs.pattern) ?? 99
                return lp < rp
            }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.id < rhs.id
        }

        return GeneratorCandidates(answers: answers, items: ordered)
    }

    /// Ordine di preferenza: prima quel che non tocca una zona da proteggere,
    /// poi i classici, poi ciò che serve meno attrezzatura (funziona ovunque),
    /// poi il livello più accessibile.
    /// L'id chiude sempre il confronto: la selezione deve essere deterministica.
    static func isBetter(
        _ lhs: GeneratorCandidate,
        _ rhs: GeneratorCandidate,
        protectedZones: Set<StressZone>
    ) -> Bool {
        let lc = lhs.needsCare(protectedZones: protectedZones)
        let rc = rhs.needsCare(protectedZones: protectedZones)
        if lc != rc { return !lc }
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        if lhs.equipmentClass.rank != rhs.equipmentClass.rank { return lhs.equipmentClass.rank > rhs.equipmentClass.rank }
        if lhs.level.rank != rhs.level.rank { return lhs.level.rank < rhs.level.rank }
        return lhs.id < rhs.id
    }

    /// Versione a due argomenti, per gli usi in cui le zone non contano.
    static func isBetter(_ lhs: GeneratorCandidate, _ rhs: GeneratorCandidate) -> Bool {
        isBetter(lhs, rhs, protectedZones: [])
    }

    // MARK: - Interrogazione

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    public func candidate(id: String) -> GeneratorCandidate? { index[id] }
    public func contains(id: String) -> Bool { index[id] != nil }

    /// `true` se quell'esercizio tocca una delle zone da proteggere richieste.
    public func needsCare(_ candidate: GeneratorCandidate) -> Bool {
        candidate.needsCare(protectedZones: answers.protectedZones)
    }

    /// Ordine di preferenza che tiene conto delle zone da proteggere.
    public func isBetter(_ lhs: GeneratorCandidate, _ rhs: GeneratorCandidate) -> Bool {
        GeneratorCandidates.isBetter(lhs, rhs, protectedZones: answers.protectedZones)
    }

    /// Candidati con quello schema motorio, nell'ordine di preferenza.
    public func items(pattern: MovementPattern) -> [GeneratorCandidate] {
        items.filter { $0.pattern == pattern }.sorted(by: isBetter)
    }

    /// Candidati di quel gruppo muscolare, nell'ordine di preferenza.
    public func items(group: MuscleGroup) -> [GeneratorCandidate] {
        items.filter { $0.group == group }.sorted(by: isBetter)
    }

    /// Quanti candidati per gruppo muscolare.
    public var countsByGroup: [MuscleGroup: Int] {
        items.reduce(into: [:]) { $0[$1.group, default: 0] += 1 }
    }

    /// Quanti candidati per schema motorio.
    public var countsByPattern: [MovementPattern: Int] {
        items.reduce(into: [:]) { $0[$1.pattern, default: 0] += 1 }
    }

    // MARK: - Serializzazione per il modello

    /// L'elenco compatto, una riga per esercizio, con il segno `!` sui candidati
    /// da usare con cautela per via delle zone da proteggere.
    public var compactList: String {
        items.map { $0.compactLine(protectedZones: answers.protectedZones) }.joined(separator: "\n")
    }

    /// `true` se almeno un candidato porta il segno della cautela.
    public var hasCautionItems: Bool { items.contains(where: needsCare) }

    /// Stima dei token dell'elenco.
    public var estimatedTokens: Int { GeneratorCandidates.estimateTokens(compactList) }

    /// Stima grossolana dei token di un testo italiano: circa 3,6 caratteri per
    /// token. Serve solo a tenere il prompt sotto una soglia, non a fatturare.
    public static func estimateTokens(_ text: String) -> Int {
        Int((Double(text.count) / 3.6).rounded(.up))
    }
}
