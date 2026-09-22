import Foundation

/// Le regole da preparatore che una scheda deve rispettare **dopo** che il
/// modello ha scelto gli esercizi, e il motore che le impone senza fare una
/// seconda chiamata.
///
/// ## Perché esiste
/// La prova reale del 18/09/2026 ha prodotto tre schede che il validatore
/// dichiarava "valide" e che un preparatore non firmerebbe mai: quattro
/// esercizi al giorno dove ne servivano sei, due giorni di parte alta identici
/// per quattro esercizi su sette, l'addome mai allenato in una full body, il
/// petto a un terzo del volume del dorso. Non sono difetti da "riprova": sono
/// difetti da **sistemare**, perché il telefono sa benissimo qual è l'esercizio
/// giusto da mettere al posto di quello mancante.
///
/// Qui dentro non si chiede niente a nessuno: si prende l'elenco di id del
/// modello e lo si porta a essere una scheda sensata, dichiarando ogni
/// intervento in italiano. Lo stesso motore gira anche sulla scheda di riserva,
/// così le due strade arrivano alle stesse regole.
public enum GeneratorRepair {

    // MARK: - Le regole, in numeri

    /// Quanti esercizi possono ripetersi fra due giorni dello stesso tipo.
    ///
    /// Uno o due fondamentali che tornano sono programmazione; quattro su sette
    /// sono un copia e incolla.
    public static let maxSharedBetweenSimilarDays = 2
    /// Quante volte a settimana può comparire lo stesso esercizio.
    public static let maxWeeklyRepeats = 2
    /// Quanti esercizi "con cautela" (zona protetta sfiorata) per seduta.
    public static let maxCautionPerDay = 1
    /// Sotto questo numero di esercizi a settimana non si pretende l'addome
    /// diretto: con dieci esercizi in tutto ci sono cose più importanti.
    public static let directAbsThreshold = 15

    /// I blocchi con cui si guarda l'equilibrio di una scheda.
    ///
    /// Femorali e glutei stanno insieme perché nessuna scheda seria li divide:
    /// stacco rumeno e hip thrust lavorano su entrambi.
    public enum BigGroup: String, Sendable, Hashable, CaseIterable {
        case chest, back, shoulders, quads, posterior

        public var displayName: String {
            switch self {
            case .chest: "Petto"
            case .back: "Dorso"
            case .shoulders: "Spalle"
            case .quads: "Quadricipiti"
            case .posterior: "Femorali e glutei"
            }
        }

        public static func of(_ group: MuscleGroup) -> BigGroup? {
            switch group {
            case .chest: .chest
            case .back: .back
            case .shoulders: .shoulders
            case .quads: .quads
            case .hamstrings, .glutes: .posterior
            default: nil
            }
        }
    }

    /// Gruppi che vogliono almeno un esercizio **diretto** a settimana.
    ///
    /// L'addome entra solo quando la scheda ha abbastanza esercizi da
    /// permetterselo: pretenderlo in una scheda da due giorni da 45 minuti
    /// significherebbe togliere una spinta o una tirata.
    public static func requiredDirectGroups(parameters: GeneratorPlanParameters) -> [MuscleGroup] {
        var groups: [MuscleGroup] = [.chest, .back, .shoulders, .quads]
        if parameters.weeklyExerciseBudget >= directAbsThreshold { groups.append(.abs) }
        return groups
    }

    /// Schemi che allenano la catena posteriore anche senza colpirla "diretta":
    /// squat, affondi e stacchi lasciano i glutei ben allenati.
    public static let posteriorPatterns: Set<MovementPattern> = [.squat, .lunge, .hinge, .backExtension]

    /// Schemi di spinta e di tirata, per la regola "in ogni giorno di parte alta
    /// ci vuole una spinta e una tirata".
    public static let pushPatterns: Set<MovementPattern> = [.horizontalPush, .verticalPush]
    public static let pullPatterns: Set<MovementPattern> = [.horizontalPull, .verticalPull]

