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

        let low = max(1, parameters.exercisesPerDay.lowerBound - 1)
        let high = parameters.exercisesPerDay.upperBound + 1

        var groupsTrained: Set<MuscleGroup> = []

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
            var sawIsolation = false

            for item in day.items {
                guard let candidate = candidates.candidate(id: item.id) else {
                    errors.append("\(label): l'esercizio \(item.id) non è fra i candidati proposti.")
                    continue
                }
                if !seen.insert(item.id).inserted {
                    errors.append("\(label): \(candidate.shortName) compare due volte.")
                }
                groupsTrained.insert(candidate.group)

                if !setsRange.contains(item.sets) {
                    errors.append("\(label), \(candidate.shortName): \(item.sets) serie, ammesse da \(setsRange.lowerBound) a \(setsRange.upperBound).")
                }
                if let seconds = item.seconds, item.repsMin == nil {
                    if !secondsRange.contains(seconds) {
                        errors.append("\(label), \(candidate.shortName): durata di \(seconds) s fuori dai limiti.")
                    }
                } else {
                    guard let minimum = item.repsMin, let maximum = item.repsMax else {
                        errors.append("\(label), \(candidate.shortName): mancano le ripetizioni.")
                        continue
                    }
                    if !repsRange.contains(minimum) || !repsRange.contains(maximum) {
                        errors.append("\(label), \(candidate.shortName): ripetizioni fuori da \(repsRange.lowerBound)-\(repsRange.upperBound).")
                    }
                    if minimum > maximum {
                        errors.append("\(label), \(candidate.shortName): ripetizioni minime maggiori delle massime.")
                    }
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
                if !candidate.stress.isDisjoint(with: answers.protectedZones) {
                    let zones = StressZone.displayOrder
                        .filter { candidate.stress.contains($0) && answers.protectedZones.contains($0) }
                        .map(\.displayName)
                    errors.append("\(label), \(candidate.shortName): sollecita una zona da proteggere (\(zones.joined(separator: ", "))).")
                }

                if candidate.kind == .isolation {
                    sawIsolation = true
                } else if sawIsolation {
                    errors.append("\(label): \(candidate.shortName) è multiarticolare e viene dopo un esercizio di isolamento.")
                }
            }
        }

        // Copertura settimanale: le schede da due giorni sono esentate, non
        // possono coprire tutto senza diventare maratone.
        if draft.days.count > 2 {
            for group in requiredWeeklyGroups where !groupsTrained.contains(group) {
                errors.append("Nessun esercizio per \(group.displayName) in tutta la settimana.")
            }
            if groupsTrained.isDisjoint(with: requiredPosteriorGroups) {
                errors.append("Nessun esercizio per femorali o glutei in tutta la settimana.")
            }
        }

        // Rilievi non bloccanti
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

    // MARK: - Riparazione

    /// Corregge i difetti piccoli e dice cosa ha corretto.
    ///
    /// Fa **solo** cose che non cambiano le scelte del modello: riporta i numeri
    /// nei limiti, toglie i doppioni e gli id inventati, accorcia le note, mette
    /// i multiarticolari davanti. Non aggiunge esercizi e non cambia i giorni:
    /// se manca della roba, la risposta va scartata.
    public static func repair(
        _ draft: GeneratedProgramDraft,
        answers: GeneratorAnswers,
        parameters: GeneratorPlanParameters,
        candidates: GeneratorCandidates
    ) -> (draft: GeneratedProgramDraft, repairs: [String]) {
        var repairs: [String] = []
        var result = draft

        // Nome
        var name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains(where: forbiddenDashes.contains) {
            name = sanitizeDashes(name)
            repairs.append("Tolto un trattino lungo dal nome della scheda.")
        }
        if name.count > maxNameLength {
            name = String(name.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
            repairs.append("Accorciato il nome della scheda.")
        }
        if name.isEmpty {
            name = defaultName(for: answers)
            repairs.append("Dato un nome alla scheda.")
        }
        result.name = name

        let high = parameters.exercisesPerDay.upperBound + 1

        for dayIndex in result.days.indices {
            var day = result.days[dayIndex]
            let label = day.name.isEmpty ? "Giorno \(dayIndex + 1)" : day.name

            if day.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                day.name = parameters.days.indices.contains(dayIndex) ? parameters.days[dayIndex].name : "Giorno \(dayIndex + 1)"
                repairs.append("Dato un nome al giorno \(dayIndex + 1).")
            } else if day.name.contains(where: forbiddenDashes.contains) {
                day.name = sanitizeDashes(day.name)
                repairs.append("\(label): tolto un trattino lungo dal nome.")
            }

            var seen: Set<String> = []
            var items: [GeneratedProgramDraft.Item] = []

            for var item in day.items {
                guard let candidate = candidates.candidate(id: item.id) else {
                    repairs.append("\(label): tolto l'esercizio \(item.id), non è fra i candidati.")
                    continue
                }
                guard seen.insert(item.id).inserted else {
                    repairs.append("\(label): tolto il doppione \(candidate.shortName).")
                    continue
                }
                if !candidate.stress.isDisjoint(with: answers.protectedZones) {
                    repairs.append("\(label): tolto \(candidate.shortName), sollecita una zona da proteggere.")
                    seen.remove(item.id)
                    continue
                }

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
                items.append(item)
            }

            // Multiarticolari davanti, ordine relativo invariato.
            let sorted = stableCompoundFirst(items, candidates: candidates)
            if sorted.map(\.id) != items.map(\.id) {
                repairs.append("\(label): multiarticolari rimessi davanti agli isolamenti.")
            }
            items = sorted

            if items.count > high {
                repairs.append("\(label): tolti \(items.count - high) esercizi di troppo.")
                items = Array(items.prefix(high))
            }

            day.items = items
            result.days[dayIndex] = day
        }

        return (result, repairs)
    }

    /// Multiarticolari prima degli isolamenti, mantenendo l'ordine originale
    /// dentro ciascun gruppo. Il cardio resta in fondo.
    static func stableCompoundFirst(
        _ items: [GeneratedProgramDraft.Item],
        candidates: GeneratorCandidates
    ) -> [GeneratedProgramDraft.Item] {
        func rank(_ item: GeneratedProgramDraft.Item) -> Int {
            guard let candidate = candidates.candidate(id: item.id) else { return 1 }
            if candidate.pattern == .cardio { return 2 }
            return candidate.kind == .compound ? 0 : 1
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

    /// Nome di ripiego per la scheda.
    public static func defaultName(for answers: GeneratorAnswers) -> String {
        "\(answers.split.displayName) \(answers.daysPerWeek) giorni"
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
