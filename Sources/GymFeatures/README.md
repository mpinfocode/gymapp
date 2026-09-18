# GymFeatures

Le schermate dell'app. Dipende da `GymCore` (dati) e `GymUI` (design system).
Leggere prima `docs/SPEC.md` (in particolare **§0 "Scopo semplificato"**, che prevale
su tutto) e `docs/DESIGN.md`: qui c'è solo il contratto tecnico.

## Convenzione d'ambiente (una sola, vincolante)

`RootView` inietta **un solo oggetto**: `AppEnvironment`.

```swift
struct MeasuresScreen: View {
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
| `app.router` | tab selezionato, path di navigazione, Impostazioni, ritocco del tab |

**Non** usare `@Environment(AppStore.self)`: lo store non viene iniettato da solo e
quella lettura va in crash a runtime. Mai leggere l'orologio di sistema con `Date()`
dentro una schermata: usare `app.now`, altrimenti gli screenshot non sono riproducibili.

## Struttura delle cartelle

```
App/          AppEnvironment, AppTab, RootView (shell, tab bar, sheet Impostazioni)
Shared/       mattoni usati da più feature: Router, Formatters, ExerciseRowView,
              keyboardDoneToolbar, PlaceholderScreen
Home/         HomeScreen: la scheda attiva in sola consultazione (tab iniziale)
Program/      ProgramScreen, editor della scheda e dei giorni, archivio
Exercises/    ExercisesScreen, ExerciseDetailScreen, ExercisePickerSheet
Measures/     MeasuresScreen, BodyMetricDetailScreen, BodyEntrySheet
Settings/     SettingsScreen
```

Una cartella per feature. Quello che serve a una sola feature resta dentro la sua
cartella (`private`/`internal`); in `Shared/` va solo ciò che è davvero riusato.

Le cartelle `Today/`, `Session/` e `Progress/` **non esistono più**: sessione
guidata, storico e statistiche di allenamento sono usciti dalla UI (SPEC §0). Il
dominio corrispondente resta in GymCore, semplicemente nessuna schermata lo espone.

## Firme pubbliche già fissate

Sono il contratto fra gli sviluppatori: **non cambiarle**, si sostituisce solo il `body`.

```swift
HomeScreen()
ProgramScreen()
ExercisesScreen()
ExerciseDetailScreen(exerciseID: String)
ExercisePickerSheet(title: String, allowsMultipleSelection: Bool,
                    excludedIDs: Set<String>, onPick: ([Exercise]) -> Void)
MeasuresScreen()
BodyMetricDetailScreen(metric: BodyMetricKind)
BodyEntrySheet(entry: BodyEntry?, defaultDate: Date)
SettingsScreen()
```

`SettingsScreen` non è un tab: la presenta **la shell** (vedi sotto).

## Navigazione

Quattro tab, in quest'ordine: **Home · Scheda · Esercizi · Misure**. Home è la tab
iniziale. Ogni tab ha il suo `NavigationStack` con il path dentro `Router`.
**Tutte** le pagine che si aprono spingendo sono casi di `AppRoute` e le loro
destinazioni sono installate una volta sola da `RootView`:

```swift
NavigationLink(value: AppRoute.exercise(id: exercise.id)) { ExerciseRowView(exercise: exercise) }