    /// Schemi che chiudono la seduta: addome e polpacci dopo gli isolamenti,
    /// il cardio per ultimo.
    public static let tailPatterns: Set<MovementPattern> = [
        .coreAntiExtension, .coreFlexion, .coreRotation, .calf,
    ]

    /// Posto dell'esercizio nella seduta: 0 multiarticolari, 1 isolamenti,
    /// 2 addome e polpacci, 3 cardio.
    public static func orderRank(_ candidate: GeneratorCandidate) -> Int {
        if candidate.pattern == .cardio { return 3 }
        if tailPatterns.contains(candidate.pattern) { return 2 }
        return candidate.kind == .compound ? 0 : 1
    }

    /// Un blocco grande con il suo volume, per i rilievi di equilibrio.
    public struct Load: Sendable, Hashable {
        public let group: BigGroup
        public let sets: Int
    }

    /// Lo squilibrio di una scheda, se c'è.
    ///
    /// Il metro è il volume **previsto**, cioè la media fra i blocchi che la
    /// struttura dei giorni prevede davvero: una scheda è sbilanciata quando un
    /// blocco sta sotto la metà della media *mentre* un altro la supera di più
    /// della metà. Il confronto diretto fra il minimo e il massimo sarebbe più
    /// severo ma segnalerebbe anche le schede sane: in una sopra/sotto le gambe
    /// prendono legittimamente più volume del petto, perché due giorni su
    /// quattro sono solo per loro.
    public static func imbalance(
        _ sets: [BigGroup: Int],
        among planned: [BigGroup]
    ) -> (low: Load, high: Load)? {
        guard planned.count >= 2 else { return nil }
        let values = planned.map { Load(group: $0, sets: sets[$0] ?? 0) }
        let expected = Double(values.reduce(0) { $0 + $1.sets }) / Double(values.count)
        guard expected > 0 else { return nil }
        guard let low = values.min(by: { $0.sets == $1.sets ? $0.group.rawValue < $1.group.rawValue : $0.sets < $1.sets }),
              let high = values.max(by: { $0.sets == $1.sets ? $0.group.rawValue > $1.group.rawValue : $0.sets < $1.sets }),
              low.group != high.group,
              Double(low.sets) < 0.5 * expected,
              Double(high.sets) > 1.5 * expected
        else { return nil }
        return (low, high)
    }

    // MARK: - Il motore

    /// Porta gli id scelti a rispettare tutte le regole.
    ///
    /// - Parameters:
    ///   - dayIDs: gli id per giorno, già ripuliti da quelli sconosciuti.
    ///   - labels: come chiamare i giorni nei messaggi di riparazione.
    /// - Returns: gli id sistemati e l'elenco in italiano di cosa è cambiato.
    public static func enforce(
        dayIDs: [[String]],
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates,
        labels: [String]
    ) -> (days: [[String]], repairs: [String]) {
        var engine = Engine(
            days: dayIDs,
            answers: answers,
            parameters: parameters,
            candidates: candidates,
            labels: labels
        )
        engine.run()
        return (engine.days, engine.repairs)
    }

    // MARK: - Stato del lavoro

    /// Lo stato del rimaneggiamento: i giorni, chi è già stato usato e dove.
    ///
    /// È una `struct` con metodi `mutating` e non una classe perché non deve
    /// sopravvivere alla chiamata: entra un elenco di id, esce un elenco di id.
    struct Engine {

        var days: [[String]]
        let answers: GeneratorAnswers
        let parameters: GeneratorPlanParameters
        let candidates: GeneratorCandidates
        let labels: [String]
        var repairs: [String] = []

        init(
            days: [[String]],
            answers: GeneratorAnswers,
            parameters: GeneratorPlanParameters,
            candidates: GeneratorCandidates,
            labels: [String]
        ) {
            self.days = days
            self.answers = answers
            self.parameters = parameters
            self.candidates = candidates
            self.labels = labels
        }

        // MARK: Comodità

        func label(_ index: Int) -> String {
            labels.indices.contains(index) ? labels[index] : "Giorno \(index + 1)"
        }

