import Foundation
import GymCore

/// Un record di carico battuto in una sessione dello storico.
struct RecordEvent: Hashable, Identifiable, Sendable {
    let sessionID: UUID
    let exerciseID: String
    let date: Date
    /// Carico che ha battuto il precedente primato.
    let weightKg: Double
    /// Carico precedente, per la riga "prima 80 kg".
    let previousKg: Double

    var id: String { "\(sessionID.uuidString)-\(exerciseID)" }
}

/// Ricostruzione dei record di carico a partire dallo storico: funzione pura.
///
/// La prima volta che un esercizio compare **non** è un record: senza un primato
/// precedente non c'è niente da battere, e contarla riempirebbe la lista di
/// "record" nati solo dal primo allenamento. Il rilevamento in tempo reale della
/// sessione (``Stats/records(for:achievedBy:sessionVolumeKg:history:earlierSetsInSession:)``)
/// resta più generoso perché lì il primo dato è comunque un'informazione utile.
enum RecordTimeline {

    /// Record di carico, dal più recente al più vecchio.
    static func events(in sessions: [WorkoutSession]) -> [RecordEvent] {
        var best: [String: Double] = [:]
        var events: [RecordEvent] = []

        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            var heaviest: [String: Double] = [:]
            for entry in session.entries {
                for set in entry.sets where set.isWorkingSet {
                    guard let weight = set.weightKg, weight > 0 else { continue }
                    heaviest[entry.exerciseID] = max(heaviest[entry.exerciseID] ?? 0, weight)
                }
            }
            for exerciseID in heaviest.keys.sorted() {
                let weight = heaviest[exerciseID] ?? 0
                guard let previous = best[exerciseID] else {
                    best[exerciseID] = weight
                    continue
                }
                if weight > previous {
                    best[exerciseID] = weight
                    events.append(
                        RecordEvent(
                            sessionID: session.id,
                            exerciseID: exerciseID,
                            date: session.startedAt,
                            weightKg: weight,
                            previousKg: previous
                        )
                    )
                }
            }
        }

        return events.sorted { $0.date > $1.date }
    }

    /// Un record per esercizio: il più recente.
    ///
    /// È la forma con cui i record si mostrano all'utente. Chi progredisce ogni
    /// settimana batte il proprio carico di continuo: elencare ogni singolo
    /// primato riempirebbe la pagina di righe uguali, e il conteggio grezzo
    /// ("63 record") non direbbe niente. Contano gli **esercizi migliorati**.
    static func latestPerExercise(_ events: [RecordEvent]) -> [RecordEvent] {
        var seen: Set<String> = []
        return events.filter { seen.insert($0.exerciseID).inserted }
    }

    /// Esercizi che hanno battuto un record in una certa sessione, con il carico.
    static func records(inSession sessionID: UUID, events: [RecordEvent]) -> [String: Double] {
        var result: [String: Double] = [:]
        for event in events where event.sessionID == sessionID {
            result[event.exerciseID] = event.weightKg
        }
        return result
    }
}
