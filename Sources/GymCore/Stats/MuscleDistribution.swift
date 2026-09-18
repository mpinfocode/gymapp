import Foundation

// Distribuzione dei muscoli colpiti da una scheda (o da un suo giorno).
//
// Serve a una domanda sola, che l'utente si fa guardando la scheda dell'istruttore:
// "è completa? su cosa si concentra?". La risposta è una percentuale per zona.
//
// ## Come si pesa
//
// Il peso di un esercizio è il numero di **serie di lavoro previste**
// (``PlanItem/targetSets``): le serie di riscaldamento (``PlanItem/warmupSets``)
// non contano, perché non sono volume allenante. La durata, il carico e il numero
// di ripetizioni non entrano nel conto: una serie vale una serie, come si ragiona
// in palestra ("quante serie di petto fai a settimana?").
//
// ## Principale e secondari
//
// Ogni serie vale:
// - **1,0** per il gruppo muscolare principale (``Stats/directWeight``);
// - **0,5** per ogni gruppo secondario **sinergista** (``Stats/synergistWeight``):
//   i tricipiti nella panca, i bicipiti nel rematore, i glutei nello squat;
// - **0,25** per ogni gruppo secondario **stabilizzatore** (``Stats/stabilizerWeight``):
//   la presa negli stacchi, il core negli esercizi in piedi, i lombari di sostegno.
//
// I secondari arrivano da ``SecondaryMuscles/resolved(for:)``, che li traduce in
// zone, ne assegna il ruolo, toglie i duplicati del principale e ne tiene al
// massimo tre (``SecondaryMuscles/maximumPerExercise``). Gli errori grossolani del
// dataset (antagonisti negli isolamenti, assurdità nei wrist curl) sono già stati
// tolti al caricamento da ``ExerciseCorrections``.
//
// Il risultato per zona distingue la **quota diretta** (dal principale) da quella
// **indiretta** (dai secondari); le percentuali si calcolano sul **totale pesato** e
// sommano esattamente a 100. Tutti i pesi sono multipli di 0,25, quindi il conto
// gira su interi ("quarti di serie") e non ha errori d'arrotondamento.
//
// Gli esercizi personalizzati portano solo il gruppo scelto dall'utente: la scheda
// di creazione non chiede i secondari, quindi hanno soltanto quota diretta.
//
// Un esercizio il cui id non si risolve (libreria non ancora caricata, esercizio
// personalizzato cancellato) non viene attribuito a nessuno: è **escluso** dal
// totale e contato a parte in ``Stats/MuscleDistribution/unresolvedSets``, così
// la UI può dirlo invece di far sballare le percentuali.

extension Stats {

    // MARK: - Pesi

    /// Quanto vale una serie per il **muscolo principale** dell'esercizio.
    public static let directWeight: Double = 1

    /// Quanto vale una serie per un gruppo secondario **sinergista**
    /// (``MuscleRole/synergist``): metà del principale.
    ///
    /// Mezza serie è la traduzione numerica di come ragiona un preparatore: quattro
    /// serie di panca non sono quattro serie di tricipiti, ma nemmeno zero.
    public static let synergistWeight: Double = 0.5

    /// Quanto vale una serie per un gruppo secondario **stabilizzatore**
    /// (``MuscleRole/stabilizer``): un quarto del principale.
    public static let stabilizerWeight: Double = 0.25

    /// Peso di un ruolo secondario.
    public static func weight(for role: MuscleRole) -> Double {
        switch role {
        case .synergist: synergistWeight
        case .stabilizer: stabilizerWeight
        }
    }

    /// Lo stesso peso espresso in **quarti di serie**: il conto interno usa interi
    /// per non accumulare errori di virgola mobile.
    static func quarters(for role: MuscleRole) -> Int {
        Int((weight(for: role) * 4).rounded())
    }

    /// Quarti di serie del muscolo principale.
    static let directQuarters = 4

    // MARK: - Macro aree