        func candidate(_ id: String) -> GeneratorCandidate? { candidates.candidate(id: id) }

        func blueprint(_ index: Int) -> GeneratorDayBlueprint? {
            parameters.days.indices.contains(index) ? parameters.days[index] : nil
        }

        /// Quanti esercizi deve avere quel giorno.
        var target: Int { parameters.targetExercisesPerDay }

        /// Quante volte l'esercizio compare in tutta la settimana.
        func weeklyUses(_ id: String) -> Int {
            days.reduce(0) { $0 + $1.filter { $0 == id }.count }
        }

        /// Quanti esercizi ha in comune il giorno `index` con il giorno `other`.
        func shared(_ index: Int, _ other: Int) -> Int {
            Set(days[index]).intersection(days[other]).count
        }

        /// Due giorni sono "dello stesso tipo" quando i loro schemi obbligatori
        /// si somigliano: parte alta A e parte alta B, spinta A e spinta B.
        func areSimilar(_ a: Int, _ b: Int) -> Bool {
            guard let first = blueprint(a), let second = blueprint(b) else { return true }
            let one = Set(first.requiredPatterns)
            let two = Set(second.requiredPatterns)
            guard !one.isEmpty, !two.isEmpty else { return true }
            let overlap = Double(one.intersection(two).count)
            return overlap / Double(min(one.count, two.count)) >= 0.5
        }

        /// Titoli brevi già usati in quel giorno: due "Seated Row" diversi nello
        /// stesso giorno sembrano un errore di copia.
        func names(in index: Int) -> Set<String> {
            Set(days[index].compactMap { candidate($0)?.shortName })
        }

        func cautionCount(in index: Int) -> Int {
            days[index].compactMap(candidate).filter(candidates.needsCare).count
        }

        /// Esercizi diretti per gruppo in tutta la settimana.
        func directCounts() -> [MuscleGroup: Int] {
            var counts: [MuscleGroup: Int] = [:]
            for day in days {
                for id in day {
                    guard let item = candidate(id) else { continue }
                    counts[item.group, default: 0] += 1
                }
            }
            return counts
        }

        /// Serie dirette per blocco grande: il volume, che è la misura con cui
        /// si giudica una scheda, non il numero di esercizi.
        func bigGroupSets() -> [BigGroup: Int] {
            var counts: [BigGroup: Int] = [:]
            for day in days {
                for id in day {
                    guard let item = candidate(id), let big = BigGroup.of(item.group) else { continue }
                    counts[big, default: 0] += parameters.sets(for: item.kind)
                }
            }
            return counts
        }

        // MARK: Ammissibilità

        /// `true` se quell'esercizio può entrare in quel giorno.
        func canAdd(_ item: GeneratorCandidate, to index: Int) -> Bool {
            guard !days[index].contains(item.id) else { return false }
            guard !names(in: index).contains(item.shortName) else { return false }
            guard weeklyUses(item.id) < GeneratorRepair.maxWeeklyRepeats else { return false }
            if candidates.needsCare(item), cautionCount(in: index) >= GeneratorRepair.maxCautionPerDay {
                return false
            }
            // Non si aggiunge un esercizio già presente in un giorno simile che
            // è già al tetto dei doppioni.
            for other in days.indices where other != index && days[other].contains(item.id) {
                guard areSimilar(index, other) else { continue }
                if shared(index, other) >= GeneratorRepair.maxSharedBetweenSimilarDays { return false }
            }
            return true
        }

        /// Il miglior candidato fra quelli che soddisfano `accept`.
        ///
        /// A parità di tutto si preferisce uno schema motorio che il giorno non
        /// ha ancora: due piegamenti di fila non fanno una seduta più completa
        /// di un piegamento e una tirata.
        func bestCandidate(
            for index: Int,
            where accept: (GeneratorCandidate) -> Bool
        ) -> GeneratorCandidate? {
            let present = Set(days[index].compactMap { candidate($0)?.pattern })
            return candidates.items
                .filter { $0.pattern != .cardio }
                .filter(accept)
                .filter { canAdd($0, to: index) }
                .min { lhs, rhs in
                    let l = present.contains(lhs.pattern)
                    let r = present.contains(rhs.pattern)
                    if l != r { return !l }
                    return candidates.isBetter(lhs, rhs)
                }
        }

