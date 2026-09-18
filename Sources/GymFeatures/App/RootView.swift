import SwiftUI
import GymCore
import GymUI

/// Radice dell'interfaccia: avvio e shell a 4 tab
/// (**Home · Scheda · Esercizi · Misure**, SPEC §0).
///
/// Convenzione d'ambiente: vedi il commento in testa a `App/AppEnvironment.swift`.
/// `RootView` costruisce (o riceve) l'``AppEnvironment`` e lo inietta con
/// `.environment(...)`; da lì in giù ogni schermata legge solo
/// `@Environment(AppEnvironment.self)`.
///
/// Nessun `#Preview`: il plugin macro non è disponibile sul toolchain locale (SPEC §1.2).
/// Per la revisione visiva si usa `swift run GymSnapshots`.
public struct RootView: View {

    /// Ambiente iniettato (screenshot/test); `nil` nell'app reale.
    private let provided: AppEnvironment?
    /// Tab selezionato all'avvio: serve agli screenshot, l'app parte sempre da Home.
    private let initialTab: AppTab

    @State private var environment: AppEnvironment?
    @State private var bootFailure: String?

    /// Avvio reale: crea l'ambiente di default e carica i dati.
    public init() {
        self.provided = nil
        self.initialTab = .home
    }

    /// Avvio con dipendenze iniettate (usato da `GymSnapshots`).
    public init(environment: AppEnvironment, initialTab: AppTab = .home) {
        self.provided = environment
        self.initialTab = initialTab
    }

    public var body: some View {
        Group {
            if let environment {
                switch environment.phase {
                case .ready:
                    AppShell()
                        .environment(environment)
                case .loading:
                    LaunchView()
                case .failed(let reason):
                    LaunchView(title: "Libreria non disponibile", message: reason) {
                        await environment.retryLibrary()
                    }
                }
            } else if let bootFailure {
                LaunchView(title: "Dati non leggibili", message: bootFailure) {
                    await retryBootstrap()
                }
            } else {
                LaunchView()
            }
        }
        .task { await bootstrap() }
    }

    /// Azione "Riprova" quando è fallita la creazione dell'ambiente: si ricomincia
    /// da capo, togliendo prima il messaggio precedente.
    private func retryBootstrap() async {
        bootFailure = nil
        await bootstrap()
    }

    private func bootstrap() async {
        guard environment == nil else { return }
        if let provided {
            if provided.phase == .loading { await provided.start() }
            environment = provided
            provided.router.tab = initialTab
            return
        }
        do {
            let created = try AppEnvironment.makeDefault()
            created.router.tab = initialTab
            await created.start()
            environment = created
        } catch {
            bootFailure = "Impossibile accedere ai dati salvati."
        }
    }
}

/// Schermata di avvio: solo il nome dell'app su sfondo bianco puro.
///
/// Se il caricamento fallisce non resta un vicolo cieco: il motivo compare in uno
/// stato vuoto con la sua azione "Riprova" (regola di DESIGN: uno stato vuoto ha
/// sempre un'azione). Il tentativo in corso disabilita il bottone invece di
/// sostituire tutto con uno spinner, così il testo non salta sotto le dita.
private struct LaunchView: View {

