import SwiftUI
import GymCore
import GymUI

/// Radice dell'interfaccia: avvio, shell a 4 tab, cover della sessione attiva.
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
    /// Tab selezionato all'avvio: serve agli screenshot, l'app parte sempre da Oggi.
    private let initialTab: AppTab
    /// Solo per gli screenshot: parte con la sessione in corso già minimizzata,
    /// così si vede la barra "Riprendi allenamento" invece della cover.
    private let sessionMinimized: Bool

    @State private var environment: AppEnvironment?
    @State private var bootFailure: String?

    /// Avvio reale: crea l'ambiente di default e carica i dati.
    public init() {
        self.provided = nil
        self.initialTab = .today
        self.sessionMinimized = false
    }

    /// Avvio con dipendenze iniettate (usato da `GymSnapshots`).
    public init(environment: AppEnvironment, initialTab: AppTab = .today, sessionMinimized: Bool = false) {
        self.provided = environment
        self.initialTab = initialTab
        self.sessionMinimized = sessionMinimized
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
            if sessionMinimized { provided.router.minimizeSession() }
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

/// Shell a tab: quattro `NavigationStack`, tab bar flottante, barra "Riprendi
/// allenamento" e cover a schermo intero della sessione in corso.
private struct AppShell: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = app.router

        ZStack {
            PageBackground()

            // I quattro stack restano tutti nella gerarchia: così il tab conserva
            // il proprio stato (path, ricerca, scroll) quando si cambia tab.
            tabStack(.today, path: $router.todayPath) { TodayScreen() }
            tabStack(.exercises, path: $router.exercisesPath) { ExercisesScreen() }
            tabStack(.program, path: $router.programPath) { ProgramScreen() }
            tabStack(.progress, path: $router.progressPath) { ProgressScreen() }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sessionCover(isPresented: sessionCoverBinding) {
            ActiveSessionScreen(onMinimize: { app.router.minimizeSession() })
        }
        .onChange(of: app.store.activeSession?.id) { _, _ in
            // Una sessione appena avviata (o chiusa) riparte sempre non minimizzata.
            app.router.resumeSession()
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
                    switch route {
                    case .exercise(let id): ExerciseDetailScreen(exerciseID: id)
                    case .session(let id): SessionDetailScreen(sessionID: id)
                    }
                }
        }
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
        .zIndex(isSelected ? 1 : 0)
    }

    // MARK: - Barre in basso

    private var bottomBar: some View {
        @Bindable var router = app.router

        return VStack(spacing: Theme.Spacing.s) {
            if app.store.activeSession != nil, app.router.isSessionMinimized {
                resumeBar
            }
            FloatingTabBar(items: AppTab.tabItems, selection: $router.tab)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.bottom, Theme.Spacing.s)
    }

    private var resumeBar: some View {
        Button {
            app.router.resumeSession()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Text("Riprendi allenamento")
                    .font(.bodyEmphasis)
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(Theme.ink, in: Capsule(style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Riprendi allenamento"))
    }

    // MARK: - Cover della sessione

    /// La cover è aperta quando c'è una sessione in corso e non è stata minimizzata.
    /// Chiuderla non termina la sessione: la minimizza e fa comparire la barra sopra la tab bar.
    private var sessionCoverBinding: Binding<Bool> {
        Binding(
            get: { app.store.activeSession != nil && !app.router.isSessionMinimized },
            set: { isOpen in if !isOpen { app.router.minimizeSession() } }
        )
    }
}

private extension View {

    /// Cover a schermo intero della sessione.
    ///
    /// `fullScreenCover` esiste solo su iOS: su macOS (dove si compila e si fanno
    /// gli screenshot) ricade su `sheet`, che ha la stessa semantica di binding.
    @ViewBuilder
    func sessionCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}
