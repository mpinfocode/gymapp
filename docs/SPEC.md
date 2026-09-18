# GymApp — Specifica di prodotto e architettura

App iOS personale (un solo utente) per allenarsi in palestra: libreria di 1.324 esercizi con GIF,
la scheda dell'istruttore (giorni, esercizi, serie, carichi, recuperi), sessione di allenamento con log di serie/ripetizioni/carico, timer di recupero, storico e progressi.
Lingua: **solo italiano** (UI e istruzioni esercizi; nessuna scelta lingua, `en` resta nel JSON solo come fallback tecnico). Tutto gratis, nessun login, nessun backend. Distribuzione: l'utente ha un Apple Developer account → obiettivo TestFlight da CI (chiave API nei GitHub Secrets, inserita dall'utente). Più telefoni = **installazioni indipendenti**: ogni iPhone ha la propria scheda e i propri dati in locale, nessuna sincronizzazione (non richiesta). Neon/Vercel non servono; se mai servissero vanno usati come servizi separati, mai con l'integrazione Neon dentro Vercel.

## 1. Vincoli NON negoziabili

1. **Niente Xcode sul Mac.** Sono installate solo le Command Line Tools (Swift 6.2, SDK macOS 26). Non installare Xcode, simulatori o toolchain pesanti.
2. Verificato sul toolchain locale:
   - ✅ compilano: `SwiftUI`, `Charts`, `Observation` (`@Observable`), `Foundation`, `ImageIO`, `CryptoKit`
   - ❌ NON disponibili (plugin macro / moduli assenti): **SwiftData** (`@Model`, `@Query`), **`#Preview`**, **XCTest**, **Swift Testing**
   - Quindi: persistenza = `Codable` + file JSON; niente `#Preview`; test = eseguibile `GymChecks` (`swift run GymChecks`).
3. Tutto il codice vive in un **Swift Package** che compila **anche per macOS** → verifica locale con `swift build`. Ogni API solo-iOS va isolata con `#if os(iOS)` / `#if canImport(UIKit)` e ridotta al minimo indispensabile (quel codice non viene type-checkato in locale, quindi deve essere banale e scritto con estrema cura).
4. La build iOS reale avviene su **GitHub Actions** (runner macOS) con **XcodeGen** → `.ipa` non firmata come artifact → installazione su iPhone via sideload (Sideloadly/AltStore, Apple ID gratuito).
5. Zero dipendenze SPM esterne salvo necessità dimostrata.
6. Target: iOS 17+, solo iPhone, portrait. Swift 6 language mode, concurrency rigorosa (`@MainActor` per UI/store).
7. Media degli esercizi © Gym visual: **mai committare GIF/immagini nel repo**, risoluzione 180×180, attribuzione "© Gym visual — https://gymvisual.com/" visibile nel dettaglio esercizio e in Impostazioni → Crediti.

## 2. Dataset

