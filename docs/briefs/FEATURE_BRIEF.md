# Brief comune per gli sviluppatori delle schermate (Fase 2)

Sei uno sviluppatore SwiftUI senior con forte gusto per il design minimale. App iOS personale per la palestra, UI solo in italiano. Un project manager revisionerà compilando, leggendo il codice e GUARDANDO gli screenshot: la resa visiva conta quanto il codice.

## Leggi prima, per intero
1. `docs/DESIGN.md`: il **Principio guida "minimale, senza rumore"** e le regole vincolanti dell'utente prevalgono su tutto: un solo font (SF Pro di sistema), ZERO letter-spacing, MAI "—" o "–" in stringhe visibili o di accessibilità, sfondo bianco puro, card grigio chiarissimo senza ombre né bordi, accenti pastello (riempimenti `.fill` con contenuto `onFill`, linee/icone `.deep`), forme astratte `BlobGradient` solo dove previsto.
2. `docs/SPEC.md`: §1 vincoli, §4 modello dati, §5 schermate (la tua), e "Fuori scope".
3. `Sources/GymFeatures/README.md`: convenzioni OBBLIGATORIE (si legge solo `@Environment(AppEnvironment.self)`; mai `Date()`, sempre `app.now`; struttura cartelle; come aggiungere scene di screenshot).
4. L'API pubblica reale di `Sources/GymCore` (AppStore, Stats, modelli) e il catalogo componenti di `Sources/GymUI` (guarda anche `docs/preview/design-system.png`). Riusa i componenti esistenti: NON ricreare bottoni, card, chip, campi, grafici mini, tile media.

## Vincoli duri
- Niente Xcode su questo Mac: si verifica con `swift build` (macOS). Tutto deve compilare anche su macOS 14. API solo-iOS dentro `#if os(iOS)` minimi, scritti con cura estrema (non vengono type-checkati qui ma la CI li compila su iOS). Preferisci sempre API cross-platform.
- VIETATI: `#Preview`, SwiftData, XCTest, Swift Testing, dipendenze esterne, colori/font letterali nelle feature (solo token GymUI), `.shadow`, `.tracking`, `.kerning`, font serif/rounded/expanded, emoji nella UI.
- Swift 6 concurrency rigorosa, zero warning. iOS 17+. Dynamic Type, VoiceOver sulle azioni, target ≥ 44pt.
- Lavora SOLO nella tua area (indicata nel task). Non toccare GymCore, GymUI, Package.swift, App/, docs/ (tranne la scrittura dei PNG in docs/preview), né le cartelle delle altre feature: altri sviluppatori lavorano in parallelo. Se una build fallisce per file altrui a metà scrittura, riprova dopo un minuto; se persiste, segnalalo nel report. Se ti manca qualcosa in GymCore/GymUI NON aggirarlo con hack: fai il meglio possibile nella tua area e segnalalo nel report.
- In `Sources/GymSnapshots/Scenes.swift` puoi SOLO aggiungere/aggiornare le scene della tua feature (modifiche piccole e localizzate: è un file condiviso). Se ti servono dati mock aggiuntivi, aggiungili in un file nuovo `Sources/GymSnapshots/MockData+<Feature>.swift`.
- Non fare commit git.

## Metodo di lavoro obbligatorio
1. Progetta prima la schermata a parole chiedendoti per ogni elemento: "serve davvero adesso?". In caso di dubbio togli o sposta un livello sotto (menu "…", sheet, riga espandibile).
2. Implementa con file piccoli (una view per file quando cresce), stato locale con `@State`, logica di presentazione in piccoli tipi testabili, nessuna logica di dominio duplicata (sta in GymCore).
3. `swift build` pulito, poi `swift run GymSnapshots <filtro>` e **GUARDA i PNG** (leggi i file immagine): itera finché la schermata è davvero bella, ariosa, allineata, senza testo troncato, con stati vuoti curati. Controlla stato pieno, stato vuoto e, dove ha senso, dark.
4. Report finale conciso in italiano: file creati, scelte di design (cosa hai tolto e perché), scene di screenshot disponibili, rami solo-iOS non verificati, mancanze trovate in GymCore/GymUI, limiti noti.
