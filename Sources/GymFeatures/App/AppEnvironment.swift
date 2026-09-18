import Foundation
import Observation
import GymCore

// MARK: - Convenzione d'ambiente (VINCOLANTE per tutte le schermate di GymFeatures)
//
// `RootView` inietta **un solo oggetto** nell'ambiente SwiftUI: `AppEnvironment`.
//
//     .environment(appEnvironment)
//
// Ogni schermata legge quindi SEMPRE e SOLO:
//
//     @Environment(AppEnvironment.self) private var app
//
// e passa da lì per tutto il resto:
//
//     app.store        // AppStore: dati e mutazioni (è @Observable, l'osservazione funziona anche annidata)
//     app.exercises    // ExerciseRepository, nil finché la libreria non è pronta
//     app.exercise(id:)// scorciatoia per un singolo esercizio
//     app.now          // "adesso" secondo la sorgente di tempo dello store (fissa negli screenshot)
//     app.calendar     // calendario con settimana da lunedì
//     app.router       // navigazione condivisa fra i tab
//
// NON leggere `@Environment(AppStore.self)`: lo store non viene iniettato da solo e
// quella lettura andrebbe in crash a runtime. Una sola convenzione, nessuna eccezione.

/// Radice delle dipendenze dell'app: possiede lo ``AppStore`` e lo stato di
/// caricamento della libreria esercizi.
///
/// Si costruisce in due modi:
/// - ``makeDefault()`` per l'app reale (dati in `Application Support/GymApp/`);
/// - ``init(store:phase:)`` con dipendenze iniettate (store su directory temporanea,
///   repository già caricato, data "adesso" fissa) per gli screenshot di `GymSnapshots`.
@MainActor
@Observable
public final class AppEnvironment {

    /// Stato di caricamento della libreria esercizi (`exercises.json` dal bundle).
    public enum LibraryPhase: Sendable, Equatable {
        /// Caricamento in corso: la UI mostra la schermata di avvio.
        case loading
        /// Libreria pronta: si può mostrare la shell a tab.
        case ready
        /// Caricamento fallito, con il motivo da mostrare all'utente.
        case failed(String)

        public var isReady: Bool { self == .ready }
    }

    /// Dati e mutazioni. È `@Observable`: leggere `app.store.sessions` dentro una
    /// view la fa aggiornare come se lo store fosse iniettato direttamente.
    public let store: AppStore

    /// Navigazione condivisa (tab selezionato e path di ogni NavigationStack).
    public let router: Router

    /// Fase di caricamento della libreria esercizi.
    public private(set) var phase: LibraryPhase

    /// - Parameters:
    ///   - store: store già costruito (directory iniettabile, data "adesso" iniettabile).
    ///   - phase: passare `.ready` quando lo store è già popolato e non serve chiamare ``start()``.
    ///   - router: router condiviso; di norma quello di default.
    public init(store: AppStore, phase: LibraryPhase = .loading, router: Router = Router()) {
        self.store = store
        self.phase = phase
        self.router = router
    }

    /// Ambiente dell'app reale: dati in `Application Support/GymApp/`.
    public static func makeDefault() throws -> AppEnvironment {
        AppEnvironment(store: try AppStore.makeDefault())
    }

    // MARK: - Scorciatoie di lettura

    /// Libreria esercizi; `nil` finché ``phase`` non è `.ready`.
    public var exercises: ExerciseRepository? { store.exercises }

    /// Un esercizio per id del dataset, `nil` se la libreria non è pronta o l'id non esiste.
    public func exercise(id: String) -> Exercise? { store.exercises?.exercise(id: id) }

    /// Istante corrente secondo la sorgente di tempo dello store (fissa negli screenshot).
    public var now: Date { store.currentDate }

    /// Calendario con la settimana che inizia di lunedì.
    public var calendar: Calendar { store.calendar }

    /// Unità di misura scelta dall'utente, per i formattatori.
    public var unit: WeightUnit { store.settings.unit }

    // MARK: - Avvio

    /// Carica i dati da disco e la libreria esercizi, poi aggiorna ``phase``.
    ///
    /// Chiamarla più volte è innocuo: ``AppStore/load()`` è idempotente.
    public func start() async {
        await store.load()
        phase = Self.phase(for: store)
    }

    /// Riprova a caricare **solo** la libreria esercizi dopo un errore.
    ///
    /// È l'azione "Riprova" della schermata di avvio: i dati dell'utente sono già
    /// stati letti da ``start()``, qui si ritenta il pezzo che è andato storto
    /// (``AppStore/reloadExercises()``). Durante il tentativo la fase torna a
    /// `.loading`, così la schermata non resta con il messaggio di errore sotto le
    /// dita mentre il caricamento è in corso.
    public func retryLibrary() async {
        phase = .loading
        _ = await store.reloadExercises()
        phase = Self.phase(for: store)
    }

    /// Messaggio mostrato quando la libreria esercizi non si carica.
    ///
    /// Non riporta l'errore tecnico dello store: all'utente non dice niente e in
    /// caso di JSON malformato sarebbe un muro di testo. Quello che conta è che i
    /// dati personali non sono in pericolo e che si può ritentare.
    public static let libraryFailureMessage =
        "Gli esercizi non si sono caricati. I tuoi allenamenti e le tue schede sono al sicuro."

    /// Fase corrispondente allo stato corrente dello store.
    private static func phase(for store: AppStore) -> LibraryPhase {
        store.exercises == nil ? .failed(libraryFailureMessage) : .ready
    }
}
