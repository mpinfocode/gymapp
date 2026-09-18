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
// ## Solo il muscolo principale
//
// Ogni serie è attribuita **interamente al gruppo muscolare principale**
// dell'esercizio (``MuscleGroup/forExercise(_:)``, che parte dal `target` già
// corretto da ``ExerciseCorrections``). I **muscoli secondari NON contano**:
// nel dataset sono inaffidabili (SPEC §2, punto 3: leg extension dichiara
// `hamstrings`, il pushdown dichiara `forearms`) e spalmare quote su di essi
// produrrebbe numeri falsi con l'aria di essere precisi. Gli esercizi
// personalizzati portano il gruppo scelto dall'utente, come tutti gli altri.
//
// Un esercizio il cui id non si risolve (libreria non ancora caricata, esercizio
// personalizzato cancellato) non viene attribuito a nessuno: è **escluso** dal
// totale e contato a parte in ``Stats/MuscleDistribution/unresolvedSets``, così
// la UI può dirlo invece di far sballare le percentuali.

extension Stats {

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
        /// Serie di lavoro attribuite alla zona.
        public let sets: Int
        /// Percentuale **già arrotondata** per la UI: la somma delle quote fa esattamente 100.
        public let percent: Int
        /// Quota esatta 0...1, per disegnare la barra senza l'errore d'arrotondamento.
        public let fraction: Double

        public var id: MuscleGroup { group }

