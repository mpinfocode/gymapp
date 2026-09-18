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
/// del filtro da riga di comando (`swift run GymSnapshots misure`).
@MainActor
func makeScenes(full: AppEnvironment, empty: AppEnvironment) -> [SnapshotScene] {
    return [
        // Shell completa: i quattro tab, stato pieno. Tutte le scene `root-*`
        // passano alla shell le misure di un iPhone 17 (barra di stato 59, home
        // indicator 34) SENZA safe area di sistema: è il caso del telefono vero.
        SnapshotScene("root-home", height: deviceHeight, settle: 2.5,
                      view: RootShellScene(environment: full, tab: .home)),
        SnapshotScene("root-scheda", height: deviceHeight, settle: 2.5,
                      view: RootShellScene(environment: full, tab: .program)),
        SnapshotScene("root-esercizi", height: deviceHeight,
                      view: RootShellScene(environment: full, tab: .exercises)),
        SnapshotScene("root-misure", height: deviceHeight,
                      view: RootShellScene(environment: full, tab: .measures)),
        SnapshotScene("root-scuro", height: deviceHeight, dark: true, settle: 2.5,
                      view: RootShellScene(environment: full, tab: .home)),

        // VERIFICA DELLE FASCE: le stesse radici scrollate FINO IN FONDO. L'ultima
        // riga deve terminare sopra il bordo superiore della fascia della tab bar.
        SnapshotScene("root-esercizi-fondo", height: deviceHeight, settle: 4,
                      view: RootShellScene(environment: full, tab: .exercises, scrolledToBottom: true)),
        SnapshotScene("root-misure-fondo", height: deviceHeight, settle: 3,
                      view: RootShellScene(environment: full, tab: .measures, scrolledToBottom: true)),
        SnapshotScene("root-home-fondo", height: deviceHeight, settle: 4,
                      view: LongHomeShellScene()),
        SnapshotScene("root-esercizi-zona-fondo", height: deviceHeight, settle: 6,
                      view: GroupShellScene()),

        // Pagine spinte DENTRO la shell: la tab bar resta visibile e il contenuto
        // (bottoni ancorati in basso compresi) deve stare sopra di lei.
        SnapshotScene("root-scheda-giorno", height: deviceHeight, settle: 4,
                      view: ShellScene(variant: .programDay)),
        // Lista più corta dello schermo: è il caso in cui sul telefono il bottone
        // "Aggiungi esercizi" finiva sotto la capsula.
        SnapshotScene("root-scheda-giorno-corto", height: deviceHeight, settle: 4,
                      view: ShellScene(variant: .programDayShort)),
        // Lista più lunga dello schermo, scrollata in fondo.
        SnapshotScene("root-scheda-giorno-lungo", height: deviceHeight, settle: 4,
                      view: ShellScene(variant: .programDayLong, scrolledToBottom: true)),
        SnapshotScene("root-esercizi-dettaglio", height: deviceHeight, settle: 6,
                      view: ShellScene(variant: .exerciseDetail)),
        SnapshotScene("root-misure-dettaglio", height: deviceHeight, settle: 3,
                      view: ShellScene(variant: .bodyMetric)),

        // Coerenza delle intestazioni: le quattro radici affiancate. Titolo alla
        // stessa Y, stessa dimensione, bottone alla stessa X/Y e stessa forma.
        SnapshotScene("coerenza-intestazioni", height: 4 * 230 + 3, settle: 5,
                      view: HeaderConsistencyScene(environment: full)),

        // Avvio fallito: lo stato di errore ha sempre la sua azione "Riprova".
        SnapshotScene("root-avvio-errore", height: deviceHeight,
                      view: RootView(environment: AppEnvironment(
                          store: empty.store,
                          phase: .failed(AppEnvironment.libraryFailureMessage)
                      ))),

        // Shell, primo avvio (nessuna scheda, nessuna rilevazione).
        SnapshotScene("root-home-vuota", height: deviceHeight,
                      view: RootView(environment: empty, initialTab: .home)),
        SnapshotScene("root-scheda-vuota", height: deviceHeight,
                      view: RootView(environment: empty, initialTab: .program)),
        SnapshotScene("root-misure-vuoto", height: deviceHeight,
                      view: RootView(environment: empty, initialTab: .measures)),

        // Home: la scheda in consultazione, la schermata da palestra.
        SnapshotScene("home", height: deviceHeight, settle: 3, view: HomeVariantScene(variant: .day)),
        SnapshotScene("home-alta", height: 1400, settle: 3, view: HomeVariantScene(variant: .day)),
        SnapshotScene("home-giorno-b", height: deviceHeight, settle: 3, view: HomeVariantScene(variant: .otherDay)),
        SnapshotScene("home-scuro", height: deviceHeight, dark: true, settle: 3, view: HomeVariantScene(variant: .day)),
        SnapshotScene("home-vuota", height: deviceHeight, view: screen(HomeScreen(), in: empty)),
        SnapshotScene("home-esercizio-dettaglio", settle: 6, view: HomeVariantScene(variant: .detail)),

        // Esercizi: zone colpite, elenco di una zona, ricerca, dettaglio, picker.
        SnapshotScene("esercizi", settle: 4, view: ExercisesVariantScene(variant: .catalog)),
        SnapshotScene("esercizi-scuro", dark: true, settle: 4, view: ExercisesVariantScene(variant: .catalog)),
        SnapshotScene("esercizi-zona", settle: 6, view: ExercisesVariantScene(variant: .group)),
        SnapshotScene("esercizi-ricerca", settle: 5, view: screen(
            ExercisesScreen(preset: ExerciseSearchModel(query: "panca piana")),
            in: full
        )),
        SnapshotScene("esercizi-nessun-risultato", settle: 3, view: screen(
            ExercisesScreen(preset: ExerciseSearchModel(query: "panca romana")),
            in: full
        )),
        SnapshotScene("esercizi-dettaglio", settle: 6, view: screen(ExerciseDetailScreen(exerciseID: "0227"), in: full)),
        SnapshotScene("esercizi-personalizzato", settle: 3, view: ExercisesVariantScene(variant: .customForm)),
        SnapshotScene("esercizi-personalizzato-dettaglio", settle: 5, view: ExercisesVariantScene(variant: .customDetail)),
        SnapshotScene("esercizi-picker", height: deviceHeight, settle: 4, view: ExercisesVariantScene(variant: .picker)),
        SnapshotScene("esercizi-picker-zona", height: deviceHeight, settle: 6, view: ExercisesVariantScene(variant: .pickerGroup)),
        SnapshotScene("esercizi-picker-dettaglio", settle: 6, view: ExercisesVariantScene(variant: .pickerDetail)),

        // Scheda: qui si modifica.
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

        // Muscoli colpiti: la ripartizione della scheda.
        SnapshotScene("muscoli-riepilogo", height: 460, settle: 2.5, view: MusclesScene(variant: .summary)),
        SnapshotScene("muscoli-giorno", height: 300, settle: 2.5, view: MusclesScene(variant: .day)),
        SnapshotScene("muscoli-squilibrata", height: 340, settle: 2.5, view: MusclesScene(variant: .unbalanced)),
        SnapshotScene("muscoli-compatto", height: 480, settle: 2.5, view: MusclesScene(variant: .compact)),
        SnapshotScene("muscoli-vuoto", height: 240, settle: 2.5, view: MusclesScene(variant: .empty)),
        SnapshotScene("muscoli-scuro", height: 460, dark: true, settle: 2.5, view: MusclesScene(variant: .summary)),

        // Misure.
        SnapshotScene("misure", view: screen(MeasuresScreen(), in: full)),
        SnapshotScene("misure-vuoto", view: screen(MeasuresScreen(), in: empty)),
        SnapshotScene("misure-dettaglio-peso", view: screen(BodyMetricDetailScreen(metric: .weight), in: full)),
        SnapshotScene("misure-nuova-rilevazione", view: screen(BodyEntrySheet(entry: nil, defaultDate: full.now), in: full)),

        // Impostazioni.
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