        // MARK: Ordine di scarto

        /// Quanto è "sacrificabile" una voce del giorno: si toglie prima
        /// l'isolamento accessorio di un gruppo già ben servito, mai il
        /// fondamentale che regge la seduta.
        func expendability(_ id: String, in index: Int) -> (Int, Int, Int, String) {
            guard let item = candidate(id) else { return (9, 9, 9, id) }
            let required = Set(blueprint(index)?.requiredPatterns ?? [])
            let counts = directCounts()
            let isRequired = required.contains(item.pattern) ? 0 : 1
            let isCompound = item.kind == .compound ? 0 : 1
            // Più esemplari ha già quel gruppo, più la voce è sacrificabile.
            let abundance = -(counts[item.group] ?? 0)
            return (isRequired, isCompound, abundance * -1 + item.priority, id)
        }

        /// Indice della voce più sacrificabile del giorno, escludendo il cardio
        /// (che ha un posto suo) e le voci indicate.
        func mostExpendable(in index: Int, keeping protected: Set<String> = []) -> Int? {
            days[index].indices
                .filter { candidate(days[index][$0])?.pattern != .cardio }
                .filter { !protected.contains(days[index][$0]) }
                .max { lhs, rhs in
                    expendability(days[index][lhs], in: index) < expendability(days[index][rhs], in: index)
                }
        }

        // MARK: La sequenza

        mutating func run() {
            limitCaution()
            breakTwins()
            ensureCardio()
            trimLongDays()
            fillShortDays()
            coverMissingGroups()
            ensurePushAndPull()
            rebalance()
            // Le sostituzioni possono aver rimesso in circolo un esercizio
            // delicato: si ripassa, e se il giorno resta corto si ricompleta.
            limitCaution()
            fillShortDays()
            sortDays()
        }

        // MARK: 1. Un solo esercizio "con cautela" per seduta

        mutating func limitCaution() {
            guard !answers.protectedZones.isEmpty else { return }
            for index in days.indices {
                var kept = 0
                var removed: [String] = []
                var result: [String] = []
                for id in days[index] {
                    guard let item = candidate(id), candidates.needsCare(item) else {
                        result.append(id)
                        continue
                    }
                    if kept < GeneratorRepair.maxCautionPerDay {
                        kept += 1
                        result.append(id)
                    } else {
                        removed.append(item.shortName)
                    }
                }
                days[index] = result
                if !removed.isEmpty {
                    repairs.append(
                        "\(label(index)): tolti \(removed.joined(separator: ", ")), "
                        + "in una seduta ci sta un solo esercizio delicato per le zone da proteggere."
                    )
                }
            }
        }

        // MARK: 2. Giorni gemelli

