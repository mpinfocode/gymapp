import Foundation

/// La scheda di riserva: deterministica, senza AI, sempre valida.
///
/// Serve in tre casi, tutti reali: non c'è rete, il modello risponde male, o
/// l'utente non vuole aspettare. Il risultato non è un ripiego triste: riempie
/// gli schemi motori previsti dal giorno scegliendo per priorità, rispetta
/// attrezzatura, esperienza e zone da proteggere, e supera il proprio
/// validatore per ogni combinazione di risposte.
///
/// Il `seed` serve al pulsante "Rigenera": stesso seme, stessa scheda; seme
/// diverso, seconde e terze scelte al posto delle prime.
public enum FallbackProgramGenerator {

    /// Costruisce la scheda.
    public static func makeDraft(
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates,
        seed: Int = 0
    ) -> GeneratedProgramDraft {
        var usedInProgram: Set<String> = []
        var days: [GeneratedProgramDraft.Day] = []

        let cardioCandidates = candidates.items(pattern: .cardio)
        let wantsCardio = answers.includeCardio && !cardioCandidates.isEmpty
        // Il cardio occupa un posto: gli esercizi con i pesi sono uno in meno.
        let target = parameters.targetExercisesPerDay
        let strengthTarget = max(parameters.exercisesPerDay.lowerBound, wantsCardio ? target - 1 : target)

        for (dayIndex, blueprint) in parameters.days.enumerated() {
            var items: [GeneratedProgramDraft.Item] = []
            var usedInDay: Set<String> = []
            // Due esercizi diversi possono avere lo stesso titolo breve
            // ("Seated Row" ai cavi e alla macchina): nello stesso giorno
            // sembrerebbero un errore di copia.
            var usedNames: Set<String> = []
            var groupsInDay: Set<MuscleGroup> = []

            func append(_ candidate: GeneratorCandidate) {
                usedInDay.insert(candidate.id)
                usedNames.insert(candidate.shortName)
                usedInProgram.insert(candidate.id)
                groupsInDay.insert(candidate.group)
                items.append(makeItem(for: candidate, parameters: parameters))
            }

            // 1. Si riempiono gli schemi motori del giorno, in ordine.
            for pattern in blueprint.patternSequence(count: strengthTarget) {
                guard items.count < strengthTarget else { break }
                var pool = candidates.items(pattern: pattern)
                    .filter { !usedInDay.contains($0.id) && !usedNames.contains($0.shortName) }
                // Fra i candidati dello stesso schema si preferisce il muscolo
                // per cui lo schema sta nel giorno.
                if let primary = pattern.primaryGroup {
                    let onTarget = pool.filter { $0.group == primary }
                    if !onTarget.isEmpty { pool = onTarget }
                }
                guard let pick = choose(from: pool, seed: seed, dayIndex: dayIndex, avoiding: usedInProgram) else { continue }
                append(pick)
            }

            // 2. Se il giorno è rimasto corto (attrezzatura scarsa, zone
            //    protette), si completa con i gruppi già presenti: meglio una
            //    seconda spinta che un giorno da tre esercizi.
            if items.count < parameters.exercisesPerDay.lowerBound {
                let fill = candidates.items
                    .filter { !usedInDay.contains($0.id) && !usedNames.contains($0.shortName) && $0.pattern != .cardio }
                    .filter { groupsInDay.isEmpty || groupsInDay.contains($0.group) }
                    .sorted(by: GeneratorCandidates.isBetter)
                for candidate in fill where items.count < parameters.exercisesPerDay.lowerBound {
                    append(candidate)
                }
            }
            // 3. Se ancora corto, si prende quel che c'è.
            if items.count < parameters.exercisesPerDay.lowerBound {
                let fill = candidates.items
                    .filter { !usedInDay.contains($0.id) && $0.pattern != .cardio }
                    .sorted(by: GeneratorCandidates.isBetter)
                for candidate in fill where items.count < parameters.exercisesPerDay.lowerBound {
                    append(candidate)
                }
            }

            // 4. Multiarticolari davanti.
            items = GeneratorValidator.stableCompoundFirst(items, candidates: candidates)

            // 5. Cardio in coda.
            if wantsCardio, let seconds = parameters.cardioSeconds {
                let pool = cardioCandidates.filter { !usedInDay.contains($0.id) }
                if let pick = choose(from: pool, seed: seed, dayIndex: dayIndex, avoiding: usedInProgram) ?? cardioCandidates.first {
                    usedInDay.insert(pick.id)
                    usedInProgram.insert(pick.id)
                    items.append(
                        GeneratedProgramDraft.Item(
                            id: pick.id,
                            sets: 1,
                            seconds: seconds,
                            rest: 60,
                            note: "Ritmo costante, respirazione controllata"
                        )
                    )
                }
            }

            days.append(GeneratedProgramDraft.Day(name: blueprint.name, items: items))
        }

        // Le stesse regole che si impongono alla risposta del modello valgono
        // anche qui: varietà fra giorni gemelli, copertura, equilibrio, ordine.
        // Passare di qui costa nulla (la scheda di riserva è già quasi a posto)
        // ed evita che le due strade divergano al primo ritocco delle regole.
        let draft = GeneratedProgramDraft(name: name(for: answers), days: days)
        return GeneratorValidator.repair(
            draft,
            answers: answers,
            parameters: parameters,
            candidates: candidates
        ).draft
    }

