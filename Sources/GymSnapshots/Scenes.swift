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
    // Prima serie completata della prima sessione: la scena "correggi serie" di Progressi.
    let correctionEntry = full.store.session(id: sessionID)?.entries.first { $0.sets.contains(where: \.isCompleted) }
    let correctionEntryID = correctionEntry?.id ?? UUID()
    let correctionSetID = correctionEntry?.sets.first(where: \.isCompleted)?.id ?? UUID()

    // Sessione: quattro momenti costruiti al secondo (vedi MockData+Session.swift).
    let library = full.store.exercises
    let sessionStart = SessionMock.environment(
        repository: library, dayIndex: 0, completedEntries: 0, partialSets: 0,
        lastSetSecondsAgo: 0, elapsedMinutes: 1
    )
    let sessionMid = SessionMock.environment(
        repository: library, dayIndex: 0, completedEntries: 2, partialSets: 2,
        lastSetSecondsAgo: 44
    )
    let sessionSuperset = SessionMock.environment(
        repository: library, dayIndex: 0, completedEntries: 3, partialSets: 0,
        lastSetSecondsAgo: 900, elapsedMinutes: 46
    )
    // Giorno Pull: il secondo esercizio è a corpo libero (trazioni), dove la
    // progressione proposta è a ripetizioni e non a carico.
    let sessionBodyweight = SessionMock.environment(
        repository: library, dayIndex: 1, completedEntries: 1, partialSets: 0,
        lastSetSecondsAgo: 900, elapsedMinutes: 22
    )
    let sessionDuration = SessionMock.environment(
        repository: library, dayIndex: 2, completedEntries: 5, partialSets: 0,
        lastSetSecondsAgo: 900, elapsedMinutes: 52
    )
    let pendingSet = SessionMock.firstPendingSet(in: sessionMid)

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

        // Avvio fallito: lo stato di errore ha sempre la sua azione "Riprova".
        SnapshotScene("root-avvio-errore", height: deviceHeight,
                      view: RootView(environment: AppEnvironment(
                          store: empty.store,
                          phase: .failed(AppEnvironment.libraryFailureMessage)
                      ))),

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
        SnapshotScene("oggi-scuro", dark: true, view: screen(TodayScreen(), in: full)),
        SnapshotScene("oggi-riposo", settle: 5, view: TodayVariantScene(variant: .rest)),
        SnapshotScene("oggi-completato", settle: 5, view: TodayVariantScene(variant: .completed)),
        SnapshotScene("oggi-in-scadenza", settle: 5, view: TodayVariantScene(variant: .expiring)),
        // Esercizi: catalogo, ricerca in italiano, filtri, dettaglio, picker, personalizzati.
        SnapshotScene("esercizi", settle: 6, view: ExercisesVariantScene(variant: .catalog)),
        SnapshotScene("esercizi-scuro", dark: true, settle: 6, view: ExercisesVariantScene(variant: .catalog)),
        SnapshotScene("esercizi-ricerca", settle: 5, view: screen(
            ExercisesScreen(preset: ExerciseSearchModel(query: "panca piana")),
            in: full
        )),
        SnapshotScene("esercizi-filtri", settle: 3, view: ExercisesVariantScene(variant: .filters)),
        SnapshotScene("esercizi-nessun-risultato", settle: 3, view: screen(
            ExercisesScreen(preset: ExerciseSearchModel(query: "panca romana")),
            in: full
        )),
        SnapshotScene("esercizi-dettaglio", settle: 6, view: screen(ExerciseDetailScreen(exerciseID: "0227"), in: full)),
        SnapshotScene("esercizi-dettaglio-progressi", settle: 6, view: screen(
            ExerciseDetailScreen(exerciseID: exerciseID),
            in: full
        )),
        SnapshotScene("esercizi-personalizzato", settle: 3, view: ExercisesVariantScene(variant: .customForm)),
        SnapshotScene("esercizi-personalizzato-dettaglio", settle: 5, view: ExercisesVariantScene(variant: .customDetail)),
        SnapshotScene("esercizi-picker", settle: 6, view: screen(
            ExercisePickerSheet(title: "Aggiungi esercizi", allowsMultipleSelection: true, excludedIDs: ["0025", "0047"], onPick: { _ in }),
            in: full
        )),
        SnapshotScene("scheda", view: screen(ProgramScreen(), in: full)),
        SnapshotScene("scheda-vuota", view: screen(ProgramScreen(), in: empty)),
        SnapshotScene("scheda-scuro", dark: true, view: screen(ProgramScreen(), in: full)),
        SnapshotScene("scheda-giorno", height: deviceHeight, settle: 2.5,
                      view: ProgramVariantScene(variant: .day)),
        SnapshotScene("scheda-editor-esercizio", height: deviceHeight, settle: 2.5,
                      view: ProgramVariantScene(variant: .item)),
        SnapshotScene("scheda-nuova", height: deviceHeight, settle: 2.5,
                      view: ProgramVariantScene(variant: .create)),
        SnapshotScene("scheda-archivio", height: deviceHeight, settle: 2.5,
                      view: ProgramVariantScene(variant: .archive)),
        SnapshotScene("scheda-giorni-fissi", height: deviceHeight, settle: 2.5,
                      view: ProgramVariantScene(variant: .weekdays)),
        SnapshotScene("progressi", view: screen(ProgressScreen(), in: full)),
        SnapshotScene("progressi-vuoto", view: screen(ProgressScreen(), in: empty)),
        SnapshotScene("progressi-scuro", dark: true, view: screen(ProgressScreen(), in: full)),
        SnapshotScene("progressi-sessione", view: screen(SessionDetailScreen(sessionID: sessionID), in: full)),
        SnapshotScene("progressi-dettaglio-peso", view: screen(BodyMetricDetailScreen(metric: .weight), in: full)),
        SnapshotScene("progressi-dettaglio-volume", view: screen(TrainingMetricDetailScreen(metric: .volume), in: full)),
        SnapshotScene("progressi-misure", view: screen(BodyMeasuresScreen(), in: full)),
        SnapshotScene("progressi-nuova-rilevazione", view: screen(BodyEntrySheet(entry: nil, defaultDate: full.now), in: full)),
        SnapshotScene("progressi-correggi-serie", view: screen(
            SetCorrectionSheet(sessionID: sessionID, entryID: correctionEntryID, setID: correctionSetID),
            in: full
        )),
        SnapshotScene("progressi-storico", view: screen(WorkoutHistoryScreen(), in: full)),
        SnapshotScene("progressi-record", view: screen(RecordsScreen(), in: full)),
        // Sessione attiva: altezza reale da iPhone e versione alta per la pagina intera.
        SnapshotScene("sessione-attiva", height: deviceHeight, settle: 2.5,
                      view: screen(ActiveSessionScreen(onMinimize: {}), in: sessionMid)),
        SnapshotScene("sessione-attiva-alta", height: 1700, settle: 2.5,
                      view: screen(ActiveSessionScreen(onMinimize: {}), in: sessionMid)),
        SnapshotScene("sessione-inizio", height: deviceHeight, settle: 2.5,
                      view: screen(ActiveSessionScreen(onMinimize: {}), in: sessionStart)),
        SnapshotScene("sessione-inizio-alta", height: 1700, settle: 2.5,
                      view: screen(ActiveSessionScreen(onMinimize: {}), in: sessionStart)),
        SnapshotScene("sessione-superset", height: deviceHeight, settle: 2.5,
                      view: screen(ActiveSessionScreen(onMinimize: {}), in: sessionSuperset)),
        SnapshotScene("sessione-durata", height: deviceHeight, settle: 2.5,
                      view: screen(ActiveSessionScreen(onMinimize: {}), in: sessionDuration)),
        SnapshotScene("sessione-corpo-libero", height: deviceHeight, settle: 2.5,
                      view: screen(ActiveSessionScreen(onMinimize: {}), in: sessionBodyweight)),
        SnapshotScene("sessione-menu", height: deviceHeight,
                      view: screen(
                        SetOptionsSheet(
                            entryID: pendingSet?.entryID ?? UUID(),
                            setID: pendingSet?.setID ?? UUID()
                        ),
                        in: sessionMid
                      )),
        SnapshotScene("sessione-riepilogo", height: deviceHeight,
                      view: screen(SessionSummaryScreen(sessionID: sessionID), in: full)),
        SnapshotScene("sessione-riepilogo-alta", height: 1400,
                      view: screen(SessionSummaryScreen(sessionID: sessionID), in: full)),
        SnapshotScene("impostazioni", view: screen(SettingsScreen(), in: full)),
        SnapshotScene("impostazioni-vuoto", view: screen(SettingsScreen(), in: empty)),

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
