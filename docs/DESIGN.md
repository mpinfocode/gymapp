# GymApp — Direzione di design

Riferimenti studiati su Mobbin (iOS): **Future Pro**, **MacroFactor**, **pillowtalk** (+ Hevy / Bevel / Ladder solo per il pattern della tabella serie).
L'obiettivo NON è copiare ma fondere tre idee in un linguaggio coerente, calmo e premium. Niente look "app fitness aggressiva" (no neon, no nero+giallo, no maiuscole urlate ovunque).

## Principio guida (dell'utente, prevale su tutto il resto): minimale, senza rumore

L'app deve essere **essenziale e silenziosa**. In caso di dubbio, togliere.
- **Una cosa principale per schermata.** Tutto ciò che non serve all'azione del momento sparisce o va un livello sotto (dettaglio, menu "…", sheet).
- **Niente decorazione gratuita**: niente emoji, badge, coriandoli, streak urlate, punti esclamativi, icone accanto a ogni etichetta, bordi e ombre sovrapposti. Il colore compare solo dove porta significato (stato fatto/attivo, una metrica). Il gradiente sfocato è l'unico elemento espressivo e si usa con parsimonia: hero di Oggi, card della scheda, sfondo della sessione. Mai nelle liste.
- **Pochi elementi, molto spazio bianco.** Card solo quando raggruppano davvero; altrimenti testo su sfondo. Massimo due pesi tipografici per schermata, massimo un bottone primario visibile.
- **Testi brevi.** Etichette di una o due parole, nessuna frase motivazionale, nessun sottotitolo che ripete il titolo. Numeri grandi, unità piccole.
- **Progressive disclosure.** Le funzioni avanzate (RPE, tipo serie, superset, note, sostituisci, serie di riscaldamento) esistono ma sono nascoste finché non servono: long-press, menu "…", riga espandibile. Il percorso base in palestra è: vedi carico e ripetizioni, tocca ✓.
- **Home corta**: allenamento di oggi, settimana, e basta. Niente feed, niente riepiloghi ridondanti; lo storico sta in Progressi.
- **Progressi sobri**: poche card scelte (allenamenti, volume, peso corporeo, misure, record), non una parete di grafici.
- **Animazioni discrete** e funzionali; nessun suono.

## Cosa prendiamo da ciascuna

### Future Pro → struttura e tono della Home, tab bar, liste esercizi
- Sfondo **bianco puro** (vedi Sistema), card con raggio ampio (24-28) in grigio chiarissimo, senza ombra.
- Saluto grande ("Buongiorno, Francesco"), titoli di sezione semibold ("Oggi", "Questa settimana", "Riepilogo settimanale").
- **Hero card "Oggi"** alta (~360pt), full-bleed con testo in basso a sinistra (titolo + "45 min · 6 esercizi"), variante "Giorno di riposo", variante completata con numero gigante (es. volume) + durata.
- Striscia settimana Lun–Dom dentro una card, giorno corrente = cerchio pieno colore accento.
- Righe-pillola: icona + titolo + dettaglio a destra + chevron. Coppie di bottoni pillola secondari ("Modifica piano" / "Vedi storico").
- Barre di avanzamento spesse, arrotondate, nere su grigio chiaro (Riepilogo settimanale).
- **Tab bar flottante a capsula** con materiale traslucido, tab selezionata evidenziata da una pillola più scura dietro icona+label.
- Lista esercizi: thumbnail quadrata arrotondata (raggio 12) a sinistra, nome, sotto-riga grigia; check verde sovrapposto alla thumbnail se completato.

### MacroFactor → Progressi / dashboard
- Header: data piccola maiuscola ("VENERDÌ 18 SETTEMBRE", senza spaziatura lettere) + titolo **heavy maiuscolo** ("PROGRESSI"), stesso font di sistema.
- Sezioni con titolo bold + "Vedi tutto" sottolineato a destra.
- **Griglia 2 colonne di mini-card**: titolo, sottotitolo grigio ("Ultimi 7 giorni"), mini grafico (linea con punti, barre, o griglia-abitudini 30 giorni a quadratini), divisore sottile, valore grande + unità piccola + chevron.
- Un colore per metrica (viola = peso corporeo, arancio = volume, verde = costanza, blu = allenamenti, rosa = PR).
- Segmented control a capsula nero/bianco; pager orizzontale con puntini per la card grande in alto.
- Numeri sempre con cifre monospaziate/tabellari.

### pillowtalk → sessione attiva, hero, momenti "emotivi"
- Superfici **scure immersive** con **gradienti sfocati organici** (mesh/blur di 2–3 macchie di colore che si muovono lentissime), card enormi con raggio 36–40 che si impilano in verticale.
- Tipografia **tutta minuscola**, leggera, grande, per i momenti guida ("pronto per iniziare?", "recupera", "ottimo lavoro"). Chip-etichetta in alto a sinistra della card (capsula traslucida con icona + testo minuscolo).
- Tris di azioni circolari traslucide in basso con label minuscola sotto (nella sessione: "−15s · salta · +15s", oppure "note · storico · sostituisci").
- Bottone "+" circolare flottante.
- Calendario a pallini con "blob" sfumati nei giorni attivi (riusare per il mese in Progressi/Storico in dark).
- Ogni scheda (routine) ha un **gradiente proprio** generato da un seed → lo stesso gradiente identifica la scheda in Home, in Schede e nella sessione.

