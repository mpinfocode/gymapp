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
        Text(app.store.displayName)
    }
}
```

Da lì si passa per tutto il resto:

| accesso | cosa dà |
| --- | --- |
| `app.store` | `AppStore`: dati e mutazioni (è `@Observable`, l'osservazione funziona anche annidata) |
| `app.rowPresentation(for:)` | titolo e sottoriga già pronti per una riga di lista |
| `app.exercises` | `ExerciseRepository`, `nil` finché la libreria non è pronta |
| `app.exercise(id:)` | un singolo esercizio |
| `app.now` | "adesso" secondo la sorgente di tempo dello store (fissa negli screenshot) |
| `app.calendar` | calendario con la settimana che inizia di lunedì |
| `app.unit` | unità di misura scelta dall'utente |
| `app.router` | tab selezionato, path di navigazione, Impostazioni, ritocco del tab |

**Non** usare `@Environment(AppStore.self)`: lo store non viene iniettato da solo e
quella lettura va in crash a runtime. Mai leggere l'orologio di sistema con `Date()`
dentro una schermata: usare `app.now`, altrimenti gli screenshot non sono riproducibili.

## Fluidità: dove stanno le dipendenze osservate

FLUIDITÀ è la priorità n.1 (SPEC §0) e il costo più alto non è il calcolo: sono le
**invalidazioni**. Tre regole, valide ovunque.

1. **Ogni dipendenza osservata sta nella view più piccola che può averla.** Se un
   valore serve solo a una riga, non si legge nel body della pagina. `RootView` è
   l'esempio: `AppShell.body` non legge niente, il tab lo leggono `TabSlot` e la tab
   bar, il foglio delle Impostazioni e le vibrazioni stanno in una view invisibile.
   Attenzione a `onChange(of:)`: il valore lo **legge il body** che lo ospita.
2. **Mai `app.store.settings.X` in un `body`.** `settings` ricostruisce il DTO e
   crea una dipendenza larga: chi la legge viene invalidato anche solo perché è
   cambiato l'elenco dei recenti. Si leggono le proprietà granulari
   (`displayName`, `unit`, `defaultRestSeconds`, `favoriteExerciseIDs`,
   `recentExerciseIDs`, `hapticsEnabled`, `activeProgramID`). `updateSettings { }`
   resta il modo di scrivere.
3. **Nel `body` non si calcola.** Ricerche, facet, ordinamenti, serie e domini dei
   grafici stanno in `@State` aggiornati da `.task(id: signature)`; la firma cambia
   solo quando cambia davvero il risultato. Il lavoro lungo va in
   `Task.detached` con `store.exerciseSearchSnapshot()`, che è `Sendable`.

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
`.programArchive`, `.bodyMetric(_:)`, `.exerciseGroup(_:)`,
`.planItem(programID:dayID:itemID:)`.

La navigazione **modale** di una feature (editor, picker, sheet) resta locale:
niente rotte nuove per una sheet. Una pagina **spinta**, invece, è sempre una rotta:
una `navigationDestination(item:)` locale dentro uno stack con `path:` vincolato al
Router sopravvive a `popToRoot`, e il ritocco del tab non riporta più alla radice.

## Impostazioni

Le apre **la shell** come `.sheet`, non una singola schermata:

```swift
app.router.presentSettings()   // ingranaggio discreto nella testata della Home
app.router.dismissSettings()
```

In tutta l'app esiste **un solo** accesso alle Impostazioni (l'ingranaggio della
Home): non aggiungerne altri.

## Layout a fasce: tab bar e barra di stato

La tab bar flottante è **sempre visibile**, anche nelle pagine spinte: è l'unico
modo per ritoccare l'icona di un tab da qualunque profondità.

La shell è un `VStack(spacing: 0)` con due fasce:

```
┌─────────────────────────┐
│  (barra di stato)       │  safe area della finestra, riempita da PageBackground
├─────────────────────────┤
│  AREA DEI CONTENUTI     │  i 4 TabSlot / NavigationStack, .clipped()
│                         │
├─────────────────────────┤
│  FASCIA DELLA TAB BAR   │  capsula + margini, sfondo pieno
│  (home indicator)       │  esteso sotto l'home indicator
└─────────────────────────┘
```

**Non esiste più `tabBarSafeArea()`**, e nessuna schermata deve riservare spazio in
fondo: "il fondo", per qualunque pagina (radici e spinte), è già il bordo superiore
della fascia. In fondo a un contenuto scrollabile va solo un respiro di
`Theme.Spacing.l`. Vietati `contentMargins`, padding compensativi e
`FloatingTabBarMetrics.scrollBottomInset` (residuo, non più usato).

Perché così: su iPhone (iOS 26) la safe area ridotta da un `safeAreaInset`
**non si propaga** dentro i `NavigationStack` e le loro `ScrollView`/`List`, che
continuano a considerare "fondo" il bordo fisico dello schermo. Su macOS e in
`GymPreview` si propagava, ed è per questo che il difetto era già stato "corretto"
due volte senza successo. Un `VStack` invece impone un **frame**, che è un vincolo
di layout duro anche per i contenitori UIKit; `.clipped()` chiude il caso limite.

Stessa regola per i **bottoni ancorati in basso**: `ProgramDayEditor` e
`ExercisePickerSheet` mettono il proprio bottone **sotto** l'elenco in un `VStack`,
non in un `safeAreaInset`, con fondo pieno
(`.background(Theme.background.ignoresSafeArea(edges: .bottom))`).

La **barra di stato** non ha bisogno di misure: la shell resta dentro la safe area
della finestra (quella della radice è l'unica affidabile) e l'area dei contenuti è
ritagliata, quindi niente può disegnare dove c'è l'orologio; quella zona la riempie
`PageBackground`, che è pieno e a tutto schermo.

`EnvironmentValues.deviceInsetsOverride` serve **solo** a chi simula un telefono
senza safe area: `GymPreview` in modalità "Safe area rigida" (menu Dispositivo,
attiva di default) e le scene `root-*` degli screenshot. In quella modalità la
cornice non passa **nessuna** safe area al contenuto e comunica le misure alla
shell, che costruisce le fasce da quei numeri: è il caso del telefono vero, dove
tutto ciò che sta sotto la shell vive con safe area zero. La vecchia modalità
(`--safe-area-morbida`) usa `safeAreaInset` e **nasconde** questa classe di difetti.

`router.isAtRoot` resta disponibile (dice se il tab selezionato è alla sua radice)
ma non governa più la visibilità della barra.

## Una sola intestazione

`Shared/PageHeader.swift` contiene gli unici mattoni ammessi:

| componente | dove |
| --- | --- |
| `PageHeader(title:subtitle:subtitleColor:trailing:)` | ogni pagina: radici e pagine spinte |
| `SheetHeader(title:subtitle:back:backTitle:actionTitle:action:)` | ogni sheet |
| `CircleIconButton` | l'unica azione di una `PageHeader` (44pt, cerchio `surface`) |
| `EllipsisMenu` | il menu "…", stessa forma |
| `SheetBackButton` | "Indietro" dentro una sheet |

Regole: titolo con `greetingStyle` (caso normale, mai `pageTitleStyle` heavy
maiuscolo), niente overline con la data, **al massimo una** azione a destra.
`PageHeader` porta con sé i propri margini (pagina 20, `top: s`, `bottom: xl`): si
mette come primo elemento di un `VStack(spacing: 0)` e il contenuto sotto si
impagina da sé. Le sheet usano `sheetHeaderMargins()` quando la testata sta dentro
un elenco scrollabile.

I titoli stanno **sempre nel contenuto**: la barra di navigazione di sistema resta
senza titolo (`navigationBarTitleDisplayModeInline()`) e serve solo al tasto
"indietro", uguale in tutte le pagine spinte. La scena `coerenza-intestazioni`
affianca le quattro radici per controllarlo a colpo d'occhio.

## Tastiera

Regola dell'utente: non deve mai esistere un campo con la tastiera aperta e nessuna
via d'uscita. Tre vie, sempre insieme:

1. `keyboardDismissable()` su **ogni** `ScrollView`/`List` (è
   `scrollDismissesKeyboard(.interactively)`): swipe in giù e la tastiera si chiude;
2. `keyboardDismissOnTap()` sulle schermate con campi: un tocco qualsiasi chiude la
   tastiera senza rubare il tocco a bottoni e righe (`simultaneousGesture`);
3. `keyboardDoneToolbar()` su tutti i campi numerici (il tastierino non ha invio).

La shell ignora la safe area della tastiera (`ignoresSafeArea(.keyboard)`): la
fascia non sale sopra la tastiera e non ruba spazio.

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

`FloatingTabBar` riassegna `selection` anche sul ritocco della tab già attiva (ed
espone `onReselect:`), quindi la catena binding → `reselect` → token funziona.

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
  accessorio trailing libero. Nelle **liste** si usa
  `ExerciseRowView(presentation:imageURL:)` con `app.rowPresentation(for:)`: titolo e
  sottoriga arrivano già calcolati dall'indice invece di essere ricostruiti a ogni `body`.
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
swift run GymPreview           # l'app in una finestra Mac formato iPhone (safe area RIGIDA)
swift run GymPreview --safe-area-morbida   # vecchio comportamento (safeAreaInset), solo per confronto
swift run GymPreview --png=/tmp/shell.png   # solo un PNG, senza finestra
```

Le scene stanno in `Sources/GymSnapshots/Scenes.swift`, i dati finti in
`Sources/GymSnapshots/MockData.swift` (scheda attiva alla settimana 3 di 6, un ciclo
precedente in archivio, 6 rilevazioni corporee, preferiti, "adesso" fisso a giovedì
17 settembre 2026 alle 17:40, più una variante vuota). Niente sessioni finte: la UI
non le espone più. Le schermate lunghe si rendono a 1600 punti di altezza perché una
`ScrollView` viene fotografata per l'altezza data; le scene `root-*` si rendono a
852 punti (altezza reale di un iPhone) per verificare la tab bar.