Fonte: https://github.com/hasaneyldrm/exercises-dataset (dati MIT, media © Gym visual).
- `data/exercises.json`: 1.324 record. Campi: `id, name, category, body_part, equipment, target, muscle_group, secondary_muscles[], instructions{lang}, instruction_steps{lang:[String]}, image, gif_url, media_id, created_at, attribution`.
- Categorie (10): back, cardio, chest, lower arms, lower legs, neck, shoulders, upper arms, upper legs, waist. Equipment: 28 valori.
- `scripts/fetch_dataset.sh` scarica il JSON e genera `Sources/GymCore/Resources/exercises.json` **ridotto** (solo lingue `it` e `en`, solo `instruction_steps`, senza `instructions`/`created_at`) → qualche MB, committato.
- Media caricati a runtime da `https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/<image|gif_url>` con cache su disco permanente (Caches → meglio `Application Support/Media`, escluso da backup) + funzione "Scarica tutto per uso offline" in Impostazioni (in palestra spesso non c'è rete).
- I nomi esercizio sono solo in inglese: mostrarli capitalizzati. Categoria / attrezzo / muscolo tradotti in italiano con mappa statica in GymCore (`Localization`).

### Qualità del dataset (audit a campione del PM, 2026-09-18) e correzioni da applicare
Esito: zona del corpo (`category`) affidabile su tutti i 1.324 record; `target` corretto per petto, dorso, spalle, braccia, addome, polpacci; istruzioni italiane presenti ovunque (4-11 passi). Difetti noti, da gestire in GymCore con uno strato `ExerciseCorrections` applicato al caricamento (il JSON resta quello upstream):
1. **Gambe**: 68 esercizi tipo squat / affondi / leg press / step-up hanno `target = glutes` con `quadriceps` solo tra i secondari (eredità ExerciseDB). Correzione: per i nomi che contengono squat, lunge, leg press, step-up, split squat, hack, sissy, wall sit → target `quads`, e `glutes` passa in testa ai secondari. NON toccare hip thrust, glute bridge, kickback, deadlift, good morning, pull through (glutei/femorali corretti). Stacchi rumeni e a gambe tese, good morning → target `hamstrings` con glutes secondario.
2. Il campo `muscle_group` è solo una copia del primo muscolo secondario (1.324 su 1.324): **non usarlo nella UI né nei filtri**; mostrare "target" + "secondari".
3. Secondari anatomicamente deboli (es. leg extension → hamstrings, pushdown → forearms): mostrarli in piccolo come "muscoli secondari", mai usarli per le statistiche per gruppo muscolare (che usano solo target/categoria corretti).
4. Varianti ridondanti ("v. 2", "(female)", "(back pov)", "(side pov)"): tenerle, ma nella ricerca ordinare dopo la variante base.
5. **Esercizi mancanti** (es. face pull, bulgarian split squat non esistono con quel nome): serve **"Esercizio personalizzato"**: l'utente crea un esercizio proprio (nome, zona, muscolo target, attrezzo, note; senza GIF, con segnaposto sobrio), utilizzabile nella scheda e nelle statistiche come gli altri. Id con prefisso `custom-`, salvati in una collezione dello store.
6. **Ricerca in italiano**: i nomi restano in inglese a schermo, ma la ricerca accetta il gergo italiano tramite dizionario di sinonimi (panca→bench press, panca inclinata→incline, stacco→deadlift, trazioni→pull-up/chin-up, rematore→row, lento avanti/military→overhead press, alzate laterali→lateral raise, alzate frontali→front raise, croci→fly, affondi→lunge, pressa→leg press, tirate al mento→upright row, scrollate→shrug, french press, spinte→press, distensioni, dip/parallele→dip, piegamenti/flessioni→push-up, addominali→crunch/abs, polpacci→calf, femorali→leg curl/hamstrings, glutei, ponte→bridge/hip thrust, pulley/lat machine→pulldown/seated row, manubrio/i, bilanciere, cavo/i, elastico, multipower→smith, ecc.). Copertura da verificare in GymChecks con una lista di query reali italiane e il primo risultato atteso.

## 3. Struttura del progetto

```
Package.swift                 # pacchetto "GymKit" (scritto dal PM, non modificare senza chiedere)
Sources/GymCore/              # modelli, persistenza, repository esercizi, statistiche. Solo Foundation/Observation. NIENTE SwiftUI.
Sources/GymCore/Resources/    # exercises.json ridotto
Sources/GymUI/                # design system: tema, tipografia, componenti, GIF/immagini remote. SwiftUI. Non dipende da GymCore.
Sources/GymFeatures/          # schermate. Dipende da GymCore + GymUI. Una cartella per feature.
Sources/GymChecks/            # eseguibile di test per GymCore (assert + exit code)
App/                          # target app iOS: GymApp.swift (@main), Assets, generato con XcodeGen
project.yml                   # XcodeGen
.github/workflows/ios.yml     # build IPA non firmata
scripts/                      # fetch_dataset.sh ecc.
docs/                         # SPEC.md, DESIGN.md
```

## 4. Modello dati (GymCore) — tutti `Codable, Sendable, Identifiable, Hashable`

- `Exercise`: id(String), name, category, bodyPart, equipment, target, muscleGroup, secondaryMuscles, steps[lang:[String]], imagePath, gifPath, attribution. Helper: `imageURL`, `gifURL`, `displayName`.
- `Program` (= la **scheda** dell'istruttore): id(UUID), name, notes, startDate, plannedWeeks(Int?, tipicamente 4–8), mode(`.rotation` | `.weekdays`), days:[ProgramDay], accent(Int seed gradiente), isArchived, createdAt, updatedAt. Computed: `endDate`, `weeksElapsed`, `isExpired`, `daysToExpiry`.
  - **Una sola scheda attiva alla volta** (`settings.activeProgramID`); le altre restano in archivio consultabili, duplicabili e riattivabili. Lo storico delle sessioni non si perde mai.
  - `ProgramDay`: id, name ("Giorno A", "Push"…), weekday(Weekday?, usato solo in modalità `.weekdays`), items:[PlanItem], note.
  - `PlanItem`: id, exerciseID, targetSets(Int), measure(`.reps(min:Int,max:Int)` | `.duration(seconds:Int)`), targetWeightKg(Double?), warmupSets(Int), restSeconds(Int), supersetGroup(Int?), note ("presa stretta", "panca 30°").
  - **Allenamento di oggi**: `.weekdays` → il giorno con weekday == oggi (altrimenti riposo, ma si può avviare qualunque giorno); `.rotation` → il giorno successivo all'ultimo giorno completato di quella scheda (ciclico), sempre sovrascrivibile a mano.
- `WorkoutSession`: id, programID?, programDayID?, name, startedAt, endedAt?, entries:[SessionEntry], notes. Computed: durata, volume totale, serie completate.
  - `SessionEntry`: id, exerciseID, planItemID?, measureKind(.reps/.duration), sets:[SetLog], note, restSeconds, supersetGroup?.
  - `SetLog`: id, kind(.warmup/.normal/.drop/.failure), weightKg(Double?), reps(Int?), durationSec(Int?), rpe(Double?), completedAt(Date?).
- `BodyEntry`: id, date, weightKg(Double?), measurementsCm:[BodyMeasure: Double] con `BodyMeasure` = collo, spalle, petto, braccio dx/sx, avambraccio, vita, fianchi, coscia dx/sx, polpaccio (nomi italiani), più composizione corporea opzionale come da bilancia impedenziometrica della palestra: bodyFatPct, leanMassKg, muscleMassKg, waterPct. **Tutto inserito a mano dall'utente** (sono i valori che gli comunicano in palestra); ogni campo opzionale: si può registrare solo il peso o solo alcune misure.
- `UserSettings`: displayName, activeProgramID(UUID?), unit(.kg/.lb), defaultRestSeconds, favoriteExerciseIDs, recentExerciseIDs, hapticsEnabled.

Pesi sempre salvati in **kg**; conversione solo in presentazione.

### Persistenza
- `JSONFileStore` (actor): un file per collezione in `Application Support/GymApp/` — scrittura atomica, `JSONEncoder` ISO8601, directory iniettabile (per i check usare una temp dir).
- `AppStore` (`@MainActor @Observable`): facciata unica usata dalla UI. Carica tutto all'avvio, espone `programs, sessions, bodyEntries, settings, activeSession`, metodi di mutazione che salvano (debounce ~300 ms; **la sessione attiva si salva subito a ogni modifica**, deve sopravvivere a un crash/kill).
- `ExerciseRepository`: carica il JSON dal bundle (`Bundle.module`) off-main, indicizza per id, ricerca full-text (nome, muscolo, attrezzo; diacritici/case-insensitive, multi-token), filtri (categoria, attrezzo, target, preferiti), facets con conteggi.
- Backup: `exportBackup() -> Data` / `importBackup(Data)` (JSON unico versionato) — fondamentale perché il sideload può far perdere i dati.

### Statistiche (`Stats`, funzioni pure, ben testate in GymChecks)
- volume (Σ kg×reps, escluse warmup), 1RM stimato (Epley, reps ≤ 12), PR per esercizio (peso max, 1RM stimato max, volume max in sessione), rilevamento PR in tempo reale durante la sessione
- **suggerimento di progressione**: se nell'ultima sessione tutte le serie normali di un esercizio hanno raggiunto il massimo del range di ripetizioni al carico previsto → suggerire +2,5 kg (+1,25 per manubri/isolamento leggero: semplice euristica su equipment), mostrato come hint non invasivo
- "precedente": ultime serie fatte per lo stesso esercizio (per pre-compilare e mostrare colonna PRECEDENTE)
- per settimana: n. allenamenti, volume, durata, serie per gruppo muscolare; streak di settimane consecutive; griglia 30 giorni di attività
- serie storica per esercizio (data → best 1RM / peso max / volume)

## 5. Schermate (GymFeatures)

Tab bar flottante a pillola, 4 tab: **Oggi · Esercizi · Scheda · Progressi**. Impostazioni dall'avatar in alto a destra di Oggi.

1. **Oggi (Home)** — saluto, hero card dell'allenamento di oggi dalla scheda attiva (giorno proposto secondo la modalità; "Giorno di riposo"; "Nessuna scheda: creane una"), possibilità di scegliere un altro giorno o un allenamento libero, stato scheda ("Settimana 3 di 6", avviso quando mancano ≤7 giorni alla scadenza o è scaduta), striscia settimana L–D con giorni completati, riepilogo settimanale (allenamenti, minuti, volume), ultime sessioni, banner "Riprendi allenamento" se c'è una sessione attiva.
2. **Esercizi** — ricerca, chip filtro (gruppo muscolare, attrezzo, preferiti), lista con thumbnail, conteggi. **Dettaglio**: GIF grande su tile bianca, muscolo target + secondari, attrezzo, istruzioni a passi (italiano), preferito, storico personale dell'esercizio (grafico + PR), "Aggiungi alla scheda" (scelta del giorno), attribuzione.
3. **Scheda** — in alto la scheda attiva (card con gradiente, date, settimana corrente, giorni); sotto l'archivio. **Editor pensato per ricopiare velocemente la scheda cartacea dell'istruttore**: nome, data inizio, durata in settimane, modalità (rotazione / giorni fissi), giorni (aggiungi, rinomina, riordina, assegna giorno della settimana), per ogni giorno esercizi riordinabili con: serie, ripetizioni (singolo o range) **oppure durata**, carico previsto, serie di riscaldamento, recupero, superset, nota. Picker esercizi che riusa la ricerca, con aggiunta multipla. Azioni: attiva, archivia, duplica ("nuova scheda partendo da questa"), elimina. Al primo avvio: nessuna scheda finta, ma un empty state che invita a crearla + opzione "Carica scheda d'esempio" (Push/Pull/Legs con id reali).
4. **Sessione attiva** (full-screen cover, tema scuro immersivo) — timer totale, per ogni esercizio: GIF, nota della scheda, tabella serie (SERIE · PRECEDENTE · KG · REPS **o TEMPO** · ✓) precompilata da carico previsto/ultima prestazione, hint di progressione, esercizi a durata con cronometro/countdown integrato, aggiungi/rimuovi serie, tipo serie (riscaldamento/normale/drop/cedimento), **RPE opzionale per serie** (selettore rapido 6–10), note per esercizio e per sessione, timer di recupero automatico al ✓ con −15/+15 s, skip, haptic e notifica locale a fine recupero, badge PR in tempo reale, superset raggruppati, aggiungi/**sostituisci** (macchina occupata: propone esercizi con stesso target)/riordina esercizi, termina → **riepilogo** (durata, volume, serie, PR, nota finale) → salva.
5. **Progressi** — dashboard a card 2 colonne stile MacroFactor: allenamenti/settimana, volume, costanza 30 giorni, serie per gruppo muscolare, **peso corporeo**, **misure corporee** (inserimento manuale rapido di peso, circonferenze e composizione corporea — con i valori dell'ultima rilevazione come riferimento, grafico per ogni misura, variazione rispetto all'inizio della scheda), PR recenti; dettaglio per card con grafico grande e range 1M/3M/6M/1A; **Storico** sessioni (filtrabile per scheda) con dettaglio, modifica ed eliminazione.
6. **Impostazioni** — nome, unità, recupero di default, haptics, download offline dei media (progress), crediti e licenze. (Niente backup nell'interfaccia: non serve all'utente.)

**Fuori scope (app personale)**: account, social, abbonamenti, nutrizione, piani generati da AI, foto progressi, cadenza/TUT, Apple Watch/HealthKit (eventuale v2).

## 6. Definizione di "fatto" per ogni task
- `swift build` dalla root **senza errori e senza warning nuovi**; per GymCore anche `swift run GymChecks` verde.
- Nessuna API vietata (§1.2). Nessun file fuori dalla propria area. Niente TODO/stub lasciati in giro senza dichiararlo nel report.
- Report finale: file creati, API pubbliche esposte, decisioni prese, limiti noti, cosa NON è stato verificabile in locale.