## Sistema

**Tema**: chiaro di default per Oggi / Esercizi / Schede / Progressi (le GIF del dataset hanno sfondo bianco e si integrano bene). **Sessione attiva e riepilogo sempre scuri**, a prescindere dal sistema. Supportare comunque la dark mode di sistema per le altre schermate (token semantici, mai colori hardcoded nelle feature).

**GIF ed immagini esercizi**: sempre dentro una *tile bianca* con raggio 12–20 e padding interno, anche in dark. Sorgente 180×180: non ingrandire oltre ~240pt; nel dettaglio centrarla in una tile grande invece di stirarla.

**Sfondo (regola dell'utente, vincolante)**: in tema chiaro lo sfondo delle pagine è **bianco puro #FFFFFF**, piatto: niente gradiente, niente grigio o lavanda. Poiché lo sfondo è bianco, le card si distinguono con un riempimento grigio chiarissimo neutro (`surface` ≈ #F5F5F7) **senza ombra e senza bordo**; gli elementi sopra una card (`surfaceElevated`) tornano bianchi. Le tile dei media restano bianche: su sfondo bianco prendono un bordo hairline `separator`, dentro una card grigia nessun bordo. Tab bar flottante: materiale chiaro con bordo hairline. In dark: sfondo nero puro #000000 e `surface` ≈ #1C1C1E.

**Colori (token)**: `background` (bianco puro / nero puro), `surface`, `surfaceElevated`, `textPrimary/Secondary/Tertiary`, `separator`, `accent` (**pastello**, vedi sotto; solo per stati "fatto/attivo"), `ink` (quasi nero, per bottoni primari e barre), palette metriche (viola/arancio/verde/blu/rosa), palette gradienti schede (8 combinazioni curate, calde e fredde).

**Accenti pastello (regola dell'utente, vincolante)**: tutti i colori d'accento sono **pastello**: morbidi, desaturati, luminosi, mai saturi o neon. `accent` = verde salvia/menta pastello; palette metriche = lilla, pesca, menta, azzurro polvere, rosa cipria. Sul bianco i pastello si usano come **riempimenti** (barre, celle, sfondi di riga completata, anello del timer) con testo/icone in `ink` sopra; per linee sottili di grafico o testo colorato usare la variante più profonda dello stesso pastello (`.deep`) così resta leggibile (contrasto AA). Mai testo bianco su pastello.

**Forme astratte (piacciono all'utente: mantenerle)**: i gradienti organici sfocati di `BlobGradient` (macchie morbide che respirano) sono la firma visiva dell'app e restano, con palette tutte pastello. Compaiono solo in: hero di Oggi, card della scheda, sfondo della sessione attiva e del riepilogo. Mai nelle liste o come decorazione ripetuta.

**Tipografia (regole dell'utente, vincolanti)**: **un solo font in tutta l'app: SF Pro di sistema (`.system`, design `.default`)**. Vietati: serif/New York, `.rounded`, `.monospaced`, `fontWidth(.expanded)` o qualsiasi accoppiata di font. **Vietata la spaziatura tra lettere**: mai `.tracking()` / `.kerning()`, nemmeno sulle overline maiuscole. La gerarchia si ottiene SOLO con dimensione, peso (light → heavy), colore e maiuscole/minuscole: saluto = 34 semibold; titoli sezione = 22 semibold; titolo pagina Progressi = 30 heavy maiuscolo; overline = 12 semibold maiuscolo colore secondario; "whisper" pillowtalk = grande, minuscolo, weight light. Numeri: `monospacedDigit()` è ammesso (stesso font, solo cifre tabellari).

**Punteggiatura nella UI (vincolante)**: **mai il trattino lungo "—" (em-dash) né "–" (en-dash) in nessuna stringa visibile**. Usare virgola, due punti, punto, "·" come separatore, e "-" solo nei range numerici (es. "8-12"). Valore mancante = "·" oppure campo vuoto, mai "—". L'attribuzione media si mostra come "© Gym visual · https://gymvisual.com/".

**Forma**: raggi 12 / 20 / 28 / 40. Bottoni primari = capsula alta 56 full-width, `ink` su chiaro, bianca su scuro. Spaziatura base 4; margini pagina 20.

**Movimento**: spring morbide (response ~0.45, damping ~0.85); completare una serie = check che "scatta" + haptic; timer recupero = anello che si svuota; gradienti che respirano (≤ 0.1 Hz). Rispettare Riduci movimento.

**Tabella serie** (sessione): colonne SERIE · PRECEDENTE · KG · REPS · ✓; riga completata = sfondo tinta accento tenue; celle input = capsule con bordo; tastierino numerico con barra "Fatto"; la riga attiva è evidenziata. Target tap ≥ 44pt — si usa con le mani sudate tra una serie e l'altra: **poche cose, grandi**.

**Copy**: italiano, tono calmo e diretto, minuscolo nei momenti pillowtalk, mai punti esclamativi a raffica. Empty state sempre con un'azione.

**Accessibilità**: Dynamic Type fino a XXL senza rotture, contrasto AA, label VoiceOver su icone e celle serie.
