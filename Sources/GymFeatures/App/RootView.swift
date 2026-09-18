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
private struct AppShell: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = app.router

        ZStack {
            // I quattro stack restano tutti nella gerarchia: così il tab conserva
            // il proprio stato (path, ricerca, posizione di scroll) quando si
            // cambia tab. Smontarli sarebbe più economico ma SwiftUI non sa
            // ripristinare l'offset di scroll di una gerarchia distrutta: si
            // tornerebbe in cima a ogni giro di tab. Il lavoro inutile dei tab
            // nascosti si elimina invece mettendoli in pausa (vedi `tabStack`).
            tabStack(.home, path: $router.homePath) { HomeScreen() }
            tabStack(.program, path: $router.programPath) { ProgramScreen() }
            tabStack(.exercises, path: $router.exercisesPath) { ExercisesScreen() }
            tabStack(.measures, path: $router.measuresPath) { MeasuresScreen() }
        }
        // Lo sfondo sta dietro, non dentro lo stack: un figlio con
        // `ignoresSafeArea` in uno ZStack può far crescere il contenitore e
        // spingere il contenuto sotto la safe area.
        .background(PageBackground())
        // La barra è disegnata SOPRA gli stack, non come loro inset: lo spazio se
        // lo prende ogni stack con `tabBarSafeArea()`, che vale anche per le
        // pagine spinte (vedi il commento del modificatore).
        .overlay(alignment: .bottom) { tabBar }
        // Le Impostazioni sono un foglio della shell: qualunque schermata le apre
        // con `app.router.presentSettings()`.
        .sheet(isPresented: $router.isPresentingSettings) {
            SettingsScreen()
                .environment(app)
        }
        .onChange(of: app.store.settings.hapticsEnabled, initial: true) { _, enabled in
            Haptics.isEnabled = enabled
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            let store = app.store
            Task { await store.flush() }
        }
    }

    // MARK: - Tab

    @ViewBuilder
    private func tabStack<Content: View>(
        _ tab: AppTab,
        path: Binding<[AppRoute]>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = app.router.tab == tab
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }
        // Lo spazio della tab bar si riserva QUI, fuori dal `NavigationStack`: la
        // safe area ridotta vale così anche per le pagine spinte e per i loro
        // `safeAreaInset(edge: .bottom)`, che finiscono sopra la barra invece che
        // sotto. Applicarlo dentro le singole schermate lo farebbe dimenticare
        // proprio alla prima pagina spinta con un bottone ancorato in basso.
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
        .animation(nil, value: app.router.tab)
    }

    /// Le pagine spinte, tutte in un punto solo.
    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .exercise(let id): ExerciseDetailScreen(exerciseID: id)
        case .programDay(let programID, let dayID): ProgramDayEditor(programID: programID, dayID: dayID)
        case .programArchive: ProgramArchiveScreen()
        case .bodyMetric(let metric): BodyMetricDetailScreen(metric: metric)
        }
    }

    // MARK: - Tab bar

    /// Sempre visibile, anche nelle pagine spinte: è l'unico modo per ritoccare
    /// l'icona di un tab e tornare alla sua radice da qualunque profondità.
    private var tabBar: some View {
        FloatingTabBar(items: AppTab.tabItems, selection: tabSelection)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, FloatingTabBarMetrics.bottomMargin)
    }

    /// Il tab si cambia senza animare il contenuto (vedi `tabStack`).
    ///
    /// Il **ritocco** di un tab già selezionato passa da ``Router/reselect(_:)``:
    /// torna alla radice della sezione oppure, se è già alla radice, chiede alla
    /// schermata di scorrere in cima.
    private var tabSelection: Binding<AppTab> {
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
