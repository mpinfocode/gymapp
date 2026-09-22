import Foundation
import GymCore

/// Controlli di qualità che vanno oltre il validatore: dicono se la scheda è
/// *buona*, non solo se è *lecita*.
struct QualityReport {

    struct Finding {
        let passed: Bool
        let text: String

        var line: String { "\(passed ? "ok " : "KO ") \(text)" }
    }

    let findings: [Finding]
    let distributionLines: [String]

    var failures: [String] { findings.filter { !$0.passed }.map(\.text) }
    var isClean: Bool { failures.isEmpty }

    static func make(
        draft: GeneratedProgramDraft,
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates,
        exercisesByID: [String: Exercise]
    ) -> QualityReport {
        var findings: [Finding] = []

        // Zone protette
        let violations = draft.days.flatMap { day in
            day.items.compactMap { item -> String? in
                guard let candidate = candidates.candidate(id: item.id) else { return nil }
                guard !candidate.stress.isDisjoint(with: answers.protectedZones) else { return nil }
                return "\(day.name): \(candidate.shortName)"
            }
        }
        findings.append(
            Finding(
                passed: violations.isEmpty,
                text: answers.protectedZones.isEmpty
                    ? "nessuna zona da proteggere richiesta"
                    : "zone protette rispettate\(violations.isEmpty ? "" : " (" + violations.joined(separator: ", ") + ")")"
            )
        )

        // Attrezzatura
        let available = answers.equipment.equipmentClass
        let wrongEquipment = draft.days.flatMap { day in
            day.items.compactMap { item -> String? in
                guard let candidate = candidates.candidate(id: item.id) else { return nil }
                guard candidate.equipmentClass.rank > available.rank else { return nil }
                return "\(day.name): \(candidate.shortName) (\(candidate.equipment))"
            }
        }
        findings.append(
            Finding(
                passed: wrongEquipment.isEmpty,
                text: "attrezzatura rispettata\(wrongEquipment.isEmpty ? "" : " (" + wrongEquipment.joined(separator: ", ") + ")")"
            )
        )

        // Doppioni fra giorni diversi
        var occurrences: [String: Int] = [:]
        for day in draft.days {
            for item in day.items { occurrences[item.id, default: 0] += 1 }
        }
        let repeated = occurrences.filter { $0.value > 1 }
            .compactMap { candidates.candidate(id: $0.key)?.shortName }
            .sorted()
        // Ripetere un esercizio in due giorni è normale su una divisione a 6
        // giorni, diventa pigrizia quando è sistematico.
        let repeatedShare = Double(repeated.count) / Double(max(1, occurrences.count))
        findings.append(
            Finding(
                passed: repeatedShare <= 0.35,
                text: "esercizi ripetuti fra i giorni: \(repeated.count) su \(occurrences.count)\(repeated.isEmpty ? "" : " (" + repeated.prefix(5).joined(separator: ", ") + ")")"
            )
        )

        // Equilibrio spinta/tirata
        let pushPatterns: Set<MovementPattern> = [.horizontalPush, .verticalPush, .chestIsolation]
        let pullPatterns: Set<MovementPattern> = [.horizontalPull, .verticalPull, .backIsolation]
        var pushSets = 0
        var pullSets = 0
        for day in draft.days {
            for item in day.items {
                guard let candidate = candidates.candidate(id: item.id) else { continue }
                if pushPatterns.contains(candidate.pattern) { pushSets += item.sets }
                if pullPatterns.contains(candidate.pattern) { pullSets += item.sets }
            }
        }
        let balanced = pushSets == 0 && pullSets == 0
            ? true
            : Double(min(pushSets, pullSets)) >= 0.6 * Double(max(pushSets, pullSets))
        findings.append(
            Finding(passed: balanced, text: "equilibrio spinta/tirata: \(pushSets) serie contro \(pullSets)")
        )

        // Volume settimanale per gruppo rispetto al previsto
        let items = draft.days.flatMap { day in
            day.items.map { item in
                PlanItem(
                    exerciseID: item.id,
                    targetSets: item.sets,
                    measure: item.measure,
                    restSeconds: item.rest
                )
            }
        }
        let distribution = Stats.muscleDistribution(items: items) { exercisesByID[$0] }
        var distributionLines: [String] = []
        var underTrained: [String] = []
        for share in distribution.shares where share.group != .cardio && share.group != .other {
            let expected = parameters.weeklySetsByGroup[share.group] ?? 0
            let direct = Int(share.directSets.rounded())
            distributionLines.append(
                "  \(share.group.displayName.padding(toLength: 14, withPad: " ", startingAt: 0)) \(String(format: "%3d", direct)) serie dirette, \(String(format: "%4.1f", share.weightedSets)) pesate, \(share.percent)% (previste ~\(expected))"
            )
            // Solo i gruppi grossi devono avvicinarsi al volume previsto: per
            // polpacci e avambracci il "previsto" è una soglia teorica che
            // nessuna scheda sensata da 45 minuti raggiunge.
            // Con due sedute a settimana il volume "previsto" è irraggiungibile
            // per costruzione: non ha senso segnalarlo.
            let majors: Set<MuscleGroup> = [.chest, .back, .shoulders, .quads]
            if answers.daysPerWeek >= 3, majors.contains(share.group), direct * 2 < expected {
                underTrained.append("\(share.group.displayName) \(direct)/\(expected)")
            }
        }
        for group in distribution.neverTrainedGroups where group != .cardio && group != .other {
            distributionLines.append("  \(group.displayName): mai allenato")
        }
        findings.append(
            Finding(
                passed: underTrained.isEmpty,
                text: "volume dei gruppi principali\(underTrained.isEmpty ? " coerente" : " sotto la metà del previsto: " + underTrained.joined(separator: ", "))"
            )
        )

        // Priorità
        if !answers.focusGroups.isEmpty {
            let focusSets = distribution.shares
                .filter { answers.focusGroups.contains($0.group) }
                .reduce(0) { $0 + Int($1.directSets.rounded()) }
            let otherSets = distribution.shares
                .filter { !answers.focusGroups.contains($0.group) && $0.group != .cardio && $0.group != .other }
                .reduce(0) { $0 + Int($1.directSets.rounded()) }
            let groupsCount = max(1, distribution.shares.count - answers.focusGroups.count)
            let focusAverage = Double(focusSets) / Double(max(1, answers.focusGroups.count))
            let otherAverage = Double(otherSets) / Double(groupsCount)
            findings.append(
                Finding(
                    passed: focusAverage >= otherAverage,
                    text: String(format: "priorità rispettate: %.1f serie medie contro %.1f degli altri gruppi", focusAverage, otherAverage)
                )
            )
        }

        // Cardio
        if answers.includeCardio {
            let daysWithCardio = draft.days.filter { day in
                day.items.contains { candidates.candidate(id: $0.id)?.pattern == .cardio }
            }.count
            findings.append(
                Finding(passed: daysWithCardio == draft.days.count, text: "cardio presente in \(daysWithCardio) giorni su \(draft.days.count)")
            )
        }

        return QualityReport(findings: findings, distributionLines: distributionLines)
    }
}

