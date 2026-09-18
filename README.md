# GymApp

App iOS personale (un solo utente) per allenarsi in palestra: libreria di 1.324 esercizi con GIF,
schede, sessione di allenamento con log di serie/ripetizioni/carico, timer di recupero, storico e
progressi. Interfaccia in italiano, nessun account, nessun backend, zero costi.

La specifica di prodotto è in [`docs/SPEC.md`](docs/SPEC.md), la direzione di design in
[`docs/DESIGN.md`](docs/DESIGN.md). Questo file spiega **come si costruisce e si installa**.

> **Vincolo che spiega tutto il resto:** sul Mac di sviluppo non c'è Xcode, solo le Command Line
> Tools. Quindi il codice vive in uno Swift Package che compila anche per macOS (verifica locale con
> `swift build`), e l'unica build iOS reale avviene su GitHub Actions.

---

## Struttura

```
Package.swift                   pacchetto "GymKit" — prodotti GymCore / GymUI / GymFeatures
Sources/GymCore/                modelli, persistenza, repository esercizi, statistiche (no SwiftUI)
Sources/GymCore/Resources/      exercises.json ridotto (committato, ~1,7 MB)
Sources/GymUI/                  design system: tema, tipografia, componenti, media remoti
Sources/GymFeatures/            schermate (dipende da GymCore + GymUI)
Sources/GymChecks/              eseguibile di test: `swift run GymChecks`
App/                            target iOS: GymApp.swift (@main), Assets.xcassets
project.yml                     spec XcodeGen del progetto Xcode
.github/workflows/ios.yml       build CI → Gym-unsigned.ipa
scripts/                        fetch_dataset.sh, make_icon.swift
docs/                           SPEC.md, DESIGN.md
```

File **generati**, non scritti a mano: `GymApp.xcodeproj` (da `project.yml`, non versionato) e
`App/Info.plist` (riscritto a ogni `xcodegen generate`, le chiavi si modificano in `project.yml`).

---

## Verifica in locale (senza Xcode)

Serve solo la toolchain Swift delle Command Line Tools:

```bash
swift build            # compila GymCore + GymUI + GymFeatures per macOS
swift run GymChecks    # esegue i check su GymCore (exit code ≠ 0 se falliscono)
```

Utile durante lo sviluppo:

```bash
swift build --target GymFeatures   # compila un solo modulo
swift build 2>&1 | grep warning    # nessun warning nuovo è parte della definizione di "fatto"
```

**Cosa NON è verificabile in locale**, e va quindi scritto con estrema cura: tutto il codice dentro
`#if os(iOS)` / `#if canImport(UIKit)`, il target app (`App/GymApp.swift`), `project.yml` e il
workflow. Non sono disponibili SwiftData, `#Preview`, XCTest e Swift Testing (vedi SPEC §1.2).

Rigenerare l'icona dell'app (CoreGraphics + ImageIO, nessun tool esterno):