        /// Toglie i doppioni di troppo fra giorni dello stesso tipo.
        ///
        /// Un fondamentale (multiarticolare di priorità 1) può tornare: è quello
        /// su cui si misura il progresso. Tutto il resto, se ripetuto, viene
        /// sostituito da una variante dello stesso schema.
        mutating func breakTwins() {
            for index in days.indices.dropFirst() {
                let original = days[index]

                // Prima si decide **chi ha diritto** di ripetersi, e il diritto
                // se lo prendono i fondamentali: un multiarticolare di priorità
                // 1 è l'esercizio su cui si misura il progresso, e sarebbe
                // assurdo toglierlo per tenere un'alzata laterale ripetuta solo
                // perché veniva prima nell'elenco.
                var keep: Set<String> = []
                var sharedWith: [Int: Int] = [:]
                let byImportance = original.enumerated().sorted { lhs, rhs in
                    func staple(_ id: String) -> Bool {
                        guard let item = candidate(id) else { return false }
                        return item.kind == .compound && item.priority == 1
                    }
                    let l = staple(lhs.element)
                    let r = staple(rhs.element)
                    return l == r ? lhs.offset < rhs.offset : l && !r
                }
                for (_, id) in byImportance {
                    guard candidate(id) != nil else { continue }
                    let similar = (0..<index).filter { days[$0].contains(id) && areSimilar(index, $0) }
                    guard !similar.isEmpty else {
                        keep.insert(id)
                        continue
                    }
                    let worst = similar.map { sharedWith[$0] ?? 0 }.max() ?? 0
                    let isStaple = candidate(id)?.kind == .compound && candidate(id)?.priority == 1
                    guard isStaple, worst < GeneratorRepair.maxSharedBetweenSimilarDays else { continue }
                    keep.insert(id)
                    for other in similar { sharedWith[other, default: 0] += 1 }
                }

                // Poi si ricostruisce il giorno nell'ordine originale,
                // sostituendo i ripetuti che non hanno passato il vaglio.
                var result: [String] = []
                for id in original {
                    guard let item = candidate(id) else { continue }
                    if keep.contains(id) {
                        result.append(id)
                        continue
                    }
                    // Si cerca una variante dello stesso schema e dello stesso
                    // tipo: sostituire uno squat con un wall sit "risolve" il
                    // doppione ma toglie al giorno il suo multiarticolare.
                    days[index] = result
                    // Il sostituto non può essere un esercizio che compare più
                    // avanti nello stesso giorno: sarebbe un doppione.
                    let taken = Set(original)
                    func pick(_ accept: @escaping (GeneratorCandidate) -> Bool) -> GeneratorCandidate? {
                        bestCandidate(for: index) { !taken.contains($0.id) && accept($0) }
                    }
                    let replacement = pick { $0.pattern == item.pattern && $0.kind == item.kind }
                        ?? pick { $0.group == item.group && $0.kind == item.kind }
                        ?? pick { $0.pattern == item.pattern }
                        ?? pick { $0.group == item.group }
                    if let replacement {
                        result.append(replacement.id)
                        repairs.append(
                            "\(label(index)): \(item.shortName) tornava da un giorno uguale, "
                            + "al suo posto \(replacement.shortName)."
                        )
                    } else {
                        repairs.append("\(label(index)): tolto \(item.shortName), ripetuto da un giorno uguale.")
                    }
                }
                days[index] = result
            }
        }

        // MARK: 2 bis. Il cardio richiesto

        /// Se l'utente ha chiesto il cardio, ogni seduta ne ha uno: è l'unica
        /// richiesta esplicita che il modello dimentica più spesso.
        mutating func ensureCardio() {
            guard answers.includeCardio else { return }
            let pool = candidates.items(pattern: .cardio)
            guard !pool.isEmpty else { return }
            for index in days.indices {
                guard !days[index].contains(where: { candidate($0)?.pattern == .cardio }) else { continue }
                let pick = pool.first { canAdd($0, to: index) } ?? pool.first { !days[index].contains($0.id) }
                guard let pick else { continue }
                if days[index].count >= target, let position = mostExpendable(in: index) {
                    days[index].remove(at: position)
                }
                days[index].append(pick.id)
                repairs.append("\(label(index)): aggiunto \(pick.shortName), era stato chiesto del cardio a fine seduta.")
            }
        }

        // MARK: 3. Sedute troppo lunghe

        mutating func trimLongDays() {
            for index in days.indices {
                while days[index].count > target {
                    guard let position = mostExpendable(in: index) else { break }
                    let removed = days[index].remove(at: position)
                    let name = candidate(removed)?.shortName ?? removed
                    repairs.append("\(label(index)): tolto \(name), la seduta era più lunga del tempo a disposizione.")
                }
            }
        }

        // MARK: 4. Sedute troppo corte

