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
