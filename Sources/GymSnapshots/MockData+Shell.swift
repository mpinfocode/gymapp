#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymFeatures
import GymUI

/// Misure di un iPhone 17 (852 punti): sono le stesse che la cornice di
/// ``GymPreview`` passa in modalità "Safe area rigida".
///
/// Le scene `root-*` le passano alla shell con
/// ``EnvironmentValues/deviceInsetsOverride``: senza, su macOS la finestra non ha
/// safe area e la fascia della barra di stato non si vedrebbe, cioè lo screenshot
/// direbbe una cosa diversa dal telefono. **È il motivo per cui il difetto era già
/// stato "corretto" due volte:** l'anteprima non riproduceva il caso reale.
enum ShellFrameMetrics {
    static let topInset: CGFloat = 59
    static let bottomInset: CGFloat = 34
}

extension View {

    /// Monta la shell come sul telefono: misure dei bordi passate a mano, nessuna
    /// safe area di sistema (su macOS non c'è).
    func deviceShellFrame() -> some View {
        environment(
            \.deviceInsetsOverride,
            DeviceInsets(top: ShellFrameMetrics.topInset, bottom: ShellFrameMetrics.bottomInset)
        )
    }
}

/// Una radice dentro la shell, resa all'altezza reale di un iPhone.
///
/// `scrolledToBottom` fotografa la pagina **scrollata fino in fondo**: è l'unico
/// modo per vedere se l'ultima riga finisce sotto la fascia della tab bar.
struct RootShellScene: View {

    let environment: AppEnvironment
    let tab: AppTab
    var scrolledToBottom = false

    var body: some View {
        RootView(environment: environment, initialTab: tab)
            .deviceShellFrame()
            .defaultScrollAnchor(scrolledToBottom ? .bottom : .top)
    }
}

/// Una pagina **spinta dentro la shell**, non renderizzata da sola.
///
/// Serve proprio a intercettare i difetti che si vedono solo con la tab bar
/// flottante in basso: un bottone primario ancorato al fondo, l'ultima riga di
/// una lista, l'altezza reale dell'iPhone. Le scene "scheda-giorno" e compagnia
/// rendono la pagina isolata e per questo non avevano mai mostrato il bug.
struct ShellScene: View {

    enum Variant {
        /// Giorno della scheda (sei esercizi) dentro il tab Scheda.
        case programDay
        /// Giorno con soli 3 esercizi: la lista è più corta dello schermo, il caso
        /// in cui sul telefono il bottone "Aggiungi esercizi" finiva sotto la
        /// capsula della tab bar.
        case programDayShort
        /// Giorno con 12 esercizi: lista più lunga dello schermo.
        case programDayLong
        /// Dettaglio di un esercizio dentro il tab Esercizi.
        case exerciseDetail
        /// Dettaglio del peso corporeo dentro il tab Misure.
        case bodyMetric
    }

    let variant: Variant
    /// Fotografa la pagina scrollata fino in fondo.
    var scrolledToBottom = false

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                RootView(environment: environment, initialTab: ShellMockData.tab(for: variant))
                    .deviceShellFrame()
                    .defaultScrollAnchor(scrolledToBottom ? .bottom : .top)
            }
        }
        .task {
            environment = await ShellMockData.environment(for: variant)
        }
    }
}

/// Home con un giorno da 12 esercizi, scrollata fino in fondo.
struct LongHomeShellScene: View {

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                RootShellScene(environment: environment, tab: .home, scrolledToBottom: true)
            }
        }
        .task { environment = await ShellMockData.longHomeEnvironment() }
    }
}

/// Elenco di una zona colpita (pagina spinta nel tab Esercizi) con la **fine
/// dell'elenco visibile**.
///
/// La zona è "Altro" (6 esercizi) di proposito: `ExerciseGroupList` è una `List`,
/// che carica le righe in un `task` e quindi ignora `defaultScrollAnchor(.bottom)`
/// (l'ancora si risolve prima che le righe esistano). Con una zona corta la fine
/// dell'elenco è comunque sullo schermo, ed è quella che si deve misurare:
/// l'ultima riga più il respiro di fine pagina devono stare sopra la fascia.
struct GroupShellScene: View {

    @State private var environment: AppEnvironment?

    var body: some View {
        ZStack {
            PageBackground()
            if let environment {
                RootShellScene(environment: environment, tab: .exercises)
            }
        }
        .task {
            let loaded = await MockData.fullEnvironment()
            loaded.router.exercisesPath = [.exerciseGroup(.group(.other))]
            environment = loaded
        }
    }
}

