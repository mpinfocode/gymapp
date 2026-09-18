#if os(macOS)
import Foundation
import SwiftUI
import GymCore
import GymUI
import GymFeatures

/// Altezza di un iPhone 15/16 Pro: le scene che mostrano la shell completa
/// (tab bar in basso) vanno rese così, non allungate.
private let deviceHeight: CGFloat = 852

/// Elenco dichiarativo di tutte le scene.
///
/// Aggiungere una schermata = aggiungere una riga qui. Il nome è anche la chiave
/// del filtro da riga di comando (`swift run GymSnapshots oggi`).
@MainActor
func makeScenes(full: AppEnvironment, empty: AppEnvironment, running: AppEnvironment) -> [SnapshotScene] {
    let sessionID = full.store.sessions.first?.id ?? UUID()
    let exerciseID = SampleProgram.exerciseIDs.first ?? "0025"

    return [
        // Shell completa: i quattro tab, stato pieno.
        SnapshotScene("root-oggi", height: deviceHeight, settle: 2.5,
                      view: RootView(environment: full, initialTab: .today)),
        SnapshotScene("root-esercizi", height: deviceHeight,
                      view: RootView(environment: full, initialTab: .exercises)),
        SnapshotScene("root-scheda", height: deviceHeight,
                      view: RootView(environment: full, initialTab: .program)),
        SnapshotScene("root-progressi", height: deviceHeight,
                      view: RootView(environment: full, initialTab: .progress)),
        SnapshotScene("root-oggi-scuro", height: deviceHeight, dark: true,
                      view: RootView(environment: full, initialTab: .today)),

        // Shell, primo avvio (nessuna scheda, nessuno storico).
        SnapshotScene("root-oggi-vuoto", height: deviceHeight,
                      view: RootView(environment: empty, initialTab: .today)),
        SnapshotScene("root-scheda-vuota", height: deviceHeight,
                      view: RootView(environment: empty, initialTab: .program)),
        SnapshotScene("root-progressi-vuoto", height: deviceHeight,
                      view: RootView(environment: empty, initialTab: .progress)),

        // Sessione in corso, cover chiusa: barra "Riprendi allenamento" sopra la tab bar.
        SnapshotScene("root-sessione-minimizzata", height: deviceHeight,
                      view: RootView(environment: running, initialTab: .today, sessionMinimized: true)),

        // Schermate singole, rese alte per vedere tutta la pagina.
        SnapshotScene("oggi", view: screen(TodayScreen(), in: full)),
        SnapshotScene("oggi-vuoto", view: screen(TodayScreen(), in: empty)),
        SnapshotScene("esercizi", view: screen(ExercisesScreen(), in: full)),
        SnapshotScene("esercizi-dettaglio", view: screen(ExerciseDetailScreen(exerciseID: exerciseID), in: full)),
        SnapshotScene("esercizi-picker", view: screen(
            ExercisePickerSheet(title: "Aggiungi esercizi", allowsMultipleSelection: true, excludedIDs: [], onPick: { _ in }),
            in: full
        )),
        SnapshotScene("scheda", view: screen(ProgramScreen(), in: full)),
        SnapshotScene("scheda-vuota", view: screen(ProgramScreen(), in: empty)),
        SnapshotScene("progressi", view: screen(ProgressScreen(), in: full)),
        SnapshotScene("progressi-vuoto", view: screen(ProgressScreen(), in: empty)),
        SnapshotScene("progressi-sessione", view: screen(SessionDetailScreen(sessionID: sessionID), in: full)),
        SnapshotScene("sessione-attiva", view: screen(ActiveSessionScreen(onMinimize: {}), in: running)),
        SnapshotScene("sessione-riepilogo", view: screen(SessionSummaryScreen(sessionID: sessionID), in: full)),
        SnapshotScene("impostazioni", view: screen(SettingsScreen(), in: full)),

        // Design system: resta la prima verifica visiva dei componenti.
        SnapshotScene("design-system", height: 4200, settle: 4, view: GymUIGallery()),
    ]
}

/// Monta una schermata come la monta l'app: sfondo di pagina, ambiente iniettato,
/// dentro un `NavigationStack` (molte schermate useranno barra e link).
@MainActor
private func screen<V: View>(_ view: V, in environment: AppEnvironment) -> some View {
    NavigationStack {
        view
    }
    .environment(environment)
}
#endif