app.router.push(.programDay(programID: program.id, dayID: day.id))  // spinge nel tab corrente
app.router.openExercise(id: "0025")                                 // anche da un altro tab
```

Rotte disponibili: `.exercise(id:)`, `.programDay(programID:dayID:)`,
`.programArchive`, `.bodyMetric(_:)`.

La navigazione **modale** di una feature (editor, picker, sheet) resta locale:
niente rotte nuove per una sheet.

## Impostazioni

Le apre **la shell** come `.sheet`, non una singola schermata:

```swift
app.router.presentSettings()   // ingranaggio discreto nella testata della Home
app.router.dismissSettings()
```

In tutta l'app esiste **un solo** accesso alle Impostazioni (l'ingranaggio della
Home): non aggiungerne altri.

## Tab bar e spazio riservato

La tab bar flottante è **sempre visibile**, anche nelle pagine spinte: è l'unico
modo per ritoccare l'icona di un tab da qualunque profondità.

Lo spazio in fondo lo riserva la shell con `tabBarSafeArea()`, applicato **fuori**
dal `NavigationStack` di ogni tab (`FloatingTabBarMetrics.reservedHeight` come
`safeAreaInset(edge: .bottom)`). La safe area ridotta si propaga così anche alle
pagine spinte: una pagina con un bottone primario ancorato in basso lo mette nel
proprio `safeAreaInset(edge: .bottom)` e finisce **sopra** la barra, senza aggiungere
padding a mano. Le schermate **non** devono riservare spazio da sé: sarebbe contato
due volte.

`router.isAtRoot` resta disponibile (dice se il tab selezionato è alla sua radice)
ma non governa più la visibilità della barra.

## Ritocco del tab (torna alla radice e in cima)

Ritoccare l'icona del tab **già selezionato**:

- se la sezione è in profondità → torna alla sua radice (pop animato);
- se è già alla radice → la schermata radice deve **scorrere in cima**.

Lo decide la shell chiamando `Router.reselect(_:)`. Le radici si agganciano al
token osservabile:

```swift
ScrollViewReader { proxy in
    ScrollView {
        content.id(topID)          // un'ancora qualsiasi in cima alla pagina
    }
    .onChange(of: app.router.scrollToTopToken(for: .program)) { _, _ in
        withAnimation(Theme.Motion.smooth) { proxy.scrollTo(topID, anchor: .top) }
    }
}
```

API del `Router`: `reselect(_ tab:)`, `scrollToTopToken(for: AppTab) -> Int`,
`popToRoot(_ tab:)`, `popToRoot()`. `MeasuresScreen` è già agganciata; le radici di
**Home**, **Scheda** ed **Esercizi** devono agganciarsi allo stesso modo.

> **Limite noto (richiesta per GymUI)**: `FloatingTabBar` ignora il tocco sulla tab
> già selezionata (`guard !isSelected else { return }` in `tabButton`), quindi il
> `set` del binding non viene mai chiamato e il ritocco non arriva alla shell. Serve
> una modifica in GymUI: togliere quel `guard` (riassegnando comunque `selection`)
> oppure aggiungere `onReselect: ((ID) -> Void)?` all'inizializzatore. Tutto il resto
> della catena (binding, `reselect`, token, aggancio di Misure) è già pronto e
> funzionerà senza altre modifiche.

## Come aggiungere una schermata

1. Crea il file nella cartella della sua feature.
2. `public struct NomeScreen: View` con `public init(...)` esplicito e parametri
   minimi (id, non oggetti interi: si risolvono dallo store).
3. Leggi l'ambiente con `@Environment(AppEnvironment.self) private var app`.
4. Solo token di `GymUI`: `Theme.*`, `Font.*`, componenti esistenti. **Mai** colori
   o font letterali; mai "—" o "–" nelle stringhe; testi in italiano.
5. Se serve una rotta condivisa, aggiungi un caso a `AppRoute` e la sua destinazione
   in `RootView.destination`. Altrimenti navigazione locale.
6. Registra una scena in `Sources/GymSnapshots/Scenes.swift` (stato pieno e, dove
   ha senso, stato vuoto) e guarda il PNG prima di aprire la PR.

Vietati in tutto il target: `#Preview`, SwiftData, XCTest/Swift Testing, dipendenze
esterne. Le API solo-iOS vanno in `#if os(iOS)` piccoli e banali (vedi
`Shared/KeyboardDoneToolbar.swift`): quel codice non viene type-checkato in locale.

## Mattoni condivisi

- `ExerciseRowView(exercise:subtitle:accessory:)`: thumbnail + nome + "muscolo · attrezzo",
  accessorio trailing libero.
- `Formatters`: pesi con virgola italiana (`weight`), cronometro (`clock` → "05:30"),
  durate (`minutes` → "45 min"), date relative (`relativeDay` → "oggi" / "ieri" /
  "lun 14 set"). Valore mancante: `Formatters.missing` ("·"), mai "—".
- `.keyboardDoneToolbar { focus = nil }`: barra "Fatto" sopra il tastierino numerico.
- `PlaceholderScreen`: solo per i segnaposto, sparisce con l'implementazione.

## Screenshot

```bash
swift build                    # deve essere pulito, senza warning
swift run GymChecks            # test di GymCore
swift run GymSnapshots         # tutte le scene in docs/preview (fuori da git)
swift run GymSnapshots misure  # solo le scene il cui nome contiene "misure"
swift run GymPreview           # l'app in una finestra Mac formato iPhone
swift run GymPreview --png=/tmp/shell.png   # solo un PNG, senza finestra
```

Le scene stanno in `Sources/GymSnapshots/Scenes.swift`, i dati finti in
`Sources/GymSnapshots/MockData.swift` (scheda attiva alla settimana 3 di 6, un ciclo
precedente in archivio, 6 rilevazioni corporee, preferiti, "adesso" fisso a giovedì
17 settembre 2026 alle 17:40, più una variante vuota). Niente sessioni finte: la UI
non le espone più. Le schermate lunghe si rendono a 1600 punti di altezza perché una
`ScrollView` viene fotografata per l'altezza data; le scene `root-*` si rendono a
852 punti (altezza reale di un iPhone) per verificare la tab bar.