/// Le quattro radici in sequenza, tagliate subito sotto la testata: serve a
/// controllare a colpo d'occhio che titolo e azione stiano alla stessa altezza e
/// abbiano la stessa forma in tutte le pagine.
struct HeaderConsistencyScene: View {

    /// Altezza della striscia mostrata per ogni radice.
    private static let stripHeight: CGFloat = 230

    let environment: AppEnvironment

    @State private var environments: [AppEnvironment] = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, tab in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: Theme.Size.hairline)
                }
                strip(at: index, tab: tab)
            }
        }
        .task {
            var loaded: [AppEnvironment] = []
            for _ in Self.tabs {
                loaded.append(await MockData.fullEnvironment())
            }
            environments = loaded
        }
    }

    private static let tabs: [AppTab] = [.home, .program, .exercises, .measures]

    @ViewBuilder
    private func strip(at index: Int, tab: AppTab) -> some View {
        ZStack {
            PageBackground()
            if environments.indices.contains(index) {
                RootShellScene(environment: environments[index], tab: tab)
                    .frame(width: snapshotWidth, height: 852)
            }
        }
        .frame(width: snapshotWidth, height: Self.stripHeight, alignment: .top)
        .clipped()
    }
}

/// Ambienti delle scene "dentro la shell": il path del tab è già popolato, così
/// `RootView` parte con la pagina spinta già in cima.
enum ShellMockData {

    static func tab(for variant: ShellScene.Variant) -> AppTab {
        switch variant {
        case .programDay, .programDayShort, .programDayLong: .program
        case .exerciseDetail: .exercises
        case .bodyMetric: .measures
        }
    }

    @MainActor
    static func environment(for variant: ShellScene.Variant) async -> AppEnvironment {
        switch variant {
        case .programDay:
            let environment = await ProgramMockData.environment(for: .day)
            openFirstDay(of: environment)
            return environment

        case .programDayShort:
            let environment = await ProgramMockData.environment(for: .day)
            trimFirstDay(of: environment, to: 3)
            openFirstDay(of: environment)
            return environment

        case .programDayLong:
            let environment = await ProgramMockData.environment(for: .day)
            growFirstDay(of: environment, to: 12)
            openFirstDay(of: environment)
            return environment

        case .exerciseDetail:
            let environment = await MockData.fullEnvironment()
            environment.router.exercisesPath = [.exercise(id: "0227")]
            return environment

        case .bodyMetric:
            let environment = await MockData.fullEnvironment()
            environment.router.measuresPath = [.bodyMetric(.weight)]
            return environment
        }
    }

    // MARK: - Giorni su misura

    /// Un giorno della Home con più di dieci esercizi: la radice deve restare
    /// scorribile fino all'ultima riga, sopra la fascia.
    @MainActor
    static func longHomeEnvironment() async -> AppEnvironment {
        let environment = await ProgramMockData.environment(for: .day)
        growFirstDay(of: environment, to: 12)
        return environment
    }

    @MainActor
    private static func openFirstDay(of environment: AppEnvironment) {
        guard let program = environment.store.activeProgram, let day = program.days.first else { return }
        environment.router.programPath = [.programDay(programID: program.id, dayID: day.id)]
    }

    @MainActor
    private static func trimFirstDay(of environment: AppEnvironment, to count: Int) {
        guard let program = environment.store.activeProgram, let day = program.days.first else { return }
        for item in day.items.dropFirst(count) {
            environment.store.removeItem(id: item.id, fromDay: day.id, inProgram: program.id)
        }
    }

    /// Allunga il primo giorno riusando gli esercizi già presenti nella scheda:
    /// niente id inventati, così le righe hanno nome e thumbnail veri.
    @MainActor
    private static func growFirstDay(of environment: AppEnvironment, to count: Int) {
        guard let program = environment.store.activeProgram, let day = program.days.first else { return }
        let pool = ["0025", "0027", "0405", "0334", "0201", "0464", "0043", "0085", "0585", "0605", "0652", "0861"]
        var index = day.items.count
        while (environment.store.activeProgram?.day(id: day.id)?.items.count ?? count) < count, index < pool.count * 2 {
            environment.store.addItem(
                exerciseID: pool[index % pool.count],
                toDay: day.id,
                inProgram: program.id,
                targetSets: 3,
                measure: .reps(min: 8, max: 12)
            )
            index += 1
        }
    }
}
#endif