    /// La scheda di riserva già convertita in ``Program``.
    public static func makeProgram(
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates,
        seed: Int = 0,
        now: Date = Date()
    ) -> Program {
        let draft = makeDraft(answers: answers, parameters: parameters, candidates: candidates, seed: seed)
        return GeneratorValidator.program(from: draft, answers: answers, candidates: candidates, now: now)
    }

    // MARK: - Scelta

    /// Sceglie un esercizio dalla rosa.
    ///
    /// Con `seed == 0` prende sempre il migliore: è la scheda "giusta".
    /// Con un seme diverso ruota sulle prime tre scelte, così "Rigenera" cambia
    /// davvero qualcosa restando sensato. A parità, preferisce un esercizio non
    /// ancora usato in settimana.
    static func choose(
        from pool: [GeneratorCandidate],
        seed: Int,
        dayIndex: Int,
        avoiding usedInProgram: Set<String>
    ) -> GeneratorCandidate? {
        guard !pool.isEmpty else { return nil }
        let fresh = pool.filter { !usedInProgram.contains($0.id) }
        let usable = fresh.isEmpty ? pool : fresh
        guard seed != 0, usable.count > 1 else { return usable.first }
        let window = min(3, usable.count)
        // Rotazione deterministica: nessun generatore casuale, così la stessa
        // combinazione di seme e giorno dà sempre la stessa scheda.
        let offset = abs(seed &* 31 &+ dayIndex &* 7) % window
        return usable[offset]
    }

    static func makeItem(
        for candidate: GeneratorCandidate,
        parameters: GeneratorPlanParameters
    ) -> GeneratedProgramDraft.Item {
        let reps = parameters.reps(for: candidate.kind)
        let rest = parameters.rest(for: candidate.kind).clamped(to: GeneratorValidator.restRange)

        // Plank e affini si misurano a tempo: mettere "10 ripetizioni" su un
        // plank è il classico errore da scheda generata male.
        if isHold(candidate) {
            return GeneratedProgramDraft.Item(
                id: candidate.id,
                sets: parameters.sets(for: .isolation),
                seconds: 40,
                rest: rest,
                note: nil
            )
        }

        return GeneratedProgramDraft.Item(
            id: candidate.id,
            sets: parameters.sets(for: candidate.kind),
            repsMin: reps.lowerBound,
            repsMax: reps.upperBound,
            rest: rest,
            note: nil
        )
    }

    /// Esercizi isometrici: si tengono, non si ripetono.
    /// `2135` front plank, `3544` side plank, `0624` wall sit.
    public static let holdIDs: Set<String> = ["2135", "3544", "0624"]

    static func isHold(_ candidate: GeneratorCandidate) -> Bool {
        holdIDs.contains(candidate.id)
    }

    /// Nome della scheda: lo stesso che decide il telefono per le schede
    /// dell'AI, così due schede uguali si chiamano uguale.
    public static func name(for answers: GeneratorAnswers) -> String {
        GeneratorValidator.defaultName(for: answers)
    }
}
