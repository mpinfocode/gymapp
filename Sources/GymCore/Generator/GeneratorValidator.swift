import Foundation

/// Esito della verifica di una scheda generata.
public struct GeneratorValidation: Sendable, Hashable {

    /// Errori bloccanti, in italiano, già leggibili da un umano.
    public let errors: [String]
    /// Rilievi non bloccanti (squilibri di volume, gruppi poco allenati).
    public let warnings: [String]

    public init(errors: [String], warnings: [String] = []) {
        self.errors = errors
        self.warnings = warnings
    }

    public var isValid: Bool { errors.isEmpty }
}

/// Verifica e ripara la scheda restituita dal modello.
///
/// La regola è semplice: **non si mostra all'utente niente che non sia passato
/// di qui**. Un modello economico sbaglia volentieri un id, ripete un esercizio
/// o mette il curl prima dello squat; i difetti piccoli si correggono da soli,
/// quelli grossi fanno scartare la risposta e si usa la scheda di riserva.
public enum GeneratorValidator {

    /// Serie ammesse per esercizio.
    public static let setsRange: ClosedRange<Int> = 1...6
    /// Ripetizioni ammesse.
    public static let repsRange: ClosedRange<Int> = 1...30
    /// Recupero ammesso, in secondi.
    public static let restRange: ClosedRange<Int> = 15...300
    /// Durata ammessa per gli esercizi a tempo, in secondi.
    public static let secondsRange: ClosedRange<Int> = 10...1800
    /// Lunghezza massima della nota.
    public static let maxNoteLength = 80
    /// Lunghezza massima del nome della scheda.
    public static let maxNameLength = 60

    /// Trattini vietati nelle stringhe visibili (DESIGN.md).
    static let forbiddenDashes: [Character] = ["—", "–"]

    /// Gruppi che una scheda seria allena almeno una volta a settimana.
    ///
    /// Bicipiti e tricipiti non ci sono di proposito: con tre tirate e tre
    /// spinte a settimana le braccia lavorano comunque, e pretenderli
    /// esplicitamente farebbe scartare schede corrette da 45 minuti.
    /// L'addome si aggiunge quando la scheda ha abbastanza esercizi
    /// (``GeneratorRepair/requiredDirectGroups(parameters:)``).
    public static let requiredWeeklyGroups: [MuscleGroup] = [.chest, .back, .shoulders, .quads]
    /// Almeno uno di questi (catena posteriore).
    public static let requiredPosteriorGroups: Set<MuscleGroup> = [.hamstrings, .glutes]

    // MARK: - Verifica