/// Il voto della bozza **grezza**, quella che il modello ha consegnato prima
/// che il telefono la sistemasse.
///
/// Serve a rispondere alla sola domanda che conta quando si sceglie un modello:
/// *quanto lavoro deve fare la riparazione per rendere presentabile quello che
/// mi manda?* Dopo la riparazione le schede sono tutte a posto, quindi
/// confrontarle non direbbe niente.
struct DraftScore {

    struct Part {
        let name: String
        let earned: Int
        let weight: Int
        let detail: String

        var line: String { "\(name): \(earned)/\(weight)\(detail.isEmpty ? "" : " (\(detail))")" }
    }

    let parts: [Part]

    var total: Int { parts.reduce(0) { $0 + $1.earned } }
    var maximum: Int { parts.reduce(0) { $0 + $1.weight } }

    /// Voto della bozza grezza, ricostruita dai soli id della risposta.
    static func make(
        dayIDs: [[String]],
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> DraftScore {
        var parts: [Part] = []
        let target = parameters.targetExercisesPerDay
        let allowed = parameters.allowedExercisesPerDay

        func items(_ day: [String]) -> [GeneratorCandidate] {
            day.compactMap { candidates.candidate(id: $0) }
        }

        // 1. Numero di esercizi per giorno: il vincolo più tradito.
        let exact = dayIDs.filter { $0.count == target }.count
        let near = dayIDs.filter { $0.count != target && allowed.contains($0.count) }.count
        let countScore = dayIDs.isEmpty ? 0 : Int((Double(exact * 20 + near * 10) / Double(dayIDs.count)).rounded())
        parts.append(
            Part(
                name: "esercizi giusti", earned: min(20, countScore), weight: 20,
                detail: "\(exact) giorni su \(dayIDs.count) con \(target) esercizi"
            )
        )

        // 2. Id leciti: esistono, sono fra i candidati, quindi rispettano
        //    attrezzatura ed esperienza.
        let total = dayIDs.reduce(0) { $0 + $1.count }
        let known = dayIDs.reduce(0) { $0 + items($1).count }
        let levelScore = total == 0 ? 0 : Int((Double(known) / Double(total) * 15).rounded())
        parts.append(
            Part(
                name: "adeguatezza a livello e attrezzatura", earned: levelScore, weight: 15,
                detail: "\(known) id validi su \(total)"
            )
        )

        // 3. Zone da proteggere, senza aiuto della riparazione.
        //
        // Gli esercizi vietati non sono nemmeno fra i candidati, quindi non
        // compaiono in `items(_:)`: se li contassimo solo lì, un modello che
        // sceglie il lento avanti con il bilanciere a una spalla da proteggere
        // prenderebbe 15/15 su questa voce. Si vanno a cercare nella selezione
        // curata, che è dove l'etichetta vive.
        var zoneFaults = 0
        for day in dayIDs {
            let candidatesOfDay = items(day)
            zoneFaults += day.filter { id in
                guard candidates.candidate(id: id) == nil else { return false }
                guard let curated = CuratedExercisePool.byID[id] else { return false }
                return !curated.avoid.isDisjoint(with: answers.protectedZones)
            }.count
            let care = candidatesOfDay.filter(candidates.needsCare).count
            zoneFaults += max(0, care - GeneratorRepair.maxCautionPerDay)
            if let first = candidatesOfDay.first, candidates.needsCare(first) { zoneFaults += 1 }
        }
        let zoneScore = answers.protectedZones.isEmpty ? 15 : max(0, 15 - zoneFaults * 5)
        parts.append(
            Part(
                name: "zone protette", earned: zoneScore, weight: 15,
                detail: answers.protectedZones.isEmpty ? "nessuna richiesta" : "\(zoneFaults) scivoloni"
            )
        )

        // 4. Varietà fra giorni dello stesso tipo.
        var excess = 0
        var pairs = 0
        for first in dayIDs.indices {
            for second in dayIDs.indices where second > first {
                guard GeneratorValidator.areSimilar(first, second, parameters: parameters) else { continue }
                pairs += 1
                let shared = Set(dayIDs[first]).intersection(dayIDs[second]).count
                excess += max(0, shared - GeneratorRepair.maxSharedBetweenSimilarDays)
            }
        }
        let twinScore = pairs == 0 ? 15 : max(0, 15 - excess * 4)
        parts.append(
            Part(
                name: "varietà fra giorni gemelli", earned: twinScore, weight: 15,
                detail: pairs == 0 ? "nessuna coppia di giorni simili" : "\(excess) doppioni di troppo"
            )
        )

        // 5. Copertura dei gruppi.
        var trained: Set<MuscleGroup> = []
        var patterns: Set<MovementPattern> = []
        for day in dayIDs {
            for item in items(day) {
                trained.insert(item.group)
                patterns.insert(item.pattern)
            }
        }
        var wanted = GeneratorRepair.requiredDirectGroups(parameters: parameters)
        let posterior = !trained.isDisjoint(with: GeneratorValidator.requiredPosteriorGroups)
            || !patterns.isDisjoint(with: GeneratorRepair.posteriorPatterns)
        let covered = wanted.filter(trained.contains).count + (posterior ? 1 : 0)
        wanted.append(.hamstrings)
        let coverScore = Int((Double(covered) / Double(wanted.count) * 15).rounded())
        parts.append(
            Part(
                name: "copertura settimanale", earned: coverScore, weight: 15,
                detail: "\(covered) gruppi su \(wanted.count)"
            )
        )

        // 6. Equilibrio fra i blocchi grandi.
        var sets: [GeneratorRepair.BigGroup: Int] = [:]
        for day in dayIDs {
            for item in items(day) {
                guard let big = GeneratorRepair.BigGroup.of(item.group) else { continue }
                sets[big, default: 0] += parameters.sets(for: item.kind)
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
        let imbalance = GeneratorRepair.imbalance(sets, among: planned)
        parts.append(
            Part(
                name: "equilibrio", earned: imbalance == nil ? 10 : 0, weight: 10,
                detail: imbalance.map { "\($0.low.group.displayName) \($0.low.sets) contro \($0.high.group.displayName) \($0.high.sets)" } ?? "nessuno squilibrio"
            )
        )

        // 7. Ordine della seduta.
        var wrongOrder = 0
        for day in dayIDs {
            var last = -1
            for item in items(day) {
                let rank = GeneratorRepair.orderRank(item)
                if rank < last { wrongOrder += 1 }
                last = max(last, rank)
            }
        }
        parts.append(
            Part(
                name: "ordine della seduta", earned: max(0, 10 - wrongOrder * 3), weight: 10,
                detail: wrongOrder == 0 ? "corretto" : "\(wrongOrder) esercizi fuori posto"
            )
        )

        return DraftScore(parts: parts)
    }
}

/// Stampa compatta di una scheda.
enum DraftFormatter {

    /// Ricostruisce la bozza **grezza** dai soli id della risposta, mettendoci
    /// i numeri del telefono: serve a mostrare nel rapporto cosa aveva
    /// consegnato il modello, prima di ogni riparazione.
    static func hydrate(
        dayIDs: [[String]],
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> GeneratedProgramDraft {
        let days = dayIDs.enumerated().map { index, ids in
            GeneratedProgramDraft.Day(
                name: parameters.dayNames.indices.contains(index) ? parameters.dayNames[index] : "Giorno \(index + 1)",
                items: ids.map { id in
                    guard let candidate = candidates.candidate(id: id) else {
                        return GeneratedProgramDraft.Item(id: id, sets: 3, repsMin: 8, repsMax: 12, rest: 90)
                    }
                    return GeneratorValidator.numbers(for: candidate, parameters: parameters)
                }
            )
        }
        return GeneratedProgramDraft(name: GeneratorValidator.defaultName(for: answers), days: days)
    }

    /// La scheda riga per riga con tutto quel che serve a giudicarla a mano:
    /// id, nome, attrezzo, tipo, livello, schema motorio, zone toccate e in
    /// quali altri giorni lo stesso esercizio ritorna.
    ///
    /// Il titolo breve da solo non basta: "Bench Press" può essere il bilanciere,
    /// i manubri o il multipower, e sono tre esercizi diversi per una spalla.
    static func auditLines(
        draft: GeneratedProgramDraft,
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> [String] {
        var output: [String] = []
        var occurrences: [String: [String]] = [:]
        for day in draft.days {
            for item in day.items { occurrences[item.id, default: []].append(day.name) }
        }

        for day in draft.days {
            output.append(day.name)
            for item in day.items {
                guard let candidate = candidates.candidate(id: item.id) else {
                    output.append("    \(item.id) · fuori dai candidati")
                    continue
                }
                var zones = "nessuna"
                let avoided = candidate.avoidZones.intersection(answers.protectedZones)
                let careful = candidate.cautionZones.intersection(answers.protectedZones)
                if !avoided.isEmpty {
                    zones = "VIETATO per " + StressZone.displayOrder.filter(avoided.contains).map(\.displayName).joined(separator: ", ")
                } else if !careful.isEmpty {
                    zones = "delicato per " + StressZone.displayOrder.filter(careful.contains).map(\.displayName).joined(separator: ", ")
                }
                let elsewhere = (occurrences[item.id] ?? []).filter { $0 != day.name }
                output.append(
                    "    \(item.id) · \(candidate.shortName) · \(candidate.equipment)"
                    + " · \(candidate.kind.displayName.lowercased()) · \(candidate.level.displayName.lowercased())"
                    + " · \(candidate.pattern.displayName)"
                    + " · zone: \(zones)"
                    + " · ripetuto in: \(elsewhere.isEmpty ? "nessun altro giorno" : elsewhere.joined(separator: ", "))"
                )
            }
        }

        // Il livello richiesto, e le coppie di giorni dello stesso tipo.
        let tooHard = draft.days.flatMap { day in
            day.items.compactMap { item -> String? in
                guard let candidate = candidates.candidate(id: item.id) else { return nil }
                guard candidate.level > answers.experience.maxExerciseLevel else { return nil }
                return "\(candidate.id) \(candidate.shortName)"
            }
        }
        output.append(
            "Livello richiesto (\(answers.experience.displayName)): "
                + (tooHard.isEmpty ? "rispettato da tutti gli esercizi" : "sforato da " + tooHard.joined(separator: ", "))
        )
        for first in draft.days.indices {
            for second in draft.days.indices where second > first {
                guard GeneratorValidator.areSimilar(first, second, parameters: parameters) else { continue }
                let shared = Set(draft.days[first].items.map(\.id))
                    .intersection(draft.days[second].items.map(\.id))
                    .compactMap { candidates.candidate(id: $0).map { "\($0.id) \($0.shortName)" } }
                    .sorted()
                output.append(
                    "Giorni dello stesso tipo, \(draft.days[first].name) e \(draft.days[second].name): "
                    + "\(shared.count) esercizi in comune su \(GeneratorRepair.maxSharedBetweenSimilarDays) ammessi"
                    + (shared.isEmpty ? "" : " (" + shared.joined(separator: ", ") + ")")
                )
            }
        }
        return output
    }

    static func lines(
        draft: GeneratedProgramDraft,
        candidates: GeneratorCandidates
    ) -> [String] {
        var output = ["Scheda: \(draft.name)"]
        for day in draft.days {
            output.append("  \(day.name)")
            for item in day.items {
                let candidate = candidates.candidate(id: item.id)
                // Id, nome **e attrezzo**: il titolo breve toglie il prefisso
                // dell'attrezzo (SPEC §0), così "Bench Press" può essere la
                // panca con il bilanciere, con i manubri o al multipower. Nel
                // rapporto quella differenza è esattamente quella che si deve
                // poter giudicare.
                let name = candidate.map { "\($0.id) · \($0.shortName) · \($0.equipment)" }
                    ?? "\(item.id) · esercizio fuori dai candidati"
                let target: String
                if let seconds = item.seconds, item.repsMin == nil {
                    target = SetMeasure.formatDuration(seconds)
                } else if let low = item.repsMin, let high = item.repsMax {
                    target = low == high ? "\(low)" : "\(low)-\(high)"
                } else {
                    target = "?"
                }
                var line = "    \(item.sets) x \(target)  rec \(item.rest)s  \(name)"
                if let note = item.note, !note.isEmpty { line += "  · \(note)" }
                output.append(line)
            }
        }
        return output
    }
}
