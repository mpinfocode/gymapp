import Foundation
import Observation
import GymCore

/// Tutte le pagine che si aprono **spingendo** dentro un tab.
///
/// Ogni tab installa `.navigationDestination(for: AppRoute.self)` (lo fa già
/// ``RootView``), quindi per navigare basta:
///
///     NavigationLink(value: AppRoute.exercise(id: exercise.id)) { ... }
///
/// oppure, da codice e anche da un altro tab, `app.router.openExercise(id:)`.
///
/// Perché *tutte* le pagine spinte passano di qui, anche quelle usate da una sola
/// feature: la shell deve poter riportare un tab alla sua radice quando se ne
/// ritocca l'icona. Un path per tab è l'unica fonte di verità che non può andare
/// fuori sincrono. La navigazione *modale* di una feature (sheet, editor, picker)
/// resta invece locale alla schermata che la apre.
public enum AppRoute: Hashable, Sendable {
    /// Dettaglio di un esercizio della libreria.
    case exercise(id: String)
    /// Editor di un giorno della scheda.
    case programDay(programID: UUID, dayID: UUID)
    /// Archivio delle schede.
    case programArchive
    /// Dettaglio di una metrica corporea (grafico grande e valori).
    case bodyMetric(BodyMetricKind)
    /// Elenco degli esercizi di una sezione (zona colpita, preferiti, i propri).
    ///
    /// È una pagina spinta come le altre, non una `navigationDestination(item:)`
    /// locale: solo così ``Router/popToRoot(_:)`` (e quindi il ritocco del tab) la
    /// chiude davvero invece di lasciarla aperta sopra una radice già svuotata.
    case exerciseGroup(ExerciseSection)
    /// Dettaglio di un esercizio aperto da una riga della scheda: in testa la
    /// prescrizione ("La tua scheda") con il carico ritoccabile.
    case planItem(programID: UUID, dayID: UUID, itemID: UUID)
}

/// Navigazione condivisa: tab selezionato, path di ogni `NavigationStack`,
/// presentazione delle Impostazioni e "ritocco del tab".
@MainActor
@Observable
public final class Router {

    /// Tab attualmente selezionato. L'app parte dalla **Home**.
    public var tab: AppTab = .home

    /// Le Impostazioni sono presentate come sheet dalla shell (``RootView``),
    /// non da una singola schermata: così qualunque tab può aprirle con
    /// ``presentSettings()`` senza duplicare il foglio.
    public var isPresentingSettings = false

    /// Contatore di fluidità in alto a destra (Impostazioni → Diagnostica).
    ///
    /// Stato di **sessione**: non viene salvato, così si spegne da sé a ogni avvio e
    /// non resta mai acceso per sbaglio. Spento non costa nulla: la shell non crea
    /// nemmeno la view che misura.
    public var showsFrameRate = false

    public var homePath: [AppRoute] = []
    public var programPath: [AppRoute] = []
    public var exercisesPath: [AppRoute] = []
    public var measuresPath: [AppRoute] = []

    /// Token "scorri in cima" per tab: cresce a ogni ritocco dell'icona di un tab
    /// già selezionato e già alla radice (vedi ``reselect(_:)``).
    private var scrollToTopTokens: [AppTab: Int] = [:]

    public init() {}

    // MARK: - Profondità di navigazione

    /// Path del tab indicato.
    public func path(for tab: AppTab) -> [AppRoute] {
        switch tab {
        case .home: homePath
        case .program: programPath
        case .exercises: exercisesPath
        case .measures: measuresPath
        }
    }

    /// `true` quando il tab selezionato mostra la sua radice.
    ///
    /// Non serve più a nascondere la tab bar (che ora è sempre visibile): resta
    /// come informazione utile a chi deve sapere se è in profondità.
    public var isAtRoot: Bool { path(for: tab).isEmpty }

    /// Spinge una pagina dentro il tab selezionato.
    public func push(_ route: AppRoute) {
        switch tab {
        case .home: homePath.append(route)
        case .program: programPath.append(route)
        case .exercises: exercisesPath.append(route)
        case .measures: measuresPath.append(route)
        }
    }

    /// Svuota il path di un tab (pop animato fino alla radice).
    public func popToRoot(_ tab: AppTab) {
        switch tab {
        case .home: homePath = []
        case .program: programPath = []
        case .exercises: exercisesPath = []
        case .measures: measuresPath = []
        }
    }

    /// Riporta tutti i tab alla radice (usato dopo un import di backup).
    public func popToRoot() {
        for tab in AppTab.allCases { popToRoot(tab) }
    }

    // MARK: - Ritocco del tab

    /// Ritocco dell'icona di un tab **già selezionato**: se la sezione è in
    /// profondità torna alla sua radice, se è già alla radice chiede alla
    /// schermata di scorrere in cima incrementando ``scrollToTopToken(for:)``.
    ///
    /// La chiama la shell dal binding della tab bar; le schermate radice non
    /// devono fare altro che osservare il token.
    public func reselect(_ tab: AppTab) {
        if path(for: tab).isEmpty {
            scrollToTopTokens[tab, default: 0] += 1
        } else {
            popToRoot(tab)
        }
    }

    /// Token da osservare nella radice di un tab per scorrere in cima:
    ///
    ///     ScrollViewReader { proxy in
    ///         ScrollView { content.id(topID) }
    ///             .onChange(of: app.router.scrollToTopToken(for: .measures)) { _, _ in
    ///                 withAnimation { proxy.scrollTo(topID, anchor: .top) }
    ///             }
    ///     }
    public func scrollToTopToken(for tab: AppTab) -> Int {
        scrollToTopTokens[tab] ?? 0
    }

    // MARK: - Impostazioni

    /// Apre le Impostazioni da qualunque schermata (ingranaggio discreto nella testata).
    public func presentSettings() {
        isPresentingSettings = true
    }

    /// Chiude le Impostazioni.
    public func dismissSettings() {
        isPresentingSettings = false
    }

    // MARK: - Scorciatoie

    /// Apre il dettaglio di un esercizio nel tab Esercizi, da qualunque punto dell'app.
    public func openExercise(id: String) {
        tab = .exercises
        exercisesPath = [.exercise(id: id)]
    }
}