```bash
swift scripts/make_icon.swift      # → App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Rigenerare il dataset dall'upstream (normalmente non serve: il file è già committato):

```bash
./scripts/fetch_dataset.sh
```

---

## Build CI

[`.github/workflows/ios.yml`](.github/workflows/ios.yml) gira su `push` verso `main` e su
`workflow_dispatch` (pulsante "Run workflow" nella tab Actions). Due job su `macos-latest`:

| job | cosa fa | perché |
| --- | --- | --- |
| `checks` | `swift build` + `swift run GymChecks` | stessi comandi del locale, fallisce presto |
| `ipa` | XcodeGen → build simulatore → archive device → `Gym-unsigned.ipa` | l'artefatto da installare |

`ipa` dipende da `checks` (`needs:`): se il package non compila non si spendono minuti macOS — che
sui runner GitHub contano **10×** rispetto a Linux. Un `concurrency group` annulla i run superati da
un push successivo.

Dettagli delle scelte:

- **Versione di Xcode**: `maxim-lobanov/setup-xcode@v1` con `xcode-version: latest-stable`. Seleziona
  la più recente Xcode *stabile* installata sull'immagine del runner, escludendo le preview (a
  settembre 2026 l'immagine `macos-latest` è macOS 26 con Xcode 26.6 di default e Xcode 27 in
  preview). In questo modo la build non dipende dal default dell'immagine, che GitHub cambia senza
  preavviso. Se in futuro un aggiornamento rompesse la build, basta pinnare (es. `xcode-version: '26.6'`).
- **XcodeGen**: `brew install xcodegen` — non è preinstallato sull'immagine. `xcbeautify` invece sì
  (v3.2.1), quindi il log passa da lì; il workflow ha comunque un fallback se non lo trova.
- **Due build**: una `Debug` per `generic/platform=iOS Simulator` come smoke test di compilazione, e
  una `Release` `archive` per `generic/platform=iOS`. La prima fallisce prima e con errori più
  leggibili; la seconda è quella che produce il bundle.
- **Nessuna firma**: `CODE_SIGNING_ALLOWED=NO` (e affini) sia in `project.yml` sia sulla riga di
  comando. L'IPA viene ri-firmata sul Mac al momento del sideload.
- **Nessuna cache**: il progetto non ha dipendenze SPM esterne (SPEC §1.5), quindi non c'è nulla da
  scaricare; una cache di `DerivedData` peserebbe più di quanto farebbe risparmiare. Se un giorno
  entrassero dipendenze esterne, la cosa sensata da cachare è
  `~/Library/Developer/Xcode/DerivedData/**/SourcePackages` + `~/Library/Caches/org.swift.swiftpm`.
- **Numero di build**: `MARKETING_VERSION` (0.1.0) sta in `project.yml`; il `CURRENT_PROJECT_VERSION`
  è sovrascritto dalla CI con `${{ github.run_number }}`, così ogni IPA ha un build number crescente.

L'artifact si chiama `Gym-unsigned.ipa` ed è caricato **senza zip aggiuntivo** (`archive: false`):
dalla pagina del run si scarica direttamente il `.ipa`. Se la tua versione di GitHub lo consegnasse
comunque dentro uno `.zip`, estrailo prima di usarlo.

### Aggiungere in futuro un job di screenshot (non implementato)

Non serve nessun segreto: gli screenshot si fanno sul **simulatore**, quindi restano gratis. Traccia:

1. Nuovo job `screenshots`, `runs-on: macos-latest`, `needs: checks`.
2. Avvio del simulatore: `xcrun simctl boot 'iPhone 17 Pro'` (elencare i device disponibili con
   `xcrun simctl list devicetypes` — i nomi cambiano a ogni versione di Xcode, meglio ricavarli a
   runtime invece di scriverli a mano).
3. Servono UI test, che oggi **non** esistono: XCTest/Swift Testing non sono usabili in locale
   (SPEC §1.2), quindi andrebbe aggiunto un target `GymUITests` solo-CI in `project.yml`, scritto
   alla cieca. In alternativa, più semplice: una build con uno schema di debug che espone un
   deep link (`xcrun simctl openurl booted gymapp://screenshot/oggi`) e uno script che chiama
   `xcrun simctl io booted screenshot out.png` dopo ogni navigazione.
4. Raccolta con `actions/upload-artifact`.
5. Costo: un simulatore che si avvia aggiunge 3–5 minuti macOS per run — conviene limitarlo a
   `workflow_dispatch` o a un `schedule` settimanale, non a ogni push.

Per ora non serve: l'app ha un solo utente e la si guarda sul telefono.

---

## TestFlight

[`.github/workflows/testflight.yml`](.github/workflows/testflight.yml) è la seconda pipeline:
firma l'app per davvero e la carica su App Store Connect, da dove arriva sull'iPhone tramite
l'app **TestFlight**. Rispetto al sideload dell'IPA non firmata: niente rinnovo ogni 7 giorni
(le build durano **90 giorni**), niente Mac collegato, installazione anche per un'altra persona.
Richiede l'**Apple Developer Program a pagamento** (99 €/anno), che l'utente ha.

`ios.yml` resta invariata e continua a produrre l'IPA non firmata: le due pipeline sono
indipendenti e si possono usare entrambe.