    public static func validate(
        _ draft: GeneratedProgramDraft,
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> GeneratorValidation {
        var errors: [String] = []
        var warnings: [String] = []

        // Nome
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { errors.append("La scheda non ha un nome.") }
        if name.count > maxNameLength { errors.append("Il nome della scheda supera \(maxNameLength) caratteri.") }
        if name.contains(where: forbiddenDashes.contains) { errors.append("Il nome della scheda contiene un trattino lungo.") }

        // Giorni
        let expectedDays = parameters.days.count
        if draft.days.count != expectedDays {
            errors.append("La scheda ha \(draft.days.count) giorni invece di \(expectedDays).")
        }

        // Il numero di esercizi è un vincolo, non un'indicazione: il tempo per
        // seduta è quello, e una scheda con due esercizi in meno del previsto
        // non allena (prova reale del 18/09/2026).
        let allowed = parameters.allowedExercisesPerDay
        let low = allowed.lowerBound
        let high = allowed.upperBound

        var groupsTrained: Set<MuscleGroup> = []
        var patternsTrained: Set<MovementPattern> = []

        for (position, day) in draft.days.enumerated() {
            let label = day.name.isEmpty ? "Giorno \(position + 1)" : day.name
            if day.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("\(label): manca il nome del giorno.")
            }
            if day.name.contains(where: forbiddenDashes.contains) {
                errors.append("\(label): il nome contiene un trattino lungo.")
            }
            if day.items.count < low || day.items.count > high {
                errors.append("\(label): \(day.items.count) esercizi, ne servono da \(low) a \(high).")
            }

            var seen: Set<String> = []
            var lastRank = -1
            var cautionInDay = 0

            for (itemPosition, item) in day.items.enumerated() {
                guard let candidate = candidates.candidate(id: item.id) else {
                    errors.append("\(label): l'esercizio \(item.id) non è fra i candidati proposti.")
                    continue
                }
                if !seen.insert(item.id).inserted {
                    errors.append("\(label): \(candidate.shortName) compare due volte.")
                }
                groupsTrained.insert(candidate.group)
                patternsTrained.insert(candidate.pattern)

                if !setsRange.contains(item.sets) {
                    errors.append("\(label), \(candidate.shortName): \(item.sets) serie, ammesse da \(setsRange.lowerBound) a \(setsRange.upperBound).")
                }
                if let seconds = item.seconds, item.repsMin == nil {
                    if !secondsRange.contains(seconds) {
                        errors.append("\(label), \(candidate.shortName): durata di \(seconds) s fuori dai limiti.")
                    }
                } else if let minimum = item.repsMin, let maximum = item.repsMax {
                    if !repsRange.contains(minimum) || !repsRange.contains(maximum) {
                        errors.append("\(label), \(candidate.shortName): ripetizioni fuori da \(repsRange.lowerBound)-\(repsRange.upperBound).")
                    }
                    if minimum > maximum {
                        errors.append("\(label), \(candidate.shortName): ripetizioni minime maggiori delle massime.")
                    }
                } else {
                    // Si segnala e si va avanti: prima questo caso usciva dal
                    // ciclo con un `continue`, e così una voce senza numeri
                    // saltava anche i controlli sulle zone protette e
                    // sull'ordine, che con lei non c'entrano niente.
                    errors.append("\(label), \(candidate.shortName): mancano le ripetizioni.")
                }
                if !restRange.contains(item.rest) {
                    errors.append("\(label), \(candidate.shortName): recupero di \(item.rest) s fuori da \(restRange.lowerBound)-\(restRange.upperBound).")
                }
                if let note = item.note, !note.isEmpty {
                    if note.count > maxNoteLength {
                        errors.append("\(label), \(candidate.shortName): la nota supera \(maxNoteLength) caratteri.")
                    }
                    if note.contains(where: forbiddenDashes.contains) {
                        errors.append("\(label), \(candidate.shortName): la nota contiene un trattino lungo.")
                    }
                }
                if !candidate.avoidZones.isDisjoint(with: answers.protectedZones) {
                    let zones = StressZone.displayOrder
                        .filter { candidate.avoidZones.contains($0) && answers.protectedZones.contains($0) }
                        .map(\.displayName)
                    errors.append("\(label), \(candidate.shortName): sollecita una zona da proteggere (\(zones.joined(separator: ", "))).")
                }
                if candidates.needsCare(candidate) {
                    cautionInDay += 1
                    if cautionInDay > GeneratorRepair.maxCautionPerDay {
                        errors.append("\(label), \(candidate.shortName): nella seduta c'è più di un esercizio delicato per le zone da proteggere.")
                    }
                    // Aprire la seduta con un esercizio delicato è un errore solo
                    // se c'era qualcosa di meglio da mettere davanti: a corpo
                    // libero con le ginocchia da proteggere può capitare che
                    // tutti i multiarticolari di gamba siano delicati.
                    let rank = GeneratorRepair.orderRank(candidate)
                    let hasCleanAlternative = day.items.dropFirst().contains { other in
                        guard let candidate = candidates.candidate(id: other.id) else { return false }
                        return !candidates.needsCare(candidate) && GeneratorRepair.orderRank(candidate) == rank
                    }
                    if itemPosition == 0, hasCleanAlternative {
                        errors.append("\(label): \(candidate.shortName) è delicato per le zone da proteggere e apre la seduta.")
                    }
                }

                // Ordine: multiarticolari, isolamenti, addome e polpacci, cardio.
                let rank = GeneratorRepair.orderRank(candidate)
                if rank < lastRank {
                    errors.append("\(label): \(candidate.shortName) è fuori posto nell'ordine della seduta.")
                }
                lastRank = max(lastRank, rank)
            }
        }

        // Giorni gemelli: due sedute dello stesso tipo non possono essere la
        // stessa seduta con un esercizio scambiato.
        for first in draft.days.indices {
            for second in draft.days.indices where second > first {
                guard areSimilar(first, second, parameters: parameters) else { continue }
                let shared = Set(draft.days[first].items.map(\.id))
                    .intersection(draft.days[second].items.map(\.id))
                guard shared.count > GeneratorRepair.maxSharedBetweenSimilarDays else { continue }
                let names = shared.compactMap { candidates.candidate(id: $0)?.shortName }.sorted()
                errors.append(
                    "\(draft.days[first].name) e \(draft.days[second].name) hanno \(shared.count) esercizi in comune "
                    + "(\(names.prefix(4).joined(separator: ", "))): sono lo stesso giorno due volte."
                )
            }
        }

        // Copertura settimanale: le schede da due giorni sono esentate, non
        // possono coprire tutto senza diventare maratone.
        if draft.days.count > 2 {
            for group in GeneratorRepair.requiredDirectGroups(parameters: parameters) {
                guard !groupsTrained.contains(group) else { continue }
                // Non si pretende quel che i candidati non possono dare.
                guard !candidates.items(group: group).isEmpty else { continue }
                errors.append("Nessun esercizio per \(group.displayName) in tutta la settimana.")
            }
            // Femorali e glutei: vale anche il lavoro indiretto di squat,
            // affondi e stacchi, che è come li allena davvero una scheda.
            let posterior = !groupsTrained.isDisjoint(with: requiredPosteriorGroups)
                || !patternsTrained.isDisjoint(with: GeneratorRepair.posteriorPatterns)
            if !posterior {
                errors.append("Nessun esercizio per femorali o glutei in tutta la settimana.")
            }
        }

        // Rilievi non bloccanti
        warnings += balanceWarnings(draft, parameters: parameters, candidates: candidates)
        for group in answers.focusGroups where !groupsTrained.contains(group) {
            warnings.append("\(group.displayName) è indicato come priorità ma non compare nella scheda.")
        }
        if answers.includeCardio {
            let hasCardio = draft.days.contains { day in
                day.items.contains { candidates.candidate(id: $0.id)?.pattern == .cardio }
            }
            if !hasCardio { warnings.append("Era stato chiesto del cardio, ma nella scheda non ce n'è.") }
        }

        return GeneratorValidation(errors: errors, warnings: warnings)
    }

