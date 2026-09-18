import Foundation
import Observation

/// Le destinazioni raggiungibili da più tab.
///
/// Ogni tab installa `.navigationDestination(for: AppRoute.self)` (lo fa già
/// ``RootView``), quindi per navigare basta:
///
///     NavigationLink(value: AppRoute.exercise(id: exercise.id)) { ... }
///
/// oppure, da codice e anche da un altro tab, `app.router.openExercise(id:)`.
public enum AppRoute: Hashable, Sendable {
    /// Dettaglio di un esercizio della libreria.
    case exercise(id: String)
    /// Dettaglio di una sessione conclusa dello storico.
    case session(id: UUID)
}

/// Navigazione condivisa: tab selezionato e path di ogni `NavigationStack`.
///
/// Volutamente minimale: un path per tab, due destinazioni. Tutto il resto della
/// navigazione (sheet, editor, picker) resta locale alla schermata che lo apre.
@MainActor
@Observable
public final class Router {

    /// Tab attualmente selezionato.
    public var tab: AppTab = .today

    /// La cover della sessione è stata chiusa senza terminare l'allenamento:
    /// la shell mostra la barra "Riprendi allenamento" sopra la tab bar.
    ///
    /// Nessuna schermata deve presentare la sessione da sé: avviarla nello store
    /// basta, la cover la apre ``RootView``.
    public private(set) var isSessionMinimized = false

    public var todayPath: [AppRoute] = []
    public var exercisesPath: [AppRoute] = []
    public var programPath: [AppRoute] = []
    public var progressPath: [AppRoute] = []

    public init() {}

    /// Riporta a schermo intero la sessione in corso (bottone "Riprendi").
    public func resumeSession() {
        isSessionMinimized = false
    }

    /// Chiude la cover senza terminare l'allenamento.
    public func minimizeSession() {
        isSessionMinimized = true
    }

    /// Apre il dettaglio di un esercizio nel tab Esercizi, da qualunque punto dell'app.
    public func openExercise(id: String) {
        tab = .exercises
        exercisesPath = [.exercise(id: id)]
    }

    /// Apre il dettaglio di una sessione conclusa nel tab Progressi.
    public func openSession(id: UUID) {
        tab = .progress
        progressPath = [.session(id: id)]
    }

    /// Riporta tutti i tab alla radice (usato dopo un import di backup).
    public func popToRoot() {
        todayPath = []
        exercisesPath = []
        programPath = []
        progressPath = []
    }
}