        /// Completa il giorno: prima gli schemi obbligatori scoperti, poi i
        /// gruppi senza lavoro diretto in settimana, poi gli isolamenti utili.
        mutating func fillShortDays() {
            for index in days.indices {
                guard days[index].count < target else { continue }
                let before = days[index].count
                var added: [String] = []

                // a. Schemi obbligatori del giorno non ancora coperti.
                if let plan = blueprint(index) {
                    for pattern in plan.requiredPatterns where days[index].count < target {
                        let covered = days[index].contains { candidate($0)?.pattern == pattern }
                        guard !covered else { continue }
                        guard let pick = bestCandidate(for: index, where: { $0.pattern == pattern }) else { continue }
                        days[index].append(pick.id)
                        added.append(pick.shortName)
                    }
                }

                // b. Gruppi che in settimana non hanno ancora niente di diretto.
                while days[index].count < target {
                    let counts = directCounts()
                    let missing = GeneratorRepair.requiredDirectGroups(parameters: parameters)
                        .filter { (counts[$0] ?? 0) == 0 }
                        // Solo i gruppi che il giorno prevede: l'addome sta bene
                        // ovunque, una spinta di petto in un giorno di gambe no.
                        .filter { group in
                            guard let big = BigGroup.of(group) else { return true }
                            return plans(index, big)
                        }
                    guard let group = missing.first,
                          let pick = bestCandidate(for: index, where: { $0.group == group })
                    else { break }
                    days[index].append(pick.id)
                    added.append(pick.shortName)
                }

                // c. Gli schemi facoltativi previsti dal giorno.
                if let plan = blueprint(index) {
                    for pattern in plan.patternSequence(count: target) where days[index].count < target {
                        guard let pick = bestCandidate(for: index, where: { $0.pattern == pattern }) else { continue }
                        days[index].append(pick.id)
                        added.append(pick.shortName)
                    }
                }

                // d. Quel che resta: il miglior candidato di un gruppo già
                //    toccato dal giorno, così la seduta resta coerente.
                while days[index].count < target {
                    let groupsToday = Set(days[index].compactMap { candidate($0)?.group })
                    let pick = bestCandidate(for: index, where: { groupsToday.contains($0.group) })
                        ?? bestCandidate(for: index, where: { _ in true })
                    guard let pick else { break }
                    days[index].append(pick.id)
                    added.append(pick.shortName)
                }

                if !added.isEmpty {
                    repairs.append(
                        "\(label(index)): la seduta aveva \(before) esercizi invece di \(target), "
                        + "aggiunti \(added.joined(separator: ", "))."
                    )
                }
            }
        }

        // MARK: 5. Copertura settimanale

        /// Ogni gruppo principale vuole almeno un esercizio diretto; la catena
        /// posteriore si accontenta anche del lavoro indiretto di squat,
        /// affondi e stacchi.
        mutating func coverMissingGroups() {
            for group in GeneratorRepair.requiredDirectGroups(parameters: parameters) {
                guard (directCounts()[group] ?? 0) == 0 else { continue }
                guard let (index, pick) = placeForGroup(group) else { continue }
                swapIn(pick, day: index, because: "\(group.displayName) non era allenato in tutta la settimana")
            }

            let posteriorCovered = days.contains { day in
                day.contains { id in
                    guard let item = candidate(id) else { return false }
                    return item.group == .hamstrings || item.group == .glutes
                        || GeneratorRepair.posteriorPatterns.contains(item.pattern)
                }
            }
            if !posteriorCovered, let (index, pick) = placeForGroup(.hamstrings) ?? placeForGroup(.glutes) {
                swapIn(pick, day: index, because: "femorali e glutei non erano allenati in tutta la settimana")
            }
        }

