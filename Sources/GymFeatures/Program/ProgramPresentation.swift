import Foundation
import GymCore

/// Testi e piccole trasformazioni della sezione Scheda: funzioni pure, senza
/// SwiftUI, così restano leggibili e verificabili a colpo d'occhio.
///
/// Regole rispettate qui: mai "—" né "–", "·" come separatore, "-" solo nei range
/// numerici ("8-12").
enum ProgramPresentation {

    // MARK: - Conteggi

    /// "nessun esercizio" / "1 esercizio" / "6 esercizi".
    static func exerciseCount(_ count: Int) -> String {
        switch count {
        case ..<1: "nessun esercizio"
        case 1: "1 esercizio"
        default: "\(count) esercizi"
        }
    }

    /// "1 giorno" / "3 giorni".
    static func dayCount(_ count: Int) -> String {
        count == 1 ? "1 giorno" : "\(count) giorni"
    }

    /// Sottoriga del giorno nella pagina della scheda: solo il conteggio.
    ///
    /// I giorni sono un semplice elenco con un nome: la modalità rotazione / giorni
    /// fissi è sparita dalla UI (SPEC §0).
    static func daySubtitle(_ day: ProgramDay) -> String {
        exerciseCount(day.items.count)
    }

    // MARK: - Voci di piano

    /// Tempi brevi (durata di una serie, recupero): "45 s", "1:30".
    /// Il formato è uno solo per tutta l'app, sta in ``Formatters/shortDuration(seconds:)``.
    static func seconds(_ value: Int) -> String {
        Formatters.shortDuration(seconds: value)
    }

    /// Obiettivo della serie: "8-12", "10", "45 s", "1:30".
    static func measureText(_ measure: SetMeasure) -> String {
        switch measure {
        case .reps:
            return measure.displayText
        case .duration(let total):
            return seconds(total)
        }
    }

    /// Riepilogo compatto di una riga: "4 × 8-12 · 60 kg · 90 s", "3 × 45 s · 60 s".
    static func itemSummary(_ item: PlanItem, unit: WeightUnit) -> String {
        var parts = ["\(item.targetSets) × \(measureText(item.measure))"]
        if let weight = item.targetWeightKg {
            parts.append(Formatters.weight(weight, unit: unit))
        }
        if item.restSeconds > 0 {
            parts.append(seconds(item.restSeconds))
        }
        return parts.joined(separator: " · ")
    }

    /// Lettera del superset per ogni gruppo presente nel giorno ("A", "B"…).
    static func supersetLetters(in day: ProgramDay) -> [Int: String] {
        var letters: [Int: String] = [:]
        for (index, group) in day.supersetGroups.enumerated() {
            letters[group] = letter(at: index)
        }
        return letters
    }

    /// "A", "B", … "Z", poi "A1", "B1"… (in pratica non si arriva mai oltre la B).
    static func letter(at index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard index >= 0 else { return alphabet[0].description }
        let base = alphabet[index % alphabet.count].description
        let round = index / alphabet.count
        return round == 0 ? base : base + String(round)
    }

    /// Nome di default del giorno creato per primo, secondo, terzo: "Giorno A"…
    static func defaultDayName(at index: Int) -> String {
        "Giorno " + letter(at: index)
    }

    // MARK: - Scheda

    /// Data estesa senza anno: "12 ottobre".
    static func longDay(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.day, .month], from: date)
        let day = components.day ?? 1
        let month = components.month ?? 1
        let name = Formatters.months.indices.contains(month - 1) ? Formatters.months[month - 1] : ""
        return "\(day) \(name)"
    }

    /// Riga di stato della card: "Settimana 3 di 6 · fino al 12 ottobre".
    static func programStatus(_ program: Program, now: Date, calendar: Calendar) -> String {
        guard let end = program.endDate(calendar: calendar) else { return "Senza scadenza" }
        let day = longDay(end, calendar: calendar)
        if program.isExpired(asOf: now, calendar: calendar) {
            return "Scaduta il \(day)"
        }
        return program.statusText(asOf: now, calendar: calendar) + " · fino al \(day)"
    }

    /// Nome proposto per una scheda nuova: "Scheda settembre".
    static func defaultProgramName(now: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: now)
        let name = Formatters.months.indices.contains(month - 1) ? Formatters.months[month - 1] : ""
        return name.isEmpty ? "Scheda" : "Scheda \(name)"
    }

    // MARK: - Superset

    /// `true` se le due voci sono nello stesso superset.
    static func areLinked(_ items: [PlanItem], _ first: Int, _ second: Int) -> Bool {
        guard items.indices.contains(first), items.indices.contains(second) else { return false }
        guard let group = items[first].supersetGroup else { return false }
        return group == items[second].supersetGroup
    }

    /// Lega o slega la voce `index` con quella `neighbor`, poi ripulisce i gruppi
    /// rimasti con un solo esercizio (un superset da solo non esiste).
    static func toggleSuperset(_ items: [PlanItem], at index: Int, with neighbor: Int) -> [PlanItem] {
        guard items.indices.contains(index), items.indices.contains(neighbor) else { return items }
        var result = items

        if areLinked(result, index, neighbor) {
            result[index].supersetGroup = nil
        } else if let group = result[neighbor].supersetGroup {
            result[index].supersetGroup = group
        } else if let group = result[index].supersetGroup {
            result[neighbor].supersetGroup = group
        } else {
            let next = (result.compactMap(\.supersetGroup).max() ?? 0) + 1
            result[index].supersetGroup = next
            result[neighbor].supersetGroup = next
        }

        return normalizedSupersets(result)
    }

    /// Toglie il gruppo alle voci che restano sole nel proprio superset.
    static func normalizedSupersets(_ items: [PlanItem]) -> [PlanItem] {
        var counts: [Int: Int] = [:]
        for item in items {
            guard let group = item.supersetGroup else { continue }
            counts[group, default: 0] += 1
        }
        return items.map { item in
            guard let group = item.supersetGroup, counts[group, default: 0] < 2 else { return item }
            var copy = item
            copy.supersetGroup = nil
            return copy
        }
    }

    // MARK: - Valori proposti

    /// Range di ripetizioni proposti dalle scorciatoie rapide dell'editor.
    static let repsShortcuts: [ClosedRange<Int>] = [6...8, 8...10, 8...12, 10...12, 12...15, 15...20]

    /// Durate proposte per gli esercizi a tempo.
    static let durationShortcuts = [20, 30, 45, 60, 90]

    /// Recuperi proposti, in secondi.
    static let restShortcuts = [30, 45, 60, 90, 120, 180]
}
