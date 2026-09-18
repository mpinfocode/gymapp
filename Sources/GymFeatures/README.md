# GymFeatures

Le schermate dell'app. Dipende da `GymCore` (dati) e `GymUI` (design system).
Leggere prima `docs/SPEC.md` e `docs/DESIGN.md`: qui c'è solo il contratto tecnico.

## Convenzione d'ambiente (una sola, vincolante)

`RootView` inietta **un solo oggetto**: `AppEnvironment`.

```swift
struct TodayScreen: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Text(app.store.settings.displayName)
    }
}
```

Da lì si passa per tutto il resto:

| accesso | cosa dà |
| --- | --- |
| `app.store` | `AppStore`: dati e mutazioni (è `@Observable`, l'osservazione funziona anche annidata) |
| `app.exercises` | `ExerciseRepository`, `nil` finché la libreria non è pronta |
| `app.exercise(id:)` | un singolo esercizio |
| `app.now` | "adesso" secondo la sorgente di tempo dello store (fissa negli screenshot) |
| `app.calendar` | calendario con la settimana che inizia di lunedì |
| `app.unit` | unità di misura scelta dall'utente |
| `app.router` | tab selezionato e path di navigazione |

**Non** usare `@Environment(AppStore.self)`: lo store non viene iniettato da solo e
quella lettura va in crash a runtime. Mai leggere l'orologio di sistema con `Date()`
dentro una schermata: usare `app.now`, altrimenti gli screenshot non sono riproducibili.

## Struttura delle cartelle

```
App/          AppEnvironment, AppTab, RootView (shell, tab bar, cover della sessione)
Shared/       mattoni usati da più feature: Router, Formatters, ExerciseRowView,
              keyboardDoneToolbar, PlaceholderScreen
Today/        TodayScreen
Exercises/    ExercisesScreen, ExerciseDetailScreen, ExercisePickerSheet
Program/      ProgramScreen
Session/      ActiveSessionScreen, SessionSummaryScreen
Progress/     ProgressScreen, SessionDetailScreen
Settings/     SettingsScreen
```

Una cartella per feature. Quello che serve a una sola feature resta dentro la sua
cartella (`private`/`internal`); in `Shared/` va solo ciò che è davvero riusato.

## Firme pubbliche già fissate

Sono il contratto fra i cinque sviluppatori: **non cambiarle**, si sostituisce solo il `body`.

```swift
TodayScreen()
ExercisesScreen()
ExerciseDetailScreen(exerciseID: String)
ExercisePickerSheet(title: String, allowsMultipleSelection: Bool,
                    excludedIDs: Set<String>, onPick: ([Exercise]) -> Void)
ProgramScreen()
ActiveSessionScreen(onMinimize: () -> Void)
SessionSummaryScreen(sessionID: UUID)
ProgressScreen()
SessionDetailScreen(sessionID: UUID)
SettingsScreen()
```

`SettingsScreen` non è un tab: la apre `TodayScreen` come `.sheet` (avatar in alto a destra).

## Navigazione

Ogni tab ha il suo `NavigationStack` con il path dentro `Router`. Le destinazioni
condivise sono già installate da `RootView`:

```swift
NavigationLink(value: AppRoute.exercise(id: exercise.id)) { ExerciseRowView(exercise: exercise) }
NavigationLink(value: AppRoute.session(id: session.id)) { ... }

app.router.openExercise(id: "0025")   // apre il dettaglio anche da un altro tab
```

La navigazione locale a una feature (editor, picker, sheet) resta locale: niente
rotte nuove senza necessità.

Nota: i quattro stack restano tutti nella gerarchia (visibilità con `opacity`), così
il cambio tab conserva path, ricerca e scroll. Conseguenza da tenere presente: gli
`.onAppear` / `.task` dei quattro tab partono all'avvio, non alla prima visita.

La tab bar **non** si nasconde entrando in profondità: farlo bene richiederebbe che
ogni feature riportasse il proprio stato di navigazione alla shell. La barra è
flottante e il contenuto è già inset con `safeAreaInset`, quindi le schermate non
devono aggiungere padding in fondo.

## Sessione attiva

`RootView` presenta `ActiveSessionScreen` a schermo intero quando
`store.activeSession != nil`. Chiudere la cover **non** termina la sessione: chiama
`onMinimize()`, la shell mostra la barra "Riprendi allenamento" sopra la tab bar e
l'utente può continuare a navigare. Terminare davvero la sessione è
`store.finishSession()` (oppure `store.discardSession()`), e da lì si apre
`SessionSummaryScreen`.

Nessuna schermata presenta la sessione da sé: per avviarla basta chiamare lo store
(`store.startSession(programID:dayID:)`, `startTodaysSession()`, `startFreeSession()`)
e la cover compare da sola. Lo stato "minimizzata" vive nel `Router`
(`router.isSessionMinimized`): un bottone "Riprendi" chiama `app.router.resumeSession()`,
chi chiude la cover chiama `router.minimizeSession()`.

## Come aggiungere una schermata

1. Crea il file nella cartella della sua feature.
2. `public struct NomeScreen: View` con `public init(...)` esplicito e parametri
   minimi (id, non oggetti interi: si risolvono dallo store).
3. Leggi l'ambiente con `@Environment(AppEnvironment.self) private var app`.
4. Solo token di `GymUI`: `Theme.*`, `Font.*`, componenti esistenti. **Mai** colori
   o font letterali; mai "—" o "–" nelle stringhe; testi in italiano.
5. Se serve una rotta condivisa, aggiungi un caso a `AppRoute` e la sua destinazione
   in `RootView.tabStack`. Altrimenti navigazione locale.
6. Registra una scena in `Sources/GymSnapshots/Scenes.swift` (stato pieno e, dove
   ha senso, stato vuoto) e guarda il PNG prima di aprire la PR.

Vietati in tutto il target: `#Preview`, SwiftData, XCTest/Swift Testing, dipendenze
esterne. Le API solo-iOS vanno in `#if os(iOS)` piccoli e banali (vedi
`Shared/KeyboardDoneToolbar.swift`): quel codice non viene type-checkato in locale.

## Mattoni condivisi

- `ExerciseRowView(exercise:subtitle:accessory:)`: thumbnail + nome + "muscolo · attrezzo",
  accessorio trailing libero.
- `Formatters`: pesi con virgola italiana (`weight`), volumi con separatore delle
  migliaia (`volume` → "12.480 kg"), cronometro (`clock` → "05:30"), durate
  (`minutes` → "45 min"), date relative (`relativeDay` → "oggi" / "ieri" / "lun 14 set").
  Valore mancante: `Formatters.missing` ("·"), mai "—".
- `.keyboardDoneToolbar { focus = nil }`: barra "Fatto" sopra il tastierino numerico.
- `PlaceholderScreen`: solo per i segnaposto, sparisce con l'implementazione.

## Screenshot

```bash
swift build                 # deve essere pulito, senza warning
swift run GymChecks         # test di GymCore
swift run GymSnapshots      # tutte le scene in docs/preview (fuori da git)
swift run GymSnapshots oggi # solo le scene il cui nome contiene "oggi"
```

Le scene stanno in `Sources/GymSnapshots/Scenes.swift`, i dati finti in
`Sources/GymSnapshots/MockData.swift` (scheda attiva alla settimana 3 di 6, 14
sessioni nelle ultime 5 settimane, 6 rilevazioni corporee, preferiti, "adesso"
fisso a giovedì 17 settembre 2026 alle 17:40, più una variante vuota e una con una
sessione in corso a metà). Le schermate lunghe si rendono a 1600 punti di altezza
perché una `ScrollView` viene fotografata per l'altezza data.