    var title: String = ""
    var message: String?
    /// Azione "Riprova"; `nil` durante il caricamento normale.
    var retry: (@Sendable () async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        ZStack {
            PageBackground()

            VStack(spacing: Theme.Spacing.xl) {
                Text("GymApp")
                    .font(.greeting)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let message {
                    EmptyStateView(
                        systemImage: "exclamationmark.circle",
                        title: title,
                        message: message,
                        actionTitle: retry == nil ? nil : (isRetrying ? "Caricamento" : "Riprova"),
                        action: retry == nil ? nil : { startRetry() }
                    )
                    .disabled(isRetrying)
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
        }
    }

    private func startRetry() {
        guard let retry, !isRetrying else { return }
        isRetrying = true
        Task {
            await retry()
            isRetrying = false
        }
    }
}

/// Shell a tab: quattro `NavigationStack`, tab bar flottante **sempre visibile** e
/// foglio delle Impostazioni.
///
/// ## Regola di invalidazione (la ragione per cui questo file è fatto così)
///
/// `AppShell.body` non legge **niente** di osservabile. Ogni dipendenza sta nella
/// view più piccola che può averla:
///
/// - il tab selezionato lo leggono ``TabSlot`` (uno per tab) e ``ShellTabBar``;
/// - il path di ogni tab lo legge il suo `NavigationStack`, tramite un binding che
///   non viene mai *letto* qui;
/// - la presentazione delle Impostazioni e la sincronizzazione delle vibrazioni
///   stanno in ``ShellSideEffects``, una view invisibile;
/// - il contatore di fluidità sta in ``ShellFrameRate``.
///
/// Prima bastava cambiare tab per rivalutare il body della shell **e** quello dei
/// quattro tab: su iPhone si vedeva, ed era il costo più alto dell'app.
private struct AppShell: View {

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var router = app.router

        ZStack {
            // I quattro stack restano tutti nella gerarchia: così il tab conserva
            // il proprio stato (path, ricerca, posizione di scroll) quando si
            // cambia tab. Smontarli sarebbe più economico ma SwiftUI non sa
            // ripristinare l'offset di scroll di una gerarchia distrutta: si
            // tornerebbe in cima a ogni giro di tab. Il lavoro inutile dei tab
            // nascosti si elimina invece mettendoli in pausa (vedi `TabSlot`).
            TabSlot(tab: .home) {
                NavigationStack(path: $router.homePath) { tabRoot { HomeScreen() } }
            }
            TabSlot(tab: .program) {
                NavigationStack(path: $router.programPath) { tabRoot { ProgramScreen() } }
            }
            TabSlot(tab: .exercises) {
                NavigationStack(path: $router.exercisesPath) { tabRoot { ExercisesScreen() } }
            }
            TabSlot(tab: .measures) {
                NavigationStack(path: $router.measuresPath) { tabRoot { MeasuresScreen() } }
            }
        }
        // Lo sfondo sta dietro, non dentro lo stack: un figlio con
        // `ignoresSafeArea` in uno ZStack può far crescere il contenitore e
        // spingere il contenuto sotto la safe area.
        .background(PageBackground())
        // La barra è disegnata SOPRA gli stack, non come loro inset: lo spazio se
        // lo prende ogni stack con `tabBarSafeArea()`, che vale anche per le
        // pagine spinte (vedi il commento del modificatore).
        .overlay(alignment: .bottom) { ShellTabBar() }
        // Foglio delle Impostazioni e sincronizzazioni: fuori dal body della shell,
        // così accenderle non ridisegna i quattro tab.
        .background { ShellSideEffects() }
        .overlay { ShellFrameRate() }
    }

    /// Radice di un tab: il contenuto più le destinazioni, installate una volta sola.
    @ViewBuilder
    private func tabRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .navigationDestination(for: AppRoute.self) { route in
                AppShell.destination(route)
            }
    }

    /// Le pagine spinte, tutte in un punto solo.
    @ViewBuilder
    static func destination(_ route: AppRoute) -> some View {
        switch route {
        case .exercise(let id):
            ExerciseDetailScreen(exerciseID: id)
        case .programDay(let programID, let dayID):
            ProgramDayEditor(programID: programID, dayID: dayID)
        case .programArchive:
            ProgramArchiveScreen()
        case .bodyMetric(let metric):
            BodyMetricDetailScreen(metric: metric)
        case .exerciseGroup(let section):
            ExerciseGroupScreen(section: section)
        case .planItem(let programID, let dayID, let itemID):
            PlanItemDetailScreen(
                context: PlanItemContext(programID: programID, dayID: dayID, itemID: itemID)
            )
        }
    }
}

/// Un tab dentro la shell: è **questa** view, e non la shell, a leggere
/// `router.tab`.
///
/// Il contenuto arriva già costruito dal padre: quando il tab cambia si rivaluta
/// solo questo body (tre modificatori e un confronto), mentre il sottoalbero del
/// tab resta identico e SwiftUI non lo tocca.
private struct TabSlot<Content: View>: View {