        /// Dove mettere un esercizio per quel gruppo, e quale.
        ///
        /// Si preferisce il giorno che quel gruppo lo prevede già nella sua
        /// ossatura: l'addome nel giorno che ha il core fra gli schemi, il
        /// petto in un giorno di spinta.
        func placeForGroup(_ group: MuscleGroup) -> (Int, GeneratorCandidate)? {
            let ordered = days.indices.sorted { lhs, rhs in
                let l = blueprint(lhs)?.allPatterns.contains { $0.primaryGroup == group } == true ? 0 : 1
                let r = blueprint(rhs)?.allPatterns.contains { $0.primaryGroup == group } == true ? 0 : 1
                return l == r ? lhs < rhs : l < r
            }
            for index in ordered {
                if let pick = bestCandidate(for: index, where: { $0.group == group }) {
                    return (index, pick)
                }
            }
            return nil
        }

        /// Mette `pick` nel giorno al posto della voce più sacrificabile.
        mutating func swapIn(_ pick: GeneratorCandidate, day index: Int, because reason: String) {
            guard canAdd(pick, to: index) else { return }
            if days[index].count < target {
                days[index].append(pick.id)
                repairs.append("\(label(index)): aggiunto \(pick.shortName), \(reason).")
                return
            }
            guard let position = mostExpendable(in: index) else { return }
            let removed = days[index][position]
            let name = candidate(removed)?.shortName ?? removed
            days[index][position] = pick.id
            repairs.append("\(label(index)): \(name) sostituito con \(pick.shortName), \(reason).")
        }

        // MARK: 6. Una spinta e una tirata dove servono

        mutating func ensurePushAndPull() {
            for index in days.indices {
                guard let plan = blueprint(index) else { continue }
                let required = Set(plan.requiredPatterns)
                guard !required.isDisjoint(with: GeneratorRepair.pushPatterns),
                      !required.isDisjoint(with: GeneratorRepair.pullPatterns)
                else { continue }
                let present = Set(days[index].compactMap { candidate($0)?.pattern })
                if present.isDisjoint(with: GeneratorRepair.pushPatterns),
                   let pick = bestCandidate(for: index, where: { GeneratorRepair.pushPatterns.contains($0.pattern) }) {
                    swapIn(pick, day: index, because: "la seduta era senza nessuna spinta")
                }
                let after = Set(days[index].compactMap { candidate($0)?.pattern })
                if after.isDisjoint(with: GeneratorRepair.pullPatterns),
                   let pick = bestCandidate(for: index, where: { GeneratorRepair.pullPatterns.contains($0.pattern) }) {
                    swapIn(pick, day: index, because: "la seduta era senza nessuna tirata")
                }
            }
        }

        // MARK: 7. Equilibrio fra i gruppi grandi

        /// Riequilibra finché un blocco grande resta sotto la metà del più
        /// allenato: si sostituisce nello stesso giorno, non si allungano le sedute.
        mutating func rebalance() {
            for _ in 0..<4 {
                let present = BigGroup.allCases.filter { plannedBigGroups().contains($0) }
                guard let (low, high) = GeneratorRepair.imbalance(bigGroupSets(), among: present) else { return }
                guard let move = rebalanceMove(from: high.group, to: low.group) else { return }
                let removed = days[move.day][move.position]
                let name = candidate(removed)?.shortName ?? removed
                days[move.day][move.position] = move.pick.id
                repairs.append(
                    "\(label(move.day)): \(name) sostituito con \(move.pick.shortName), "
                    + "\(low.group.displayName) era sotto la metà del volume previsto "
                    + "mentre \(high.group.displayName) lo superava di oltre la metà."
                )
            }
        }

        /// I blocchi grandi che la struttura dei giorni prevede davvero: in una
        /// scheda di sola parte alta non ha senso pretendere le gambe.
        func plannedBigGroups() -> Set<BigGroup> {
            var result: Set<BigGroup> = []
            for plan in parameters.days {
                for pattern in plan.allPatterns {
                    guard let group = pattern.primaryGroup, let big = BigGroup.of(group) else { continue }
                    result.insert(big)
                }
                if plan.allPatterns.contains(where: { $0 == .hinge || $0 == .legIsolation }) {
                    result.insert(.posterior)
                }
            }
            return result
        }