| | `ios.yml` | `testflight.yml` |
| --- | --- | --- |
| trigger | push su `main`, manuale | **solo** manuale e tag `v*` |
| firma | nessuna | automatica "cloud" con chiave API |
| risultato | artifact `Gym-unsigned.ipa` | build in TestFlight |
| segreti | nessuno | 4 GitHub Secrets |

### 1. Prerequisiti una tantum, lato Apple

Tutto si fa una volta sola, a mano, dal browser.

**a) Registrare l'App ID.** [developer.apple.com → Certificates, Identifiers & Profiles →
Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+** → *App IDs* →
*App* → Description: `Gym`, Bundle ID: **Explicit**, `it.mpinformatica.gymapp`. Nessuna capability
da spuntare: l'app usa solo notifiche **locali** (che non richiedono capability) e rete in HTTPS.

**b) Creare il record dell'app in App Store Connect.**
[appstoreconnect.apple.com → App](https://appstoreconnect.apple.com/apps) → **+** → *Nuova app*:
piattaforma iOS, nome (dev'essere unico su tutto l'App Store — se "Gym" è occupato serve un nome
diverso, p.es. "Gym — scheda palestra"; il nome sull'icona resta comunque `Gym`, è
`CFBundleDisplayName`), lingua principale *Italiano*, Bundle ID `it.mpinformatica.gymapp`, SKU
libero (p.es. `gymapp`). **Senza questo record l'upload fallisce**: non basta l'App ID.

Nella scheda dell'app conviene compilare subito anche **Privacy dell'app → "Non raccogliamo dati
da questa app"** (è vero: nessun backend, nessun analytics). Non serve per i tester interni, serve
appena si aggiungono tester esterni o si va in review.

**c) Creare la chiave API.** [App Store Connect → Utenti e accessi → Integrazioni → App Store
Connect API](https://appstoreconnect.apple.com/access/integrations/api) → scheda **Chiavi del team**
→ *Genera chiave API*. Nome libero (p.es. `github-actions-gymapp`).

> **Ruolo da assegnare: `Admin`.** È il minimo che funziona davvero per quello che fa questo
> workflow, e la ragione è precisa:
> - la firma automatica "cloud" (`-allowProvisioningUpdates`) fa creare a Xcode il **certificato di
>   distribuzione** e il **profilo di provisioning** passando dagli endpoint *Certificates,
>   Identifiers & Profiles* dell'API. Sulla tabella dei ruoli Apple, *creare e revocare certificati
>   di distribuzione* e *creare ed eliminare profili di distribuzione* compaiono solo per **Account
>   Holder e Admin**; App Manager e Developer non li hanno.
> - deve essere una **chiave del team**, non una *chiave individuale*: la documentazione Apple dice
>   esplicitamente che «Individual keys aren't able to use Provisioning endpoints».
> - `App Manager` basterebbe **solo** per caricare il binario, cioè se ci si portasse certificati e
>   profili da fuori (fastlane match o simili): non è il caso qui. `Developer` non può nemmeno
>   caricare build.
>
> Su un account con un solo sviluppatore l'Account Holder è già Admin, quindi non si sta allargando
> nulla: la chiave ha gli stessi poteri di chi la crea. Se un giorno dovesse dare fastidio, la via
> per scendere a `App Manager` è gestire certificato e profilo a mano (e allora va rivisto il
> workflow).

Alla generazione la pagina mostra **Key ID** e **Issuer ID** e un link *Scarica chiave API*: il file
`AuthKey_XXXXXXXXXX.p8` **si scarica una volta sola**, Apple non ne tiene copia. Mettilo in un posto
sicuro (p.es. il portachiavi/1Password), **fuori dal repository** — questo repo è pubblico.

**d) Annotare il Team ID.** [developer.apple.com → Membership
details](https://developer.apple.com/account#MembershipDetailsCard): 10 caratteri, p.es. `AB12CD34EF`.

### 2. I quattro GitHub Secrets

| secret | dove si trova | esempio |
| --- | --- | --- |
| `ASC_KEY_ID` | Key ID della chiave API | `2X9ABCD1EF` |
| `ASC_ISSUER_ID` | Issuer ID, in cima alla stessa pagina | `69a6de70-…-…` |
| `ASC_KEY_P8` | **contenuto** del file `AuthKey_XXXXXXXXXX.p8` | `-----BEGIN PRIVATE KEY-----…` |
| `APPLE_TEAM_ID` | Team ID | `AB12CD34EF` |

Dal terminale, con [GitHub CLI](https://cli.github.com) già autenticata (`gh auth login`), dalla
cartella del repository:

```bash
gh secret set ASC_KEY_ID     --body "2X9ABCD1EF"
gh secret set ASC_ISSUER_ID  --body "69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set APPLE_TEAM_ID  --body "AB12CD34EF"

# Il .p8 si passa come FILE, non copiato-incollato: gli a capo vanno preservati.
gh secret set ASC_KEY_P8 < ~/Downloads/AuthKey_2X9ABCD1EF.p8
```

Verifica (mostra solo i nomi, mai i valori — i secret non sono più rileggibili nemmeno dall'utente):

```bash
gh secret list
```

Il workflow si ferma al primo step con un messaggio esplicito se ne manca uno.

### 3. Lanciare il workflow

```bash
# Lancio manuale, con le note per i tester
gh workflow run testflight.yml -f note="Prima build: provare creazione scheda e sessione"

# Seguire il run
gh run watch

# In alternativa: una release vera, con tag
git tag v0.1.0 && git push origin v0.1.0
```

Oppure dal browser: tab **Actions → TestFlight → Run workflow**.

Cosa succede, in ordine: `swift build` + `swift run GymChecks` + controlli su icona e Info.plist
(gate economico: se è rosso non si spendono minuti macOS) → XcodeGen → `xcodebuild archive`
**senza firma** → `-exportArchive` con `method: app-store-connect`, che è il passo che crea
certificato e profilo con la chiave API e firma l'app → controllo dell'IPA → `xcrun altool
--upload-app`. Alla fine il riepilogo del run mostra versione, numero di build, strategia di firma
usata ed esito.

Dettagli delle scelte:

- **Solo `workflow_dispatch` e tag `v*`**. Mai `pull_request`/`pull_request_target`: il repository è
  pubblico e una PR da un fork non deve poter avvicinarsi alla chiave di firma. `permissions:
  contents: read`, `concurrency` dedicato e **senza** `cancel-in-progress` (interrompere un upload a
  metà lascia build fantasma "in elaborazione" su App Store Connect).
- **La chiave `.p8`** viene scritta in una cartella temporanea del runner con permessi `600`, non
  viene mai stampata (GitHub la maschera comunque nei log) e uno step `if: always()` cancella la
  cartella anche quando il run fallisce o viene annullato.
- **Nessuna IPA pubblicata come artifact.** Su un repository pubblico gli artifact dei run sono
  scaricabili da chiunque; l'IPA firmata contiene il profilo di provisioning. La build sta in
  TestFlight, che è il posto giusto.
- **Export + `altool`, non `destination: upload`.** `xcodebuild -exportArchive` sa anche caricare da
  solo (`destination: upload` nell'`ExportOptions.plist`), ma a oggi per quel passo si autentica con
  l'Apple ID salvato nelle preferenze di Xcode e **non** con la chiave API passata a
  `-authenticationKey*` (Feedback Assistant FB9145847, ancora aperto): su un runner effimero, dove
  nessun Apple ID è mai stato inserito, fallirebbe. Esportare e poi caricare con `xcrun altool`
  funziona con la sola chiave API, lascia l'IPA su disco (upload ripetibile senza ricompilare) e dà
  messaggi d'errore molto più leggibili. `notarytool` non c'entra: serve alla notarizzazione delle
  app **macOS** distribuite fuori dall'App Store.
- **Dove avviene la firma, e perché non nell'archive.** L'archive gira **senza firma**, con gli
  stessi identici flag dell'archive di `ios.yml` (che è verde): l'unico passo davvero costoso parte
  quindi da una ricetta già dimostrata su questo progetto. Certificato di distribuzione, profilo e
  firma sono tutti compito di `-exportArchive` (`signingStyle: automatic` +
  `-allowProvisioningUpdates` + chiave API). Si evitano così due trappole classiche della firma in
  CI: `CODE_SIGN_STYLE=Automatic` insieme a `CODE_SIGN_IDENTITY="Apple Distribution"` fa fallire
  l'archive con *«has conflicting provisioning settings … is automatically signed for development,
  but a conflicting code signing identity Apple Distribution has been manually specified»*; e la
  firma automatica di **sviluppo** per `generic/platform=iOS` pretende un profilo di sviluppo, che a
  sua volta pretende almeno un **dispositivo registrato** nel team (*«Your team has no devices from
  which to generate a provisioning profile»*) — su un account appena aperto non ce n'è nessuno, e il
  runner non è un iPhone.
- **Fallback automatico.** Se l'export dall'archivio non firmato dovesse fallire, lo stesso job
  ri-archivia da solo con **firma automatica ad hoc** (`CODE_SIGN_IDENTITY=-` +
  `AD_HOC_CODE_SIGNING_ALLOWED=YES` + `CODE_SIGN_STYLE=Automatic` + `DEVELOPMENT_TEAM`, la ricetta a
  cui la DTS di Apple rimanda per la CI, quella di Xcode Cloud: firma con la pseudo-identità `-`,
  quindi niente certificati, niente profili e niente dispositivi registrati, ma **con** gli
  entitlement già generati in fase di archive) e riprova l'export. La firma di distribuzione resta
  comunque compito di `-exportArchive`. Il riepilogo del run dice quale delle due strategie ha
  funzionato; il timeout del job è a 90 minuti proprio per coprire il caso di due archive.
- **Firma senza rompere il package SPM.** `project.yml` tiene la firma spenta per tutto il progetto
  (serve a `ios.yml`). Il workflow TestFlight **non** passa a `xcodebuild` le `CODE_SIGN_*` vere:
  qualsiasi impostazione sulla riga di comando vale per *tutti* i target del build, compresi
  `GymCore`/`GymUI`/`GymFeatures` del package locale, ed è il modo classico di farli fallire
  ("requires a development team", "profile doesn't match bundle id"). Passa invece cinque variabili
  `GYM_*` (usate solo dal fallback), che solo il target `Gym` traduce in impostazioni di firma
  (`CODE_SIGN_STYLE = $(GYM_CODE_SIGN_STYLE)` ecc.). Con i valori di default il comportamento è
  identico a prima, quindi `ios.yml` non cambia.
- **Numero di build**: secondi trascorsi dal 1° gennaio 2020 UTC (oggi ~2,1·10⁸). Sempre crescente,
  unico al secondo, e soprattutto indipendente da `github.run_number`, che è un contatore **per
  workflow**: quello di `ios.yml` e quello di `testflight.yml` si sovrapporrebbero. Resta un singolo
  intero sotto il limite di App Store Connect. La **versione marketing** arriva da `project.yml`
  (`MARKETING_VERSION`), oppure dal tag se il run parte da `vX.Y.Z`.
- **Requisiti del binario** verificati automaticamente: icona 1024×1024 **senza canale alpha** (lo
  step legge l'header del PNG), `CFBundleIconName` presente nel bundle costruito,
  `ITSAppUsesNonExemptEncryption = false`, `LSRequiresIPhoneOS`, `CFBundleDisplayName`, orientamento
  portrait, launch screen, versione/build coerenti. Non serve nessun `PrivacyInfo.xcprivacy`: l'app
  non usa API "required reason" (niente `UserDefaults`, niente date di modifica dei file, niente
  spazio su disco) e non ha SDK di terze parti.

### 4. Aggiungere i tester interni

I tester **interni** sono utenti del team App Store Connect: fino a 100 persone, 30 dispositivi a
testa, e ricevono la build **appena finita l'elaborazione**, senza nessuna revisione di Apple.

1. **Te stesso** sei già utente del team: non devi fare nulla.
2. **La seconda persona**: [Utenti e accessi](https://appstoreconnect.apple.com/access/users) → **+**
   → nome, cognome, email (dev'essere un **Apple Account** valido, la sua). Ruolo: **Developer** è
   sufficiente per fare da tester interno; spunta l'accesso all'app. Riceve un invito da accettare.
3. [TestFlight](https://appstoreconnect.apple.com/apps) → scheda **TestFlight** dell'app → *Test
   interno* → **+** su "Gruppi" → nome del gruppo (p.es. `Interni`) → aggiungi entrambi i tester →
   attiva **"Distribuisci automaticamente le build"**, così ogni nuovo upload parte da solo.
4. Sull'iPhone: installare l'app **TestFlight** dall'App Store, aprire l'email di invito (o fare
   *Riscatta* con il codice) e premere *Installa*. Gli aggiornamenti successivi arrivano lì dentro,
   con notifica.

Una nota: **"Cosa provare"** non è impostabile dalla riga di comando con i soli strumenti di Xcode.
Il testo passato con `-f note="…"` finisce nel riepilogo del run su GitHub: lo si copia una volta in
App Store Connect → TestFlight → build → *Cosa provare* (oppure si scrive una volta sola a livello di
gruppo e non ci si pensa più).

**Scadenza: 90 giorni.** Ogni build di TestFlight smette di funzionare 90 giorni dopo l'upload —
l'app installata si rifiuta di partire e chiede di aggiornare. È l'unico "rinnovo" richiesto, ed è
sei volte più comodo dei 7 giorni del sideload gratuito: basta rilanciare il workflow. Se una build
scade e non se ne carica un'altra, i dati **restano** sul telefono (l'app non viene disinstallata).

### 5. I cinque errori più probabili

| errore | dove compare | rimedio |
| --- | --- | --- |
| `No profiles for 'it.mpinformatica.gymapp' were found` / `No signing certificate "Apple Distribution" found` | step *Firma di distribuzione ed export* (dopo che anche il fallback ha fallito) | La chiave API non ha il ruolo **Admin** (senza cui non può creare certificato e profilo), oppure l'App ID del punto 1a non è stato registrato. Rigenera la chiave con ruolo Admin e riaggiorna `ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_KEY_P8`. |
| `Unable to authenticate` / `error -1011` / `401 Unauthorized` | step *Carica su App Store Connect* | Key ID o Issuer ID sbagliati (si scambiano facilmente: il Key ID è corto, l'Issuer ID è un UUID), oppure il `.p8` è stato incollato a mano perdendo gli a capo. Ricaricalo **da file**: `gh secret set ASC_KEY_P8 < AuthKey_XXXXXXXXXX.p8`. |
| `No suitable application records were found` / `Unable to find application` | step *Carica su App Store Connect* | Manca il record dell'app in App Store Connect (punto 1b) o il bundle id non coincide con `it.mpinformatica.gymapp`. |
| `The bundle version must be higher than the previously uploaded version` / `Redundant binary upload` | step *Carica su App Store Connect* | Quel numero di build è già stato usato: succede solo se si è caricato a mano qualcosa con un build number più alto. Rilancia il workflow (il numero è basato sull'orologio, quindi al run successivo è già più grande); se il problema resta, è stata caricata a mano una build con un numero enorme e va alzata la `MARKETING_VERSION` in `project.yml`. |
| `ITMS-90717: Invalid App Store Icon` (alpha) o `ITMS-90713: Missing CFBundleIconName` | step *checks* / *Controlla l'archivio* | Icona con trasparenza o asset catalog non compilato. Rigenera l'icona con `swift scripts/make_icon.swift` (lo script produce già un PNG opaco) e verifica che in `project.yml` resti `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. |

Se la build viene accettata ma **non compare** in TestFlight: è normale, l'elaborazione dura da 5 a
30 minuti; se dopo un'ora non c'è, controlla l'email dell'Account Holder, dove Apple spedisce gli
avvisi di binario rifiutato.

### Fonti

Verificate a settembre 2026:
[Apple — Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
(chiavi del team vs individuali, «Individual keys aren't able to use Provisioning endpoints»,
download del `.p8` una volta sola);
[Apple — Program roles](https://developer.apple.com/support/roles/) (tabella dei permessi: certificati
e profili di distribuzione solo ad Account Holder e Admin; *Upload builds* ad Account Holder, Admin e
App Manager);
[Apple — Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds);
[man page di `altool`](https://keith.github.io/xcode-man-pages/altool.1.html) (percorsi di ricerca del
`.p8` e `$API_PRIVATE_KEYS_DIR`) e di
[`xcodebuild`](https://keith.github.io/xcode-man-pages/xcodebuild.1.html)
(`-allowProvisioningUpdates`, `-authenticationKeyPath/ID/IssuerID`);
[FB9145847](https://openradar.appspot.com/FB9145847) (la destinazione `upload` di `-exportArchive`
non usa la chiave API);
[Apple Developer Forums — "How to make CI build with Xcode project with automatic
signing?"](https://developer.apple.com/forums/thread/756119) (la DTS rimanda alla ricetta di Xcode
Cloud: `CODE_SIGN_IDENTITY=-` + `AD_HOC_CODE_SIGNING_ALLOWED=YES` + `CODE_SIGN_STYLE=Automatic` +
`DEVELOPMENT_TEAM`, senza dispositivi registrati);
[Apple Developer Forums — conflicting provisioning settings](https://developer.apple.com/forums/thread/724582);
[Apple TN3187 — Migrating to the UIKit scene-based life cycle](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle);
[Apple — Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

---

## Installare l'IPA non firmata sull'iPhone (gratis, da macOS, senza Xcode)

L'IPA prodotta dalla CI **non è firmata**: da sola non si installa. La si firma sul Mac con il
proprio **Apple ID gratuito** (nessun Apple Developer Program da 99 €/anno).

### Strumento consigliato: Sideloadly

[Sideloadly](https://sideloadly.io/) (v0.60.0 a settembre 2026) è la scelta migliore su questo Mac:
supporta esplicitamente i Mac Apple Silicon **con SIP attivo**, non richiede Xcode, non richiede
iTunes (serve solo su Windows) e non richiede più il vecchio plug-in di Mail.

**Passo per passo (prima installazione):**

1. Scarica l'artifact `Gym-unsigned.ipa` dalla pagina del run in **Actions** su GitHub.
2. Installa Sideloadly dal sito ufficiale e aprilo.
3. Collega l'iPhone al Mac **via cavo**, sbloccalo e conferma "Autorizza questo computer".
4. Trascina `Gym-unsigned.ipa` nella finestra di Sideloadly.
5. Inserisci il tuo **Apple ID**. Con un Apple ID gratuito serve la password normale più il codice
   a 6 cifre della verifica in due fattori: le *password per app* non funzionano (richiedono un
   account sviluppatore a pagamento).
6. **Non modificare il Bundle ID** (`it.mpinformatica.gymapp`). Sideloadly offre di aggiungere un
   suffisso casuale: se lo fai, a ogni firma iOS vede un'app diversa e **perdi tutti i dati**.
7. Premi Start e attendi l'installazione.
8. Sull'iPhone: **Impostazioni → Generali → VPN e gestione dispositivo** → tocca il tuo Apple ID →
   **Autorizza**.
9. Apri l'app: iOS dirà che serve la Modalità sviluppatore. Vai in **Impostazioni → Privacy e
   sicurezza → Modalità sviluppatore**, attivala, **riavvia l'iPhone**, poi conferma con il codice
   di sblocco. La voce compare solo dopo che è stata installata un'app di sviluppo, ed è richiesta
   da iOS 16 in poi. Si fa una volta sola per dispositivo.

### Alternativa: AltStore Classic + AltServer

[AltStore](https://altstore.io/) installa sull'iPhone un'app-negozio che poi **rinnova da sola le
firme via Wi-Fi**, finché il Mac è acceso con AltServer in esecuzione: più comodo di ricollegare il
cavo ogni settimana. Richiede macOS 11+. Su macOS lo sviluppo è però meno attivo di Sideloadly (la
release 1.7.4 del marzo 2026 è solo Windows) e in alcune configurazioni compare ancora la richiesta
del plug-in di Mail.

Da valutare più avanti: **AltStore Classic 2.3** (in beta per i sostenitori Patreon) e
[SideStore](https://sidestore.io/) 0.6.4 rinnovano le firme **direttamente sul telefono**, senza
Mac; il setup iniziale richiede comunque un computer una volta sola.

> **AltStore PAL non c'entra**: è il marketplace alternativo UE previsto dal DMA, pensato per
> distribuire app al pubblico. Richiede un account sviluppatore a pagamento e la notarizzazione
> Apple. Per installare la *tua* app sul *tuo* telefono non serve.

### Limiti dell'Apple ID gratuito (validi nel 2026)

| limite | conseguenza pratica |
| --- | --- |
| firma valida **7 giorni** | dopo una settimana l'app non si apre più finché non la ri-firmi |
| massimo **3 app** sideloadate per Apple ID | AltStore, se lo usi, occupa uno dei tre slot |
| massimo **10 App ID ogni 7 giorni** | non creare bundle id nuovi a raffica |
| massimo **3 dispositivi** registrati | |
| **nessuna capability avanzata** | niente push remote, iCloud, App Groups, HealthKit |

Le notifiche **locali** (timer di recupero) funzionano: non sono una capability a pagamento.

### Rinnovo settimanale e cosa succede ai dati

L'app resta installata: scade solo la firma. Per rinnovarla si **reinstalla l'IPA sopra quella
esistente** (Sideloadly ha anche un refresh automatico in background).

**I dati sopravvivono** — quindi le schede, lo storico e le sessioni salvate in
`Application Support/GymApp/` restano — se e solo se valgono tutte e tre queste condizioni:

- stesso **Bundle ID** (`it.mpinformatica.gymapp`),
- stesso **Apple ID** usato per firmare (cambiare account cambia il Team ID e iOS rifiuta
  l'aggiornamento in place),
- installazione **sopra** l'app esistente, **senza disinstallarla prima**.

**I dati si perdono** se disinstalli l'app dalla home (iOS cancella l'intero container), se cambi
bundle id (incluso il suffisso casuale di Sideloadly) o se sei costretto a rimuovere e reinstallare
dopo una revoca del certificato.

Usa Sideloadly **0.60.0 o successiva**: le versioni precedenti, sui Mac Apple Silicon, in alcuni casi
reinstallavano l'app da zero invece di aggiornarla — con perdita dei dati.

**Rete di sicurezza**, da usare comunque: la funzione *Impostazioni → Esporta backup* dell'app
(prevista dalla SPEC §4) salva tutto in un unico file JSON. Fanne uno prima di ogni rinnovo. In
aggiunta, un backup cifrato dell'iPhone da Finder include anche i container delle app sideloadate.

### Fonti

Verificate a settembre 2026: [sideloadly.io](https://sideloadly.io/) e il relativo
[changelog](https://sideloadly.io/changelog.html) e [FAQ](https://sideloadly.io/faq.html);
[altstore.io](https://altstore.io/) e le [release notes di AltServer](https://faq.altstore.io/release-notes/altserver);
[release di SideStore](https://github.com/SideStore/SideStore/releases);
[Apple — confronto tra i tipi di account](https://developer.apple.com/support/compare-memberships/) e
[aggiornamento dei profili di provisioning](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/);
[immagini dei runner macOS di GitHub](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md);
[XcodeGen — ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).

---

## Crediti

- **Dati degli esercizi**: [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)
  — licenza **MIT**, © Hasan Emir Yıldırım.
- **Immagini e GIF degli esercizi**: **© Gym visual — https://gymvisual.com/**. I media **non** sono
  ridistribuiti in questo repository: il dataset contiene solo i percorsi e le immagini vengono
  caricate a runtime dall'upstream e messe in cache sul dispositivo. L'attribuzione è visibile nel
  dettaglio di ogni esercizio e in *Impostazioni → Crediti*.
- Icona dell'app: generata da [`scripts/make_icon.swift`](scripts/make_icon.swift).