    @Environment(AppEnvironment.self) private var app

    let tab: AppTab
    @ViewBuilder let content: Content

    var body: some View {
        let isSelected = app.router.tab == tab
        content
            // Lo spazio della tab bar si riserva QUI, fuori dal `NavigationStack`:
            // la safe area ridotta vale così anche per le pagine spinte e per i
            // loro `safeAreaInset(edge: .bottom)`, che finiscono sopra la barra
            // invece che sotto. Applicarlo dentro le singole schermate lo farebbe
            // dimenticare proprio alla prima pagina spinta con un bottone in basso.
            .tabBarSafeArea()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
            // Un tab nascosto resta montato ma non deve lavorare: gradienti e GIF
            // si fermano finché non torna visibile.
            .blobAnimationPaused(!isSelected)
            // Il cambio di tab è **istantaneo**: nessuna dissolvenza fra due
            // schermate intere. La pillola della tab bar si sposta comunque con la
            // sua animazione breve, perché è fuori da questo sottoalbero.
            .animation(nil, value: isSelected)
    }
}

/// La tab bar flottante: sempre visibile, anche nelle pagine spinte, perché è
/// l'unico modo per ritoccare l'icona di un tab da qualunque profondità.
///
/// Legge `router.tab` per conto suo: cambiare tab anima la pillola qui dentro e
/// non tocca il resto della shell.
private struct ShellTabBar: View {

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        FloatingTabBar(items: AppTab.tabItems, selection: selection)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, FloatingTabBarMetrics.bottomMargin)
    }

    /// Il **ritocco** di un tab già selezionato passa da ``Router/reselect(_:)``:
    /// torna alla radice della sezione oppure, se è già alla radice, chiede alla
    /// schermata di scorrere in cima.
    private var selection: Binding<AppTab> {
        Binding(
            get: { app.router.tab },
            set: { newValue in
                guard newValue != app.router.tab else {
                    app.router.reselect(newValue)
                    return
                }
                app.router.tab = newValue
            }
        )
    }
}

/// Foglio delle Impostazioni e sincronizzazioni della shell, in una view che non
/// disegna niente.
///
/// Sta qui e non su `AppShell` perché `onChange(of:)` **legge** il valore dentro il
/// body: `app.store.hapticsEnabled` sulla shell avrebbe invalidato i quattro tab a
/// ogni cambio di preferenza (e con `store.settings`, la vecchia lettura larga,
/// perfino aprendo un esercizio, che scrive i recenti).
private struct ShellSideEffects: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = app.router

        Color.clear
            .accessibilityHidden(true)
            .sheet(isPresented: $router.isPresentingSettings) {
                SettingsScreen()
                    .environment(app)
            }
            .onChange(of: app.store.hapticsEnabled, initial: true) { _, enabled in
                Haptics.isEnabled = enabled
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                let store = app.store
                Task { await store.flush() }
            }
    }
}

/// Contatore di fluidità (Impostazioni → Diagnostica).
///
/// Spento non esiste: nessun `CADisplayLink`, nessun timer, nessun ridisegno. È
/// una view a sé perché l'interruttore non deve invalidare la shell.
private struct ShellFrameRate: View {

    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .frameRateOverlay(app.router.showsFrameRate)
    }
}

private extension View {

    /// Riserva in fondo lo spazio della tab bar flottante.
    ///
    /// Va applicato **fuori** dal `NavigationStack` di un tab: la safe area ridotta
    /// si propaga così a tutte le pagine spinte, ai loro `safeAreaInset` e alle
    /// liste. Applicarlo una seconda volta dentro una pagina raddoppierebbe lo
    /// spazio: se serve altrove, si usa questo stesso modificatore e mai un
    /// `padding` a mano.
    func tabBarSafeArea() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: FloatingTabBarMetrics.reservedHeight)
        }
    }
}