    /// Due giorni sono "dello stesso tipo" quando i loro schemi obbligatori si
    /// somigliano per almeno metà.
    public static func areSimilar(_ first: Int, _ second: Int, parameters: GeneratorPlanParameters) -> Bool {
        guard parameters.days.indices.contains(first), parameters.days.indices.contains(second) else { return true }
        let one = Set(parameters.days[first].requiredPatterns)
        let two = Set(parameters.days[second].requiredPatterns)
        guard !one.isEmpty, !two.isEmpty else { return true }
        return Double(one.intersection(two).count) / Double(min(one.count, two.count)) >= 0.5
    }

    /// Squilibri fra i blocchi grandi: non bloccano la scheda, ma vanno detti.
    static func balanceWarnings(
        _ draft: GeneratedProgramDraft,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> [String] {
        var sets: [GeneratorRepair.BigGroup: Int] = [:]
        for day in draft.days {
            for item in day.items {
                guard let candidate = candidates.candidate(id: item.id),
                      let big = GeneratorRepair.BigGroup.of(candidate.group)
                else { continue }
                sets[big, default: 0] += item.sets
            }
        }
        let planned = GeneratorRepair.BigGroup.allCases.filter { big in
            parameters.days.contains { day in
                day.allPatterns.contains { pattern in
                    pattern.primaryGroup.flatMap(GeneratorRepair.BigGroup.of) == big
                        || (big == .posterior && (pattern == .hinge || pattern == .legIsolation))
                }
            }
        }
        guard let (low, high) = GeneratorRepair.imbalance(sets, among: planned) else { return [] }
        return [
            "\(low.group.displayName) ha \(low.sets) serie dirette contro \(high.sets) di \(high.group.displayName): "
            + "la scheda è sbilanciata."
        ]
    }

    // MARK: - Riparazione

    /// Sistema la scheda invece di scartarla, e dice cosa ha cambiato.
    ///
    /// Prima questa funzione faceva solo il minimo indispensabile: numeri nei
    /// limiti, via i doppioni e gli id inventati, multiarticolari davanti. Era
    /// una scelta prudente che però lasciava passare schede sbagliate, perché
    /// **quello che manca il telefono sa benissimo come metterlo**: ha i
    /// candidati, l'ossatura del giorno e le regole. Una seconda chiamata al
    /// modello costerebbe altri secondi di attesa per ottenere, nella migliore
    /// delle ipotesi, la stessa cosa.
    ///
    /// Adesso la sequenza è: si ripuliscono le voci illecite, si impongono le
    /// regole da preparatore (``GeneratorRepair``), si rimettono i numeri.
    /// Il nome della scheda e i nomi dei giorni li decide sempre il telefono: il
    /// campo `n` della risposta si legge e si ignora.
    public static func repair(
        _ draft: GeneratedProgramDraft,
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> (draft: GeneratedProgramDraft, repairs: [String]) {
        var repairs: [String] = []
        let expectedDays = parameters.days.count
        let labels = parameters.dayNames

        // 1. Numero di giorni: quello chiesto, né uno di più né uno di meno.
        var dayItems = draft.days.map(\.items)
        if dayItems.count > expectedDays {
            repairs.append("Tolti \(dayItems.count - expectedDays) giorni di troppo.")
            dayItems = Array(dayItems.prefix(expectedDays))
        }
        while dayItems.count < expectedDays {
            dayItems.append([])
            repairs.append("Aggiunto il giorno \(labels.indices.contains(dayItems.count - 1) ? labels[dayItems.count - 1] : "\(dayItems.count)"), mancava nella risposta.")
        }

        // 2. Pulizia delle voci: id inventati, doppioni, zone vietate.
        //
        // Un esercizio vietato da una zona da proteggere non si toglie e basta:
        // il modello lo aveva messo per un motivo (era la spinta verticale del
        // giorno), e toglierlo lascerebbe un buco che il completamento riempie
        // con la prima cosa utile invece che con una spinta verticale. Si
        // sostituisce sul posto con il miglior candidato dello stesso schema.
        var cleaned: [[GeneratedProgramDraft.Item]] = []
        var usedInProgram: Set<String> = []
        for (index, items) in dayItems.enumerated() {
            let label = labels.indices.contains(index) ? labels[index] : "Giorno \(index + 1)"
            var seen: Set<String> = []
            var kept: [GeneratedProgramDraft.Item] = []

            /// Il sostituto di un esercizio vietato: stesso schema motorio,
            /// non già in questo giorno, e possibilmente nuovo per la settimana.
            func replacement(for pattern: MovementPattern) -> GeneratorCandidate? {
                let pool = candidates.items(pattern: pattern).filter { !seen.contains($0.id) }
                return pool.first { !usedInProgram.contains($0.id) } ?? pool.first
            }

            for item in items {
                guard let candidate = candidates.candidate(id: item.id) else {
                    // Fuori dai candidati: o è un id inventato, o è un esercizio
                    // della selezione che una zona da proteggere vieta.
                    let curated = CuratedExercisePool.byID[item.id]
                    let forbidden = curated.map { !$0.avoid.isDisjoint(with: answers.protectedZones) } ?? false
                    guard forbidden, let pattern = curated?.pattern, let pick = replacement(for: pattern) else {
                        repairs.append(
                            forbidden
                                ? "\(label): tolto l'esercizio \(item.id), sollecita una zona da proteggere."
                                : "\(label): tolto l'esercizio \(item.id), non è fra i candidati."
                        )
                        continue
                    }
                    seen.insert(pick.id)
                    usedInProgram.insert(pick.id)
                    kept.append(numbers(for: pick, parameters: parameters))
                    repairs.append(
                        "\(label): l'esercizio \(item.id) sollecita una zona da proteggere, "
                        + "al suo posto \(pick.shortName) (\(pick.pattern.displayName))."
                    )
                    continue
                }
                guard seen.insert(item.id).inserted else {
                    repairs.append("\(label): tolto il doppione \(candidate.shortName).")
                    continue
                }
                usedInProgram.insert(item.id)
                kept.append(item)
            }
            cleaned.append(kept)
        }

        // 3. Le regole da preparatore.
        let enforced = GeneratorRepair.enforce(
            dayIDs: cleaned.map { $0.map(\.id) },
            answers: answers,
            parameters: parameters,
            candidates: candidates,
            labels: labels
        )
        repairs += enforced.repairs

        // 4. I numeri: quelli del modello se li aveva mandati, altrimenti
        //    quelli calcolati dal telefono.
        var days: [GeneratedProgramDraft.Day] = []
        for (index, ids) in enforced.days.enumerated() {
            let label = labels.indices.contains(index) ? labels[index] : "Giorno \(index + 1)"
            let original = Dictionary(cleaned[index].map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var items: [GeneratedProgramDraft.Item] = []
            for id in ids {
                guard let candidate = candidates.candidate(id: id) else { continue }
                var item = original[id] ?? numbers(for: candidate, parameters: parameters)
                if item.isUnspecified { item = numbers(for: candidate, parameters: parameters) }
                normalize(&item, candidate: candidate, label: label, parameters: parameters, repairs: &repairs)
                items.append(item)
            }
            days.append(GeneratedProgramDraft.Day(name: label, items: items))
        }

        return (GeneratedProgramDraft(name: defaultName(for: answers), days: days), repairs)
    }

    /// Riporta i numeri di una voce dentro i limiti, dichiarando le correzioni.
    ///
    /// Le voci del formato compatto arrivano qui già complete (i numeri li ha
    /// messi il telefono un attimo prima): non producono nessuna riga di
    /// riparazione, altrimenti l'utente ne leggerebbe quaranta tutte uguali.
    static func normalize(
        _ item: inout GeneratedProgramDraft.Item,
        candidate: GeneratorCandidate,
        label: String,
        parameters: GeneratorPlanParameters,
        repairs: inout [String]
    ) {
        if !setsRange.contains(item.sets) {
            item.sets = item.sets.clamped(to: setsRange)
            repairs.append("\(label), \(candidate.shortName): serie riportate a \(item.sets).")
        }
        if item.seconds != nil, item.repsMin == nil {
            let seconds = (item.seconds ?? 0).clamped(to: secondsRange)
            if seconds != item.seconds {
                repairs.append("\(label), \(candidate.shortName): durata riportata a \(seconds) s.")
            }
            item.seconds = seconds
        } else {
            let fallback = parameters.reps(for: candidate.kind)
            var minimum = (item.repsMin ?? fallback.lowerBound).clamped(to: repsRange)
            var maximum = (item.repsMax ?? fallback.upperBound).clamped(to: repsRange)
            if minimum > maximum {
                swap(&minimum, &maximum)
                repairs.append("\(label), \(candidate.shortName): ripetizioni minime e massime invertite.")
            }
            if minimum != item.repsMin || maximum != item.repsMax {
                if item.repsMin != nil || item.repsMax != nil {
                    repairs.append("\(label), \(candidate.shortName): ripetizioni riportate a \(minimum)-\(maximum).")
                } else {
                    repairs.append("\(label), \(candidate.shortName): aggiunte le ripetizioni mancanti.")
                }
            }
            item.repsMin = minimum
            item.repsMax = maximum
            item.seconds = nil
        }
        if !restRange.contains(item.rest) {
            item.rest = item.rest.clamped(to: restRange)
            repairs.append("\(label), \(candidate.shortName): recupero riportato a \(item.rest) s.")
        }
        if var note = item.note, !note.isEmpty {
            let original = note
            note = sanitizeDashes(note)
            if note.count > maxNoteLength {
                note = String(note.prefix(maxNoteLength)).trimmingCharacters(in: .whitespaces)
            }
            if note != original { repairs.append("\(label), \(candidate.shortName): nota sistemata.") }
            item.note = note
        }
    }

    /// I numeri di una voce di cui il modello ha mandato solo l'id.
    ///
    /// Sono gli stessi numeri che userebbe la scheda di riserva: serie,
    /// ripetizioni e recupero secondo obiettivo ed esperienza, durata al posto
    /// delle ripetizioni per plank e cardio. Così una scheda scelta dall'AI e
    /// una costruita dal telefono hanno la stessa programmazione, e l'unica
    /// differenza è la scelta degli esercizi.
    public static func numbers(
        for candidate: GeneratorCandidate,
        parameters: GeneratorPlanParameters
    ) -> GeneratedProgramDraft.Item {
        if candidate.pattern == .cardio {
            return GeneratedProgramDraft.Item(
                id: candidate.id,
                sets: 1,
                seconds: (parameters.cardioSeconds ?? 600).clamped(to: secondsRange),
                rest: 60
            )
        }
        return FallbackProgramGenerator.makeItem(for: candidate, parameters: parameters)
    }

    /// L'ordine della seduta: multiarticolari pesanti, poi isolamenti, poi
    /// addome e polpacci, infine il cardio. Dentro ciascun gruppo l'ordine
    /// originale non si tocca.
    static func stableCompoundFirst(
        _ items: [GeneratedProgramDraft.Item],
        candidates: GeneratorCandidates
    ) -> [GeneratedProgramDraft.Item] {
        func rank(_ item: GeneratedProgramDraft.Item) -> Int {
            guard let candidate = candidates.candidate(id: item.id) else { return 1 }
            return GeneratorRepair.orderRank(candidate)
        }
        return items.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element)
                let r = rank(rhs.element)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    static func sanitizeDashes(_ text: String) -> String {
        var result = text
        for dash in forbiddenDashes {
            result = result.replacingOccurrences(of: String(dash), with: "-")
        }
        return result
    }

    /// Il nome della scheda, deciso dal telefono.
    ///
    /// Non è un ripiego: è **il** nome. I modelli economici propongono titoli da
    /// volantino ("Massa Total Body", "Forma Fisica Generale") che non dicono
    /// niente in più della divisione e dei giorni, e ogni tanto ci infilano un
    /// trattino lungo che il design vieta. Il campo `n` della risposta si legge
    /// (fa parte del contratto con lo schema) e si ignora.
    public static func defaultName(for answers: GeneratorAnswers) -> String {
        "\(answers.split.displayName) · \(answers.daysPerWeek) giorni"
    }

    // MARK: - Conversione in Program

    /// Trasforma la scheda generata in un ``Program`` di GymCore.
    ///
    /// Non imposta nessun carico: lo mette l'utente alla prima seduta.
    /// La modalità è sempre ``ProgramMode/rotation`` (SPEC §0: i giorni sono un
    /// elenco, il generatore non assegna giorni della settimana).
    public static func program(
        from draft: GeneratedProgramDraft,
        answers: GeneratorAnswers,
        candidates: GeneratorCandidates,
        now: Date = Date()
    ) -> Program {
        let days = draft.days.enumerated().map { index, day in
            ProgramDay(
                name: day.name.isEmpty ? "Giorno \(index + 1)" : day.name,
                items: day.items.map { item in
                    PlanItem(
                        exerciseID: item.id,
                        targetSets: item.sets.clamped(to: setsRange),
                        measure: item.measure,
                        targetWeightKg: nil,
                        warmupSets: 0,
                        restSeconds: item.rest.clamped(to: restRange),
                        note: item.note ?? ""
                    )
                }
            )
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Program(
            name: name.isEmpty ? defaultName(for: answers) : name,
            notes: "",
            startDate: now,
            plannedWeeks: answers.weeks,
            mode: .rotation,
            days: days,
            // Seme del gradiente: deterministico, non casuale, così due schede
            // uguali hanno lo stesso colore a ogni avvio.
            accent: answers.daysPerWeek % 6,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
    }
}