        public init(group: MuscleGroup, sets: Int, percent: Int, fraction: Double) {
            self.group = group
            self.sets = sets
            self.percent = percent
            self.fraction = fraction
        }
    }

    /// Quota di una macro area.
    public struct MacroAreaShare: Sendable, Hashable, Identifiable {
        public let area: MuscleMacroArea
        public let sets: Int
        /// Percentuale arrotondata; la somma delle macro aree presenti fa 100.
        public let percent: Int
        public let fraction: Double

        public var id: MuscleMacroArea { area }

        public init(area: MuscleMacroArea, sets: Int, percent: Int, fraction: Double) {
            self.area = area
            self.sets = sets
            self.percent = percent
            self.fraction = fraction
        }
    }

    /// I muscoli colpiti da una scheda, in percentuale sulle serie di lavoro.
    public struct MuscleDistribution: Sendable, Hashable {

        /// Quote ordinate per serie decrescenti (a parità, nell'ordine di ``MuscleGroup/displayOrder``).
        public let shares: [MuscleShare]
        /// Serie di lavoro effettivamente attribuite (il denominatore delle percentuali).
        public let totalSets: Int
        /// Serie di esercizi non risolvibili, escluse dal totale.
        public let unresolvedSets: Int
        /// Quante voci di scheda non si è riusciti a risolvere.
        public let unresolvedItems: Int
        /// Zone rilevanti (vedi ``Stats/relevantMuscleGroups``) con zero serie dirette,
        /// nell'ordine di ``MuscleGroup/displayOrder``.
        public let missingGroups: [MuscleGroup]

        public init(
            shares: [MuscleShare],
            totalSets: Int,
            unresolvedSets: Int,
            unresolvedItems: Int,
            missingGroups: [MuscleGroup]
        ) {
            self.shares = shares
            self.totalSets = totalSets
            self.unresolvedSets = unresolvedSets
            self.unresolvedItems = unresolvedItems
            self.missingGroups = missingGroups
        }

        /// Distribuzione senza nemmeno una serie attribuita.
        public static let empty = MuscleDistribution(
            shares: [],
            totalSets: 0,
            unresolvedSets: 0,
            unresolvedItems: 0,
            missingGroups: relevantMuscleGroups
        )

        public var isEmpty: Bool { shares.isEmpty }

        /// Serie attribuite a una zona (0 se non compare).
        public func sets(of group: MuscleGroup) -> Int {
            shares.first { $0.group == group }?.sets ?? 0
        }

        /// Percentuale mostrata per una zona (0 se non compare).
        public func percent(of group: MuscleGroup) -> Int {
            shares.first { $0.group == group }?.percent ?? 0
        }

        /// Le prime `count` zone, per la riga compatta della Home.
        public func topShares(_ count: Int) -> [MuscleShare] {
            Array(shares.prefix(max(0, count)))
        }

        /// Vista aggregata per macro area (Parte alta / Gambe / Core), ordinata per
        /// serie decrescenti. Le zone fuori dalle macro aree (Avambracci, Cardio,
        /// Altro) non compaiono, quindi il totale può essere minore di ``totalSets``.
        public var macroAreas: [MacroAreaShare] {
            var setsByArea: [MuscleMacroArea: Int] = [:]
            for share in shares {
                guard let area = MuscleMacroArea.containing(share.group) else { continue }
                setsByArea[area, default: 0] += share.sets
            }
            let total = setsByArea.values.reduce(0, +)
            guard total > 0 else { return [] }

            let ordered = MuscleMacroArea.allCases
                .compactMap { area -> (MuscleMacroArea, Int)? in
                    guard let sets = setsByArea[area], sets > 0 else { return nil }
                    return (area, sets)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return areaRank(lhs.0) < areaRank(rhs.0)
                }
            let percents = largestRemainderPercents(ordered.map(\.1), total: total)
            return zip(ordered, percents).map { pair, percent in
                MacroAreaShare(
                    area: pair.0,
                    sets: pair.1,
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
    ///   - exercise: risolve un `Exercise.id`; `nil` se l'esercizio non esiste più.
    public static func muscleDistribution(
        items: [PlanItem],
        exercise: (String) -> Exercise?
    ) -> MuscleDistribution {
        var setsByGroup: [MuscleGroup: Int] = [:]
        var total = 0
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
            setsByGroup[MuscleGroup.forExercise(resolved), default: 0] += sets
            total += sets
        }

        let missing = relevantMuscleGroups.filter { (setsByGroup[$0] ?? 0) == 0 }

        guard total > 0 else {
            return MuscleDistribution(
                shares: [],
                totalSets: 0,
                unresolvedSets: unresolvedSets,
                unresolvedItems: unresolvedItems,
                missingGroups: missing
            )
        }

        let ordered = setsByGroup
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return groupRank(lhs.0) < groupRank(rhs.0)
            }
        let percents = largestRemainderPercents(ordered.map(\.1), total: total)
        let shares = zip(ordered, percents).map { pair, percent in
            MuscleShare(
                group: pair.0,
                sets: pair.1,
                percent: percent,
                fraction: Double(pair.1) / Double(total)
            )
        }

        return MuscleDistribution(
            shares: shares,
            totalSets: total,
            unresolvedSets: unresolvedSets,
            unresolvedItems: unresolvedItems,
            missingGroups: missing
        )
    }

    /// Distribuzione di un singolo giorno della scheda.
    public static func muscleDistribution(
        of day: ProgramDay,
        exercise: (String) -> Exercise?
    ) -> MuscleDistribution {
        muscleDistribution(items: day.items, exercise: exercise)
    }

    /// Distribuzione dell'intera scheda (tutti i giorni sommati).
    public static func muscleDistribution(
        of program: Program,
        exercise: (String) -> Exercise?
    ) -> MuscleDistribution {
        muscleDistribution(items: program.days.flatMap(\.items), exercise: exercise)
    }

    /// Variante con dizionario, comoda quando gli esercizi sono già stati raccolti.
    public static func muscleDistribution(
        of day: ProgramDay,
        exercisesByID: [String: Exercise]
    ) -> MuscleDistribution {
        muscleDistribution(items: day.items) { exercisesByID[$0] }
    }

    /// Variante con dizionario per l'intera scheda.
    public static func muscleDistribution(
        of program: Program,
        exercisesByID: [String: Exercise]
    ) -> MuscleDistribution {
        muscleDistribution(items: program.days.flatMap(\.items)) { exercisesByID[$0] }
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