        /// `true` se l'ossatura di quel giorno prevede quel blocco grande.
        func plans(_ index: Int, _ big: BigGroup) -> Bool {
            guard let plan = blueprint(index) else { return true }
            return plan.allPatterns.contains { pattern in
                pattern.primaryGroup.flatMap(BigGroup.of) == big
                    || (big == .posterior && (pattern == .hinge || pattern == .legIsolation))
            }
        }

        struct Move {
            let day: Int
            let position: Int
            let pick: GeneratorCandidate
        }

        /// Trova un giorno dove togliere un esercizio del blocco troppo servito
        /// e metterne uno del blocco trascurato.
        func rebalanceMove(from high: BigGroup, to low: BigGroup) -> Move? {
            for index in days.indices {
                // Solo nei giorni che quel blocco lo prevedono davvero: mettere
                // una spinta di petto dentro un giorno di gambe risolve un
                // numero e rovina la scheda.
                guard plans(index, low), plans(index, high) else { continue }
                guard let pick = bestCandidate(for: index, where: { BigGroup.of($0.group) == low }) else { continue }
                let positions = days[index].indices.filter { position in
                    guard let item = candidate(days[index][position]) else { return false }
                    return BigGroup.of(item.group) == high
                }
                // Si toglie il meno importante fra quelli del blocco in eccesso.
                guard let position = positions.max(by: { lhs, rhs in
                    expendability(days[index][lhs], in: index) < expendability(days[index][rhs], in: index)
                }) else { continue }
                // Mai togliere l'unico rappresentante di quel blocco nel giorno
                // se il giorno è fatto apposta per quel blocco.
                if positions.count == 1, blueprint(index)?.requiredPatterns.contains(where: {
                    $0.primaryGroup.flatMap(BigGroup.of) == high
                }) == true {
                    continue
                }
                return Move(day: index, position: position, pick: pick)
            }
            return nil
        }

        // MARK: 8. Ordine della seduta

        /// Multiarticolari pesanti, poi isolamenti, poi addome e polpacci,
        /// infine il cardio. A parità di posto l'ordine del modello resta.
        mutating func sortDays() {
            for index in days.indices {
                let sorted = days[index].enumerated().sorted { lhs, rhs in
                    let l = candidate(lhs.element).map(GeneratorRepair.orderRank) ?? 1
                    let r = candidate(rhs.element).map(GeneratorRepair.orderRank) ?? 1
                    return l == r ? lhs.offset < rhs.offset : l < r
                }.map(\.element)
                if sorted != days[index] {
                    repairs.append("\(label(index)): rimessa in ordine la seduta, i fondamentali per primi.")
                    days[index] = sorted
                }
                // Un esercizio delicato non può aprire la seduta: si scambia con
                // il successivo dello stesso posto in classifica.
                guard !answers.protectedZones.isEmpty, let first = days[index].first,
                      let item = candidate(first), candidates.needsCare(item)
                else { continue }
                let rank = GeneratorRepair.orderRank(item)
                if let swap = days[index].indices.dropFirst().first(where: { position in
                    guard let other = candidate(days[index][position]) else { return false }
                    return !candidates.needsCare(other) && GeneratorRepair.orderRank(other) == rank
                }) {
                    days[index].swapAt(0, swap)
                    repairs.append("\(label(index)): \(item.shortName) spostato più avanti, non apre la seduta.")
                    continue
                }
                // Nessuno con cui scambiarlo: si cerca una variante pulita dello
                // stesso schema. Se non c'è nemmeno quella (capita a corpo
                // libero con le ginocchia da proteggere) si tiene: meglio un
                // esercizio da fare con attenzione che un giorno monco.
                days[index].removeFirst()
                let replacement = bestCandidate(for: index) {
                    $0.pattern == item.pattern && !candidates.needsCare($0)
                }
                if let replacement {
                    days[index].insert(replacement.id, at: 0)
                    repairs.append(
                        "\(label(index)): \(item.shortName) apriva la seduta ed è delicato, "
                        + "al suo posto \(replacement.shortName)."
                    )
                } else {
                    days[index].insert(item.id, at: 0)
                }
            }
        }
    }
}
