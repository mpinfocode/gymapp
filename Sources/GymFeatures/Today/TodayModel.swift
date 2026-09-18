import Foundation
import GymCore
import GymUI

/// Logica di presentazione della schermata Oggi.
///
/// Funzioni pure: nessuna dipendenza da SwiftUI, nessuna lettura dell'orologio di
/// sistema (la data arriva sempre da `app.now`). Sta qui tutto ciò che si potrebbe
/// voler verificare a mente o con un check, così la view resta solo composizione.
enum TodayModel {

    // MARK: - Saluto

    /// "Buon pomeriggio, Francesco". Senza nome resta solo la parte oraria.
    static func greeting(at date: Date, name: String, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let moment: String
        switch hour {
        case 0..<12: moment = "Buongiorno"
        case 12..<18: moment = "Buon pomeriggio"
        default: moment = "Buonasera"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? moment : "\(moment), \(trimmed)"
    }

    // MARK: - Stima della durata

    /// Tempo medio di esecuzione di una serie a ripetizioni, in secondi.
    /// Stima volutamente grossolana: meglio onesta che finta precisione.
    static let averageSetSeconds = 40

    /// Durata stimata di un giorno: per ogni serie il recupero più il tempo di
    /// esecuzione (circa 40 secondi, o la durata prevista per gli esercizi a tempo).
    static func estimatedSeconds(of day: ProgramDay) -> Int {
        day.items.reduce(0) { total, item in
            let sets = max(0, item.targetSets + item.warmupSets)
            let work = item.measure.durationSeconds ?? averageSetSeconds
            return total + sets * (item.restSeconds + work)
        }
    }

    /// Minuti stimati, arrotondati a multipli di 5 per non fingere precisione.
    static func estimatedMinutes(of day: ProgramDay) -> Int {
        let seconds = estimatedSeconds(of: day)
        guard seconds > 0 else { return 0 }
        let minutes = Double(seconds) / 60
        return max(5, Int((minutes / 5).rounded()) * 5)
    }

    /// Sottoriga della hero: "6 esercizi · circa 55 min".
    static func summary(of day: ProgramDay) -> String {
        let count = day.items.count
        let word = count == 1 ? "esercizio" : "esercizi"
        let minutes = estimatedMinutes(of: day)
        guard minutes > 0 else { return "\(count) \(word)" }
        return "\(count) \(word) · circa \(Formatters.minutes(seconds: minutes * 60))"
    }

    // MARK: - Stato della scheda

    /// Riga di stato della scheda: avanzamento oppure avviso di scadenza.
    enum ProgramStatus: Equatable {
        /// Scheda senza durata prevista: nessuna riga da mostrare.
        case none
        /// "Settimana 3 di 6" con la frazione per la barra.
        case progress(text: String, fraction: Double)
        /// La scheda sta per scadere o è già scaduta: la riga diventa l'avviso.
        case warning(String)
    }

    static func status(of program: Program, now: Date, calendar: Calendar) -> ProgramStatus {
        guard let weeks = program.plannedWeeks, weeks > 0 else { return .none }

        if program.isExpired(asOf: now, calendar: calendar) {
            return .warning("Scheda scaduta")
        }
        if program.isExpiringSoon(asOf: now, calendar: calendar) {
            switch program.daysToExpiry(asOf: now, calendar: calendar) ?? 0 {
            case 0: return .warning("La scheda scade oggi")
            case 1: return .warning("La scheda scade domani")
            case let days: return .warning("La scheda scade tra \(days) giorni")
            }
        }
        let week = min(program.currentWeek(asOf: now, calendar: calendar), weeks)
        return .progress(text: "Settimana \(week) di \(weeks)", fraction: Double(week) / Double(weeks))
    }

    // MARK: - Settimana

    /// I sette giorni della settimana corrente, da lunedì a domenica.
    ///
    /// Completato = c'è una sessione conclusa quel giorno. Pianificato = solo in
    /// modalità a giorni fissi, per i giorni da oggi in poi assegnati a un giorno
    /// della scheda.
    static func weekDays(
        now: Date,
        calendar: Calendar,
        sessions: [WorkoutSession],
        program: Program?
    ) -> [WeekDayItem] {
        let today = calendar.startOfDay(for: now)
        let start = Stats.startOfWeek(for: now, calendar: calendar) ?? today
        let trainedWeekdays = Set(
            sessions
                .filter { $0.hasLoggedWork }
                .map { calendar.startOfDay(for: $0.startedAt) }
        )
        let plannedWeekdays: Set<Weekday> = {
            guard let program, program.mode == .weekdays else { return [] }
            return Set(program.days.compactMap(\.weekday))
        }()

        return Weekday.allCases.enumerated().map { index, weekday in
            let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
            let day = calendar.startOfDay(for: date)
            let state: DayState
            if trainedWeekdays.contains(day) {
                state = .completed
            } else if day >= today, plannedWeekdays.contains(weekday) {
                state = .planned
            } else {
                state = .rest
            }
            return WeekDayItem(
                id: index,
                initial: weekday.letter,
                fullName: weekday.italianName,
                dayNumber: calendar.component(.day, from: day),
                state: state,
                isToday: day == today
            )
        }
    }

    // MARK: - Sessione di oggi

    /// La sessione conclusa oggi, se c'è (la più recente).
    static func sessionCompletedToday(
        in sessions: [WorkoutSession],
        now: Date,
        calendar: Calendar
    ) -> WorkoutSession? {
        let today = calendar.startOfDay(for: now)
        return sessions.first {
            $0.hasLoggedWork && calendar.startOfDay(for: $0.startedAt) == today
        }
    }
}