    /// Raggruppamento grossolano delle zone, per una lettura d'insieme della scheda.
    ///
    /// Avambracci, Cardio e Altro non appartengono a nessuna macro area: sono
    /// residui o complementi, non uno dei tre blocchi di cui si valuta l'equilibrio.
    public enum MuscleMacroArea: String, Sendable, Hashable, CaseIterable, Identifiable {
        case upperBody
        case legs
        case core

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .upperBody: "Parte alta"
            case .legs: "Gambe"
            case .core: "Core"
            }
        }

        /// Zone che compongono la macro area, nell'ordine di ``MuscleGroup/displayOrder``.
        public var groups: [MuscleGroup] {
            switch self {
            case .upperBody: [.chest, .back, .shoulders, .biceps, .triceps]
            case .legs: [.quads, .hamstrings, .glutes, .calves]
            case .core: [.abs]
            }
        }

        /// Macro area di una zona, `nil` per Avambracci, Cardio e Altro.
        public static func containing(_ group: MuscleGroup) -> MuscleMacroArea? {
            allCases.first { $0.groups.contains(group) }
        }
    }

    // MARK: - Quote

    /// Quota di una zona muscolare dentro una scheda.
    public struct MuscleShare: Sendable, Hashable, Identifiable {
        public let group: MuscleGroup
        /// Serie attribuite alla zona come **muscolo principale** (peso 1,0 l'una).
        /// È sempre un intero, espresso in `Double` per stare accanto alle altre due.
        public let directSets: Double
        /// Serie pesate che arrivano dai **secondari** (0,5 sinergista, 0,25 stabilizzatore).
        public let indirectSets: Double
        /// Percentuale **già arrotondata** per la UI: la somma delle quote fa esattamente 100.
        public let percent: Int
        /// Quota esatta 0...1 del totale pesato, per disegnare la barra senza
        /// l'errore d'arrotondamento.
        public let fraction: Double

        public var id: MuscleGroup { group }

        /// Serie pesate totali della zona: ``directSets`` + ``indirectSets``.
        public var weightedSets: Double { directSets + indirectSets }

        /// La zona è toccata solo di riflesso, senza nemmeno una serie diretta.
        public var isIndirectOnly: Bool { directSets == 0 && indirectSets > 0 }

        /// Serie **dirette** come intero: è la vecchia `sets` (quando i secondari non
        /// contavano, l'unica quota possibile era quella diretta). Resta per non
        /// rompere il codice che la usa.
        public var sets: Int { Int(directSets.rounded()) }

        public init(group: MuscleGroup, directSets: Double, indirectSets: Double, percent: Int, fraction: Double) {
            self.group = group
            self.directSets = directSets
            self.indirectSets = indirectSets
            self.percent = percent
            self.fraction = fraction
        }

        /// Inizializzatore storico (sola quota diretta), mantenuto per compatibilità.
        public init(group: MuscleGroup, sets: Int, percent: Int, fraction: Double) {
            self.init(group: group, directSets: Double(sets), indirectSets: 0, percent: percent, fraction: fraction)
        }
    }

    /// Quota di una macro area.
    public struct MacroAreaShare: Sendable, Hashable, Identifiable {
        public let area: MuscleMacroArea
        /// Quota pesata della macro area, in **quarti di serie** (conto esatto).
        public let quarters: Int
        /// Percentuale arrotondata; la somma delle macro aree presenti fa 100.
        public let percent: Int
        public let fraction: Double

        public var id: MuscleMacroArea { area }

        /// Serie pesate della macro area.
        public var weightedSets: Double { Double(quarters) / 4 }

        /// Serie pesate arrotondate all'intero: è la vecchia `sets`, mantenuta per
        /// compatibilità con il codice che la legge.
        public var sets: Int { Int(weightedSets.rounded()) }

        public init(area: MuscleMacroArea, quarters: Int, percent: Int, fraction: Double) {
            self.area = area
            self.quarters = quarters
            self.percent = percent
            self.fraction = fraction
        }

        /// Inizializzatore storico (serie intere), mantenuto per compatibilità.
        public init(area: MuscleMacroArea, sets: Int, percent: Int, fraction: Double) {
            self.init(area: area, quarters: sets * 4, percent: percent, fraction: fraction)
        }
    }

    /// I muscoli colpiti da una scheda, in percentuale sulle serie di lavoro pesate.
    public struct MuscleDistribution: Sendable, Hashable {

        /// Quote ordinate per serie pesate decrescenti (a parità, nell'ordine di
        /// ``MuscleGroup/displayOrder``).
        public let shares: [MuscleShare]
        /// Serie di lavoro **dirette** attribuite: è il numero di serie che la scheda
        /// prevede davvero ("24 serie"), non il denominatore delle percentuali.
        public let totalSets: Int
        /// Totale pesato (dirette + indirette): **è il denominatore delle percentuali**.
        public let totalWeightedSets: Double
        /// Serie di esercizi non risolvibili, escluse dal totale.
        public let unresolvedSets: Int
        /// Quante voci di scheda non si è riusciti a risolvere.
        public let unresolvedItems: Int
        /// Zone rilevanti (vedi ``Stats/relevantMuscleGroups``) **mai** allenate:
        /// nemmeno come secondarie. Nell'ordine di ``MuscleGroup/displayOrder``.
        public let neverTrainedGroups: [MuscleGroup]
        /// Zone rilevanti allenate **solo indirettamente**: nessuna serie diretta ma
        /// quota indiretta maggiore di zero.
        public let indirectOnlyGroups: [MuscleGroup]

        /// Nome storico di ``neverTrainedGroups``, mantenuto per compatibilità.
        public var missingGroups: [MuscleGroup] { neverTrainedGroups }

        public init(
            shares: [MuscleShare],
            totalSets: Int,
            totalWeightedSets: Double,
            unresolvedSets: Int,
            unresolvedItems: Int,
            neverTrainedGroups: [MuscleGroup],
            indirectOnlyGroups: [MuscleGroup]
        ) {
            self.shares = shares
            self.totalSets = totalSets
            self.totalWeightedSets = totalWeightedSets
            self.unresolvedSets = unresolvedSets
            self.unresolvedItems = unresolvedItems
            self.neverTrainedGroups = neverTrainedGroups
            self.indirectOnlyGroups = indirectOnlyGroups
        }

        /// Inizializzatore storico (senza secondari), mantenuto per compatibilità.
        public init(
            shares: [MuscleShare],
            totalSets: Int,
            unresolvedSets: Int,
            unresolvedItems: Int,
            missingGroups: [MuscleGroup]
        ) {
            self.init(
                shares: shares,
                totalSets: totalSets,
                totalWeightedSets: shares.reduce(0) { $0 + $1.weightedSets },
                unresolvedSets: unresolvedSets,
                unresolvedItems: unresolvedItems,
                neverTrainedGroups: missingGroups,
                indirectOnlyGroups: []
            )
        }

        /// Distribuzione senza nemmeno una serie attribuita.
        public static let empty = MuscleDistribution(
            shares: [],
            totalSets: 0,
            totalWeightedSets: 0,
            unresolvedSets: 0,
            unresolvedItems: 0,
            neverTrainedGroups: relevantMuscleGroups,
            indirectOnlyGroups: []
        )

        public var isEmpty: Bool { shares.isEmpty }

        private func share(_ group: MuscleGroup) -> MuscleShare? {
            shares.first { $0.group == group }
        }

        /// Serie **dirette** attribuite a una zona (0 se non compare).
        public func sets(of group: MuscleGroup) -> Int { share(group)?.sets ?? 0 }

        /// Serie dirette come quota (0 se non compare).
        public func directSets(of group: MuscleGroup) -> Double { share(group)?.directSets ?? 0 }

        /// Quota indiretta di una zona, dai secondari (0 se non compare).
        public func indirectSets(of group: MuscleGroup) -> Double { share(group)?.indirectSets ?? 0 }

        /// Quota pesata totale di una zona (0 se non compare).
        public func weightedSets(of group: MuscleGroup) -> Double { share(group)?.weightedSets ?? 0 }

        /// Percentuale mostrata per una zona (0 se non compare).
        public func percent(of group: MuscleGroup) -> Int { share(group)?.percent ?? 0 }

        /// Le prime `count` zone, per la riga compatta della Home.
        public func topShares(_ count: Int) -> [MuscleShare] {
            Array(shares.prefix(max(0, count)))
        }

        /// Vista aggregata per macro area (Parte alta / Gambe / Core), ordinata per
        /// quota pesata decrescente. Le zone fuori dalle macro aree (Avambracci,
        /// Cardio, Altro) non compaiono, quindi il totale può essere minore di
        /// ``totalWeightedSets``.
        public var macroAreas: [MacroAreaShare] {
            // Il conto gira in quarti di serie: i pesi sono tutti multipli di 0,25.
            var quartersByArea: [MuscleMacroArea: Int] = [:]
            for share in shares {
                guard let area = MuscleMacroArea.containing(share.group) else { continue }
                quartersByArea[area, default: 0] += Int((share.weightedSets * 4).rounded())
            }
            let total = quartersByArea.values.reduce(0, +)
            guard total > 0 else { return [] }

            let ordered = MuscleMacroArea.allCases
                .compactMap { area -> (MuscleMacroArea, Int)? in
                    guard let quarters = quartersByArea[area], quarters > 0 else { return nil }
                    return (area, quarters)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return areaRank(lhs.0) < areaRank(rhs.0)
                }
            let percents = largestRemainderPercents(ordered.map(\.1), total: total)
            return zip(ordered, percents).map { pair, percent in
                MacroAreaShare(
                    area: pair.0,
                    quarters: pair.1,
                    percent: percent,
                    fraction: Double(pair.1) / Double(total)
                )
            }
        }

        private func areaRank(_ area: MuscleMacroArea) -> Int {
            MuscleMacroArea.allCases.firstIndex(of: area) ?? 0
        }
    }

    // MARK: - Zone che ci si aspetta di allenare

    /// Zone di cui ha senso dire "non allenata direttamente".
    ///
    /// Restano fuori **Cardio** (non è forza), **Avambracci** (si allenano di
    /// riflesso in ogni tirata: dirli mancanti sarebbe un falso allarme) e
    /// **Altro** (non è una zona, è il cestino di chi non si è potuto classificare).
    public static let relevantMuscleGroups: [MuscleGroup] = [
        .chest, .back, .shoulders, .biceps, .triceps,
        .quads, .hamstrings, .glutes, .calves, .abs,
    ]

    // MARK: - Calcolo

    /// Distribuzione dei muscoli colpiti da un elenco di voci di scheda.
    ///
    /// È la funzione pura di base: gli esercizi si risolvono con la closure passata,
    /// nessun accesso allo store.
    ///
    /// - Parameters:
    ///   - items: le voci di scheda da pesare.
    ///   - includesSecondary: `true` (predefinito) conta anche i muscoli secondari
    ///     con i pesi ``synergistWeight`` e ``stabilizerWeight``; `false` torna al
    ///     comportamento storico "solo il muscolo principale".
    ///   - exercise: risolve un `Exercise.id`; `nil` se l'esercizio non esiste più.
    public static func muscleDistribution(
        items: [PlanItem],
        includesSecondary: Bool = true,
        exercise: (String) -> Exercise?
    ) -> MuscleDistribution {
        // Tutto in quarti di serie: il principale vale 4, un sinergista 2, uno
        // stabilizzatore 1. Interi, quindi somme esatte e arrotondamenti prevedibili.
        var directQuartersByGroup: [MuscleGroup: Int] = [:]
        var indirectQuartersByGroup: [MuscleGroup: Int] = [:]
        var directSets = 0
        var unresolvedSets = 0
        var unresolvedItems = 0

        for item in items {
            let sets = max(0, item.targetSets)
            guard let resolved = exercise(item.exerciseID) else {
                unresolvedItems += 1
                unresolvedSets += sets
                continue
            }
            guard sets > 0 else { continue }

            let primary = MuscleGroup.forExercise(resolved)
            directQuartersByGroup[primary, default: 0] += sets * directQuarters
            directSets += sets

            guard includesSecondary else { continue }
            for secondary in SecondaryMuscles.resolved(for: resolved) {
                indirectQuartersByGroup[secondary.group, default: 0] += sets * quarters(for: secondary.role)
            }
        }

        var totalQuarters = 0
        var groups: Set<MuscleGroup> = []
        for (group, quarters) in directQuartersByGroup {
            totalQuarters += quarters
            groups.insert(group)
        }
        for (group, quarters) in indirectQuartersByGroup {
            totalQuarters += quarters
            groups.insert(group)
        }

        let neverTrained = relevantMuscleGroups.filter {
            (directQuartersByGroup[$0] ?? 0) == 0 && (indirectQuartersByGroup[$0] ?? 0) == 0
        }
        let indirectOnly = relevantMuscleGroups.filter {
            (directQuartersByGroup[$0] ?? 0) == 0 && (indirectQuartersByGroup[$0] ?? 0) > 0
        }

        guard totalQuarters > 0 else {
            return MuscleDistribution(
                shares: [],
                totalSets: 0,
                totalWeightedSets: 0,
                unresolvedSets: unresolvedSets,
                unresolvedItems: unresolvedItems,
                neverTrainedGroups: neverTrained,
                indirectOnlyGroups: indirectOnly
            )
        }

        let ordered = groups
            .map { ($0, (directQuartersByGroup[$0] ?? 0) + (indirectQuartersByGroup[$0] ?? 0)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return groupRank(lhs.0) < groupRank(rhs.0)
            }
        let percents = largestRemainderPercents(ordered.map(\.1), total: totalQuarters)
        let shares = zip(ordered, percents).map { pair, percent in
            MuscleShare(
                group: pair.0,
                directSets: Double(directQuartersByGroup[pair.0] ?? 0) / 4,
                indirectSets: Double(indirectQuartersByGroup[pair.0] ?? 0) / 4,
                percent: percent,
                fraction: Double(pair.1) / Double(totalQuarters)
            )
        }

        return MuscleDistribution(
            shares: shares,
            totalSets: directSets,
            totalWeightedSets: Double(totalQuarters) / 4,
            unresolvedSets: unresolvedSets,
            unresolvedItems: unresolvedItems,
            neverTrainedGroups: neverTrained,
            indirectOnlyGroups: indirectOnly
        )
    }

    /// Distribuzione di un singolo giorno della scheda.
    public static func muscleDistribution(
        of day: ProgramDay,
        includesSecondary: Bool = true,
        exercise: (String) -> Exercise?
    ) -> MuscleDistribution {
        muscleDistribution(items: day.items, includesSecondary: includesSecondary, exercise: exercise)
    }

    /// Distribuzione dell'intera scheda (tutti i giorni sommati).
    public static func muscleDistribution(
        of program: Program,
        includesSecondary: Bool = true,
        exercise: (String) -> Exercise?
    ) -> MuscleDistribution {
        muscleDistribution(
            items: program.days.flatMap(\.items),
            includesSecondary: includesSecondary,
            exercise: exercise
        )
    }

    /// Variante con dizionario, comoda quando gli esercizi sono già stati raccolti.
    public static func muscleDistribution(
        of day: ProgramDay,
        exercisesByID: [String: Exercise],
        includesSecondary: Bool = true
    ) -> MuscleDistribution {
        muscleDistribution(items: day.items, includesSecondary: includesSecondary) { exercisesByID[$0] }
    }

    /// Variante con dizionario per l'intera scheda.
    public static func muscleDistribution(
        of program: Program,
        exercisesByID: [String: Exercise],
        includesSecondary: Bool = true
    ) -> MuscleDistribution {
        muscleDistribution(items: program.days.flatMap(\.items), includesSecondary: includesSecondary) {
            exercisesByID[$0]
        }
    }

    // MARK: - Arrotondamento

    /// Percentuali intere che sommano **esattamente** a 100 (metodo del resto maggiore).
    ///
    /// Si arrotonda per difetto, poi i punti che avanzano vanno alle quote con il
    /// resto più grande (a parità, a quella che viene prima). Senza questo passaggio
    /// una scheda da 3 giorni uguali mostrerebbe "33% · 33% · 33%" (99) e una da
    /// 6 esercizi "17% × 6" (102).
    static func largestRemainderPercents(_ values: [Int], total: Int) -> [Int] {
        guard total > 0, !values.isEmpty else { return values.map { _ in 0 } }

        var percents = values.map { $0 * 100 / total }
        let assigned = percents.reduce(0, +)
        var leftover = 100 - assigned
        guard leftover > 0 else { return percents }

        let byRemainder = values.indices.sorted { lhs, rhs in
            let remainderLhs = values[lhs] * 100 % total
            let remainderRhs = values[rhs] * 100 % total
            if remainderLhs != remainderRhs { return remainderLhs > remainderRhs }
            return lhs < rhs
        }
        var cursor = 0
        while leftover > 0 && !byRemainder.isEmpty {
            percents[byRemainder[cursor % byRemainder.count]] += 1
            leftover -= 1
            cursor += 1
        }
        return percents
    }

    private static func groupRank(_ group: MuscleGroup) -> Int {
        MuscleGroup.displayOrder.firstIndex(of: group) ?? MuscleGroup.displayOrder.count
    }
}

// MARK: - Scorciatoie dallo store

extension AppStore {

    /// Muscoli colpiti da una scheda, risolvendo gli esercizi con libreria e personalizzati.
    public func muscleDistribution(for program: Program) -> Stats.MuscleDistribution {
        Stats.muscleDistribution(of: program, exercisesByID: allExercisesByID())
    }

    /// Muscoli colpiti da un solo giorno.
    public func muscleDistribution(for day: ProgramDay) -> Stats.MuscleDistribution {
        Stats.muscleDistribution(of: day, exercisesByID: allExercisesByID())
    }

    /// Muscoli colpiti dalla scheda attiva; distribuzione vuota se non ce n'è una.
    public func activeProgramMuscleDistribution() -> Stats.MuscleDistribution {
        guard let program = activeProgram else { return .empty }
        return muscleDistribution(for: program)
    }
}
