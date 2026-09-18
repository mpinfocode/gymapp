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

/// Stampa compatta di una scheda.
enum DraftFormatter {

    static func lines(
        draft: GeneratedProgramDraft,
        candidates: GeneratorCandidates
    ) -> [String] {
        var output = ["Scheda: \(draft.name)"]
        for day in draft.days {
            output.append("  \(day.name)")
            for item in day.items {
                let candidate = candidates.candidate(id: item.id)
                let name = candidate?.shortName ?? "??? (\(item.id))"
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
