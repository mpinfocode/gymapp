import Foundation
import GymCore

@MainActor
func runStoreChecks(_ h: Harness, repository: ExerciseRepository?) async {

    let directory = TempDirectory.make()
    defer { TempDirectory.remove(directory) }

    let clock = TestClock(Fixtures.date(2025, 3, 3, 18, 0)) // lunedì
    func makeStore(in url: URL) -> AppStore {
        AppStore(
            store: JSONFileStore(directory: url),
            exercises: repository,
            calendar: Fixtures.calendar,
            saveDelay: .milliseconds(50),
            now: clock.provider
        )
    }

    let store = makeStore(in: directory)

    // MARK: Primo avvio

    h.section("store · primo avvio senza scheda")

    h.check("prima di load() lo store è vuoto", store.programs.isEmpty && !store.isLoaded)
    await store.load()
    h.check("load() completata", store.isLoaded)
    h.check("nessun errore di caricamento: \(store.loadErrors)", store.loadErrors.isEmpty)
    h.check("libreria disponibile", store.exercises?.count == 1_324)

    h.check("nessuna scheda creata automaticamente", store.programs.isEmpty)
    h.check("nessuna scheda attiva", store.activeProgram == nil && store.settings.activeProgramID == nil)
    h.check("nessun allenamento proposto senza scheda", store.todaysWorkout() == .empty)
    h.check("nessuna sessione attiva al primo avvio", store.activeSession == nil)
    h.check("nessuno storico al primo avvio", store.sessions.isEmpty)
    h.check("nessuna rilevazione corporea al primo avvio", store.bodyEntries.isEmpty)
    await store.load() // seconda chiamata: deve essere un no-op
    h.check("load() è idempotente", store.programs.isEmpty && store.sessions.isEmpty)

    // Ricarica della libreria: serve alla UI quando il caricamento iniziale fallisce.
    let libraryReloaded = await store.reloadExercises()
    h.check("reloadExercises() riesce", libraryReloaded)
    h.check("libreria ancora completa dopo la ricarica", store.exercises?.count == 1_324)
    h.check("la ricarica non lascia errori: \(store.loadErrors)", store.loadErrors.isEmpty)
    h.check("la ricarica non tocca schede e storico", store.programs.isEmpty && store.sessions.isEmpty)
    h.check("la ricarica non tocca la sessione in corso", store.activeSession == nil)

    let emptyLibraryStore = AppStore(
        store: JSONFileStore(directory: directory),
        exercises: ExerciseRepository(exercises: []),
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(50),
        now: clock.provider
    )
    await emptyLibraryStore.load()
    h.check("libreria iniettata vuota", emptyLibraryStore.exercises?.count == 0)
    h.check("ricarica dal bundle riuscita", await emptyLibraryStore.reloadExercises())
    h.check("la ricarica rimpiazza la libreria", emptyLibraryStore.exercises?.count == 1_324)
    h.check("dopo la ricarica la ricerca funziona", !emptyLibraryStore.searchExercises(ExerciseFilter(query: "bench")).isEmpty)

    // MARK: Scheda d'esempio

    h.section("store · scheda d'esempio")

    let sample = store.loadSampleProgram()
    h.check("scheda d'esempio creata", store.programs.count == 1)
    h.check("scheda d'esempio attiva", store.activeProgram?.id == sample.id)
    h.check("nome", sample.name == "Push / Pull / Legs")
    h.check("modalità a rotazione", sample.mode == .rotation)
    h.check("6 settimane", sample.plannedWeeks == 6)
    h.check("inizia oggi", sample.startDate == clock.now)
    h.check("tre giorni", sample.days.map(\.name) == ["Push", "Pull", "Legs"])
    h.check("non archiviata", !sample.isArchived)

    if let library = store.exercises {
        let usedIDs = sample.days.flatMap(\.exerciseIDs)
        let unknown = usedIDs.filter { library.exercise(id: $0) == nil }
        h.check("tutti gli id della scheda d'esempio esistono nel dataset: \(unknown)", unknown.isEmpty)
        h.check("gli id dichiarati coincidono con quelli usati", Set(usedIDs) == Set(SampleProgram.exerciseIDs))
        h.check("Push inizia con la panca piana con bilanciere", library.exercise(id: sample.days[0].items[0].exerciseID)?.name == "barbell bench press")
        h.check("Pull inizia con lo stacco da terra", library.exercise(id: sample.days[1].items[0].exerciseID)?.name == "barbell deadlift")
        h.check("Pull contiene le trazioni", library.exercise(id: sample.days[1].items[1].exerciseID)?.name == "pull-up")
        h.check("Legs inizia con lo squat con bilanciere", library.exercise(id: sample.days[2].items[0].exerciseID)?.name == "barbell full squat")
        h.check("Push allena petto/spalle/braccia", sample.days[0].exerciseIDs.allSatisfy {
            ["chest", "shoulders", "upper arms"].contains(library.exercise(id: $0)?.category ?? "")
        })
        h.check("Legs allena gambe/polpacci/addome", sample.days[2].exerciseIDs.allSatisfy {
            ["upper legs", "lower legs", "waist"].contains(library.exercise(id: $0)?.category ?? "")
        })
    } else {
        h.fail("libreria non caricata: impossibile validare la scheda d'esempio")
    }

    h.check("la panca ha serie di riscaldamento", sample.days[0].items[0].warmupSets == 2)
    h.check("il superset di Push è dichiarato", sample.days[0].supersetGroups == [1])
    h.check("Legs contiene un esercizio a tempo", sample.days[2].items.contains { $0.measure.kind == .duration })
    h.check("l'esercizio a tempo dura 45 secondi", sample.days[2].items.last?.measure == .duration(seconds: 45))

    h.check("allenamento di oggi = primo giorno", store.todaysWorkout().programDay?.id == sample.days[0].id)
    h.check("stato della scheda", sample.statusText(asOf: clock.now, calendar: Fixtures.calendar) == "Settimana 1 di 6")

    // MARK: Ciclo di vita di una sessione

    h.section("store · ciclo completo di una sessione")

    let pushDay = sample.days[0]
    guard let session = store.startSession(programID: sample.id, dayID: pushDay.id) else {
        h.fail("avvio sessione fallito")
        return
    }

    h.check("sessione attiva impostata", store.activeSession?.id == session.id)
    h.check("la sessione eredita il nome del giorno", session.name == "Push")
    h.check("la sessione ricorda scheda e giorno", session.programID == sample.id && session.programDayID == pushDay.id)
    h.check("una riga per voce della scheda", session.entries.count == pushDay.items.count)
    h.check("ogni riga ricorda la voce di piano", session.entries.map(\.planItemID) == pushDay.items.map(\.id))
    h.check("warmup + serie di lavoro", session.entries.map(\.sets.count) == pushDay.items.map { $0.warmupSets + $0.targetSets })
    h.check("le prime serie sono di riscaldamento", session.entries[0].sets.prefix(2).allSatisfy { $0.kind == .warmup })
    h.check("le altre sono serie normali", session.entries[0].sets.dropFirst(2).allSatisfy { $0.kind == .normal })
    h.check("recupero preso dalla scheda", session.entries.first?.restSeconds == pushDay.items.first?.restSeconds)
    h.check("superset propagato in sessione", session.entries[3].supersetGroup == 1)
    h.check("senza storico e senza carico previsto i carichi restano vuoti", session.entries.allSatisfy { $0.sets.allSatisfy { $0.weightKg == nil } })
    h.check("le ripetizioni partono dal minimo del range", session.entries[0].sets.last?.reps == pushDay.items[0].measure.repsRange?.lowerBound)
    h.check("nessuna serie già spuntata", session.entries.allSatisfy { $0.sets.allSatisfy { !$0.isCompleted } })
    h.check("avviare due volte restituisce la stessa sessione", store.startSession(programID: sample.id, dayID: pushDay.id)?.id == session.id)

    guard let firstEntry = store.activeSession?.entries.first else {
        h.fail("prima riga assente")
        return
    }
    h.check("la prima riga è a ripetizioni", firstEntry.measureKind == .reps)

    // Log delle tre serie di lavoro sulla panca piana
    let workingSetIDs = firstEntry.sets.filter { $0.kind == .normal }.prefix(3).map(\.id)
    var records: [Set<Stats.RecordKind>] = []
    for (index, setID) in workingSetIDs.enumerated() {
        store.updateSet(id: setID, inEntry: firstEntry.id) { log in
            log.weightKg = 80
            log.reps = 8 - index
            log.rpe = 8.5
        }
        clock.advance(by: 180)
        records.append(store.completeSet(id: setID, inEntry: firstEntry.id))
    }

    // 80×8 + 80×7 + 80×6
    let expectedVolume: Double = 1_680
    h.check("serie completate registrate", store.activeSession?.entries.first?.completedSets == 3)
    h.checkClose("volume della sessione in corso", store.activeSession?.totalVolumeKg ?? 0, expectedVolume)
    h.check("primo PR assoluto rilevato", records.first?.contains(.maxWeight) == true)
    h.check("badge PR conservati in memoria", !store.liveRecords.isEmpty)
    h.check("la seconda serie allo stesso carico non è un nuovo PR", !records[1].contains(.maxWeight))
    h.check("nemmeno un nuovo PR di massimale stimato", !records[1].contains(.best1RM))

    // RPE: normalizzazione sulla scala 6…10
    store.updateSet(id: workingSetIDs[0], inEntry: firstEntry.id) { $0.rpe = 12 }
    h.check("RPE limitato a 10", store.activeSession?.entries.first?.sets.first { $0.id == workingSetIDs[0] }?.rpe == 10)
    store.updateSet(id: workingSetIDs[0], inEntry: firstEntry.id) { $0.rpe = 7.3 }
    h.check("RPE arrotondato a mezzo punto", store.activeSession?.entries.first?.sets.first { $0.id == workingSetIDs[0] }?.rpe == 7.5)
    h.check("scala RPE da 6 a 10", SetLog.rpeScale.first == 6 && SetLog.rpeScale.last == 10 && SetLog.rpeScale.count == 9)

    // Serie extra: copia l'ultima serie completata, non la riga vuota in coda
    if let extra = store.addSet(toEntry: firstEntry.id) {
        h.check("la serie aggiunta copia l'ultima completata", extra.weightKg == 80 && extra.reps == 6)
        h.check("serie aggiunta in coda", store.activeSession?.entries.first?.sets.count == firstEntry.sets.count + 1)
        store.removeSet(id: extra.id, fromEntry: firstEntry.id)
        h.check("serie rimossa", store.activeSession?.entries.first?.sets.count == firstEntry.sets.count)
    } else {
        h.fail("aggiunta serie fallita")
    }

    // Warmup: niente PR, niente volume
    if let warmup = store.addSet(toEntry: firstEntry.id, kind: .warmup) {
        store.updateSet(id: warmup.id, inEntry: firstEntry.id) { $0.weightKg = 200; $0.reps = 1 }
        let warmupRecords = store.completeSet(id: warmup.id, inEntry: firstEntry.id)
        h.check("il warmup non genera PR", warmupRecords.isEmpty)
        h.checkClose("il warmup non entra nel volume", store.activeSession?.entries.first?.volumeKg ?? 0, expectedVolume)
        store.uncompleteSet(id: warmup.id, inEntry: firstEntry.id)
        h.check("spunta annullata", store.activeSession?.entries.first?.sets.last?.isCompleted == false)
        store.removeSet(id: warmup.id, fromEntry: firstEntry.id)
    } else {
        h.fail("aggiunta warmup fallita")
    }

    // Esercizio a tempo aggiunto a mano
    if let timed = store.addExerciseToActiveSession("0464", targetSets: 2, measureKind: .duration) {
        h.check("riga a tempo", timed.measureKind == .duration)
        h.check("serie a tempo pre-compilate con la durata", timed.sets.allSatisfy { $0.durationSec == 30 && $0.reps == nil })
        h.check("riga aggiunta a mano senza voce di piano", timed.planItemID == nil)
        store.removeEntryFromActiveSession(id: timed.id)
    } else {
        h.fail("aggiunta esercizio a tempo fallita")
    }

    // Sostituzione (macchina occupata)
    let entriesBefore = store.activeSession?.entries.count ?? 0
    store.addExerciseToActiveSession("0662", targetSets: 2) // push-up
    h.check("esercizio aggiunto alla sessione", store.activeSession?.entries.count == entriesBefore + 1)
    if let added = store.activeSession?.entries.last {
        h.check("propone alternative per la sostituzione", !store.alternatives(for: "0662", limit: 5).isEmpty)
        store.replaceExerciseInActiveSession(entryID: added.id, with: "0308") // dumbbell fly
        h.check("esercizio sostituito", store.activeSession?.entries.last?.exerciseID == "0308")
        h.check("le serie sopravvivono alla sostituzione", store.activeSession?.entries.last?.sets.count == 2)
        store.setNote("presa stretta", forEntry: added.id)
        h.check("nota impostata", store.activeSession?.entries.last?.note == "presa stretta")
        store.setRestSeconds(45, forEntry: added.id)
        h.check("recupero impostato", store.activeSession?.entries.last?.restSeconds == 45)
        store.removeEntryFromActiveSession(id: added.id)
        h.check("esercizio rimosso", store.activeSession?.entries.count == entriesBefore)
    }

    let orderBefore = store.activeSession?.exerciseIDs ?? []
    store.moveEntriesInActiveSession(fromOffsets: IndexSet(integer: 0), toOffset: 2)
    let orderAfter = store.activeSession?.exerciseIDs ?? []
    h.check("riordino esercizi in sessione", orderAfter.first == orderBefore[1] && orderAfter[1] == orderBefore[0])
    h.check("il riordino non perde esercizi", Set(orderAfter) == Set(orderBefore))

    store.setSessionNotes("Buona giornata")

    // MARK: Ripristino della sessione attiva

    h.section("store · ripristino della sessione attiva")

    await store.flush()

    let restoreStore = makeStore(in: directory)
    await restoreStore.load()

    h.check("sessione attiva ripristinata", restoreStore.activeSession?.id == session.id)
    h.check("note della sessione ripristinate", restoreStore.activeSession?.notes == "Buona giornata")
    h.check("serie completate ripristinate", restoreStore.activeSession?.completedSets == 3)
    h.checkClose("volume ripristinato", restoreStore.activeSession?.totalVolumeKg ?? 0, expectedVolume)
    h.check("l'ordine degli esercizi è quello salvato", restoreStore.activeSession?.exerciseIDs == orderAfter)
    h.check("collegamento a scheda e giorno ripristinato",
            restoreStore.activeSession?.programID == sample.id && restoreStore.activeSession?.programDayID == pushDay.id)
    h.check("nessuna sessione archiviata prima di terminare", restoreStore.sessions.isEmpty)
    h.check("la scheda è stata ricaricata", restoreStore.programs.count == 1 && restoreStore.activeProgram?.id == sample.id)
    // I badge PR non stanno su disco ma si ricalcolano dalle serie già spuntate.
    h.check("i badge PR sono ricostruiti al riavvio", !restoreStore.liveRecords.isEmpty)
    h.check("i badge PR ricostruiti sono quelli del calcolo live", restoreStore.liveRecords == store.liveRecords)
    restoreStore.rebuildLiveRecords()
    h.check("ricostruzione idempotente", restoreStore.liveRecords == store.liveRecords)

    // MARK: Fine sessione

    h.section("store · fine sessione e archiviazione")

    clock.advance(by: 600)
    guard let finished = store.finishSession(notes: "fatto") else {
        h.fail("chiusura sessione fallita")
        return
    }

    h.check("nessuna sessione attiva dopo la fine", store.activeSession == nil)
    h.check("sessione archiviata", store.sessions.count == 1 && store.sessions.first?.id == finished.id)
    h.check("data di fine valorizzata", finished.endedAt != nil)
    h.check("nota finale salvata", finished.notes == "fatto")
    h.check("le serie non spuntate vengono scartate", finished.completedSets == 3)
    h.check("gli esercizi senza serie spuntate spariscono", finished.entries.count == 1)
    h.checkClose("volume finale", finished.totalVolumeKg, expectedVolume)
    h.check("durata coerente", finished.duration > 0)
    h.check("gli esercizi allenati finiscono nei recenti", store.settings.recentExerciseIDs.contains(finished.entries[0].exerciseID))
    h.check("chiudere due volte non fa nulla", store.finishSession() == nil)
    h.check("la rotazione avanza al giorno dopo", store.todaysWorkout().programDay?.id == sample.days[1].id)
    h.check("lo storico è filtrabile per scheda", store.sessions(ofProgram: sample.id).count == 1)

    await store.flush()

    // MARK: Riavvio con storico

    h.section("store · riavvio con storico")

    let reloaded = makeStore(in: directory)
    await reloaded.load()

    h.check("schede ricaricate", reloaded.programs.count == 1)
    h.check("scheda attiva ricordata", reloaded.activeProgram?.id == sample.id)
    h.check("storico ricaricato", reloaded.sessions.count == 1)
    h.checkClose("volume storico preservato", reloaded.sessions.first?.totalVolumeKg ?? 0, finished.totalVolumeKg)
    h.check("la sessione attiva è stata cancellata da disco", reloaded.activeSession == nil)
    h.check("impostazioni ricaricate", reloaded.settings.recentExerciseIDs == store.settings.recentExerciseIDs)
    h.check("nessun errore al riavvio: \(reloaded.loadErrors)", reloaded.loadErrors.isEmpty)
    h.check("record calcolabili dallo storico", reloaded.records(for: "0025")?.maxWeightKg == 80)

    // MARK: Pre-compilazione e hint di progressione

    h.section("store · pre-compilazione e progressione")

    clock.advance(by: 86_400 * 2)
    guard let second = reloaded.startSession(programID: sample.id, dayID: pushDay.id) else {
        h.fail("seconda sessione non avviata")
        return
    }
    let benchSets = second.entries[0].sets.filter { $0.kind == .normal }
    h.check("prima serie pre-compilata con l'ultimo carico", benchSets.first?.weightKg == 80)
    h.check("prima serie pre-compilata con le ultime reps", benchSets.first?.reps == 8)
    h.check("seconda serie segue la seconda di prima", benchSets[1].reps == 7)
    h.check("le serie oltre lo storico ripetono l'ultima", benchSets[3].reps == 6)
    // Riscaldamento: ~55% di 80 kg = 44 kg, arrotondato al passo del bilanciere → 45 kg.
    h.check("le serie di riscaldamento partono dal 55% arrotondato",
            second.entries[0].sets.prefix(2).allSatisfy { $0.kind == .warmup && $0.weightKg == 45 })
    h.check("il riscaldamento usa le reps minime del range",
            second.entries[0].sets.prefix(2).allSatisfy { $0.reps == pushDay.items[0].measure.repsRange?.lowerBound })
    h.check("gli esercizi senza storico restano vuoti", second.entries[1].sets.allSatisfy { $0.weightKg == nil })
    h.check("le serie pre-compilate non sono spuntate", second.entries.allSatisfy { $0.sets.allSatisfy { !$0.isCompleted } })

    if let previous = reloaded.previousPerformance(for: "0025") {
        h.check("prestazione precedente esposta dallo store", previous.sets.count == 3)
    } else {
        h.fail("prestazione precedente non disponibile")
    }
    h.check("nessun hint: il range non era stato completato", reloaded.progressionSuggestion(for: pushDay.items[0]) == nil)

    reloaded.discardSession()
    h.check("sessione scartata", reloaded.activeSession == nil)
    h.check("lo scarto non archivia nulla", reloaded.sessions.count == 1)

    // Una sessione che chiude il range fa comparire l'hint
    clock.advance(by: 86_400)
    if let third = reloaded.startSession(programID: sample.id, dayID: pushDay.id) {
        for setID in third.entries[0].sets.filter({ $0.kind == .normal }).map(\.id) {
            reloaded.updateSet(id: setID, inEntry: third.entries[0].id) { $0.weightKg = 80; $0.reps = 8 }
            reloaded.completeSet(id: setID, inEntry: third.entries[0].id)
        }
        clock.advance(by: 3_600)
        reloaded.finishSession()
        if let hint = reloaded.progressionSuggestion(for: pushDay.items[0]) {
            h.checkClose("hint di progressione: nuovo carico", hint.suggestedWeightKg, 82.5)
            h.check("hint di progressione: motivazione", hint.reason.contains("82,5 kg"))
            h.checkClose("hint di progressione: incremento da bilanciere", hint.incrementKg, 2.5)
        } else {
            h.fail("nessun hint dopo aver completato il range")
        }
    } else {
        h.fail("terza sessione non avviata")
    }

    // Sessione libera senza nulla di registrato
    let free = reloaded.startFreeSession()
    h.check("allenamento libero senza scheda", free.programID == nil && free.name == "Allenamento libero")
    h.check("allenamento libero parte vuoto", free.entries.isEmpty)
    h.check("chiudere una sessione vuota non la archivia", reloaded.finishSession() == nil)
    h.check("storico invariato", reloaded.sessions.count == 2)

    // MARK: CRUD schede

    h.section("store · CRUD schede")

    let custom = reloaded.createProgram(name: "Forza", plannedWeeks: 4, mode: .weekdays)
    h.check("scheda creata", reloaded.programs.count == 2)
    h.check("la nuova scheda diventa attiva", reloaded.activeProgram?.id == custom.id)
    h.check("la precedente finisce in archivio", reloaded.program(id: sample.id)?.isArchived == true)
    h.check("l'archivio la contiene", reloaded.archivedPrograms.contains { $0.id == sample.id })

    let dayA = reloaded.addDay(name: "Giorno A", weekday: .monday, toProgram: custom.id)
    let dayB = reloaded.addDay(name: "Giorno B", weekday: .thursday, toProgram: custom.id)
    h.check("giorni aggiunti", reloaded.program(id: custom.id)?.days.map(\.name) == ["Giorno A", "Giorno B"])

    reloaded.addItem(exerciseID: "0043", toDay: dayA.id, inProgram: custom.id, targetSets: 5, measure: .reps(min: 3, max: 5))
    reloaded.addItems(exerciseIDs: ["0032", "0025"], toDay: dayA.id, inProgram: custom.id)
    h.check("esercizi aggiunti al giorno", reloaded.program(id: custom.id)?.day(id: dayA.id)?.exerciseIDs == ["0043", "0032", "0025"])
    h.check("il recupero di default arriva dalle impostazioni",
            reloaded.program(id: custom.id)?.day(id: dayA.id)?.items.first?.restSeconds == reloaded.settings.defaultRestSeconds)

    reloaded.moveItems(inDay: dayA.id, inProgram: custom.id, fromOffsets: IndexSet(integer: 2), toOffset: 0)
    h.check("esercizi riordinati", reloaded.program(id: custom.id)?.day(id: dayA.id)?.exerciseIDs == ["0025", "0043", "0032"])

    if var item = reloaded.program(id: custom.id)?.day(id: dayA.id)?.items.first {
        item.targetWeightKg = 100
        item.measure = .duration(seconds: 60)
        reloaded.updateItem(item, inDay: dayA.id, inProgram: custom.id)
        let updated = reloaded.program(id: custom.id)?.day(id: dayA.id)?.items.first
        h.check("voce aggiornata", updated?.targetWeightKg == 100 && updated?.measure == .duration(seconds: 60))
        reloaded.removeItem(id: item.id, fromDay: dayA.id, inProgram: custom.id)
        h.check("voce rimossa", reloaded.program(id: custom.id)?.day(id: dayA.id)?.exerciseIDs == ["0043", "0032"])
    }

    reloaded.moveDays(inProgram: custom.id, fromOffsets: IndexSet(integer: 1), toOffset: 0)
    h.check("giorni riordinati", reloaded.program(id: custom.id)?.days.map(\.name) == ["Giorno B", "Giorno A"])

    reloaded.editDay(id: dayB.id, inProgram: custom.id) { $0.name = "Giorno B1"; $0.weekday = .saturday }
    h.check("giorno rinominato e riassegnato", reloaded.program(id: custom.id)?.day(id: dayB.id)?.weekday == .saturday)

    reloaded.editProgram(id: custom.id) { $0.name = "Forza 2" }
    h.check("scheda rinominata", reloaded.program(id: custom.id)?.name == "Forza 2")
    h.check("updatedAt aggiornato", (reloaded.program(id: custom.id)?.updatedAt ?? .distantPast) >= custom.updatedAt)

    // La modalità a giorni fissi propone il giorno corretto
    h.check("giorni fissi: sabato → Giorno B1",
            reloaded.todaysWorkout(on: Fixtures.date(2025, 3, 8)).programDay?.name == "Giorno B1")
    h.check("giorni fissi: martedì → riposo", reloaded.todaysWorkout(on: Fixtures.date(2025, 3, 4)).isRest)

    if let copy = reloaded.duplicateProgram(id: custom.id) {
        h.check("scheda duplicata con nuovo id", copy.id != custom.id)
        h.check("nome della copia", copy.name == "Forza 2 (copia)")
        h.check("la copia non è attiva se non richiesto", reloaded.activeProgram?.id == custom.id)
        h.check("giorni duplicati con nuovi id", copy.days.count == 2 && !copy.days.contains { $0.id == dayA.id || $0.id == dayB.id })
        h.check("la copia mantiene gli esercizi", copy.days.contains { !$0.items.isEmpty })
        h.check("la copia parte da oggi", copy.startDate == clock.now)
        reloaded.deleteProgram(id: copy.id)
        h.check("copia eliminata", reloaded.programs.count == 2)
    } else {
        h.fail("duplicazione fallita")
    }

    reloaded.activate(programID: sample.id)
    h.check("riattivazione dall'archivio", reloaded.activeProgram?.id == sample.id)
    h.check("la riattivazione toglie l'archiviazione", reloaded.program(id: sample.id)?.isArchived == false)
    h.check("la precedente attiva viene archiviata", reloaded.program(id: custom.id)?.isArchived == true)

    reloaded.archiveProgram(id: sample.id)
    h.check("archiviare la scheda attiva lascia senza scheda", reloaded.activeProgram == nil)
    h.check("senza scheda attiva non c'è allenamento proposto", reloaded.todaysWorkout() == .empty)

    let sessionsBefore = reloaded.sessions.count
    reloaded.deleteProgram(id: sample.id)
    h.check("scheda eliminata", reloaded.programs.count == 1)
    h.check("eliminare una scheda NON tocca lo storico", reloaded.sessions.count == sessionsBefore)
    reloaded.deleteProgram(id: UUID())
    h.check("eliminare una scheda inesistente non rompe nulla", reloaded.programs.count == 1)

    // MARK: Rilevazioni corporee

    h.section("store · rilevazioni corporee")

    let firstEntryID = reloaded.addBodyEntry(date: Fixtures.date(2025, 3, 1), weightKg: 80.0, measurementsCm: [.waist: 86])
    reloaded.addBodyEntry(date: Fixtures.date(2025, 3, 15), weightKg: 79.2, bodyFatPct: 15.0, waterPct: 57.5, measurementsCm: [.waist: 85])
    h.check("rilevazioni ordinate dalla più recente", reloaded.bodyEntries.map(\.date) == [Fixtures.date(2025, 3, 15), Fixtures.date(2025, 3, 1)])
    h.checkClose("ultima rilevazione", reloaded.latestBodyEntry?.weightKg ?? 0, 79.2)
    h.check("rilevazione vuota non viene salvata", reloaded.addBodyEntry(date: Date()) == nil)
    h.check("storico invariato", reloaded.bodyEntries.count == 2)

    h.checkClose("ultimo peso noto", reloaded.latestBodyValue(of: .weight)?.value ?? 0, 79.2)
    h.checkClose("ultima acqua nota", reloaded.latestBodyValue(of: .water)?.value ?? 0, 57.5)
    h.check("metrica mai registrata", reloaded.latestBodyValue(of: .muscleMass) == nil)
    h.check("serie storica del peso", reloaded.bodySeries(of: .weight).count == 2)
    if let change = reloaded.bodyChange(of: .weight, since: Fixtures.date(2025, 3, 1)) {
        h.checkClose("variazione del peso dall'inizio", change.delta, -0.8, tolerance: 0.000_1)
    } else {
        h.fail("variazione del peso non calcolata")
    }
    if let change = reloaded.bodyChange(of: .measure(.waist), since: Fixtures.date(2025, 3, 1)) {
        h.checkClose("variazione della vita", change.delta, -1)
    } else {
        h.fail("variazione della vita non calcolata")
    }

    if var updated = firstEntryID {
        updated.weightKg = 80.5
        updated[.chest] = 104
        reloaded.updateBodyEntry(updated)
        h.checkClose("rilevazione aggiornata", reloaded.bodyEntries.last?.weightKg ?? 0, 80.5)
        h.check("misura aggiunta in modifica", reloaded.bodyEntries.last?[.chest] == 104)

        updated.weightKg = nil
        updated.measurementsCm = [:]
        reloaded.updateBodyEntry(updated)
        h.check("svuotare una rilevazione la elimina", reloaded.bodyEntries.count == 1)
    }
    reloaded.deleteBodyEntry(id: reloaded.bodyEntries[0].id)
    h.check("rilevazione eliminata", reloaded.bodyEntries.isEmpty)

    // MARK: Impostazioni

    h.section("store · impostazioni")

    h.check("non preferito all'inizio", !reloaded.isFavorite("0043"))
    h.check("toggle accende il preferito", reloaded.toggleFavorite("0043"))
    h.check("preferito registrato", reloaded.isFavorite("0043"))
    h.check("toggle spegne il preferito", !reloaded.toggleFavorite("0043"))
    reloaded.toggleFavorite("0025")
    reloaded.updateSettings { $0.unit = .lb; $0.defaultRestSeconds = 120; $0.displayName = "Fra" }
    h.check("impostazioni modificate", reloaded.settings.unit == .lb && reloaded.settings.defaultRestSeconds == 120)
    reloaded.markRecent("0652")
    h.check("recenti aggiornati", reloaded.settings.recentExerciseIDs.first == "0652")

    // MARK: Statistiche esposte

    h.section("store · statistiche esposte")

    h.check("riepiloghi settimanali", !reloaded.weeklySummaries().isEmpty)
    h.check("le serie sono attribuite alla categoria", (reloaded.weeklySummaries().first?.setsByCategory["chest"] ?? 0) > 0)
    h.check("streak calcolata dal 'now' iniettato", reloaded.weekStreak() >= 1)
    h.check("griglia attività", reloaded.activityGrid(days: 30).count == 30)
    h.check("serie storica per esercizio", !reloaded.series(for: "0025").isEmpty)
    h.check("riepilogo settimana corrente", reloaded.currentWeekSummary().weekStart == Stats.startOfWeek(for: clock.now, calendar: Fixtures.calendar))

    if let toDelete = reloaded.sessions.first {
        reloaded.deleteSession(id: toDelete.id)
        h.check("sessione eliminata dallo storico", reloaded.sessions.count == sessionsBefore - 1)
    }

    await reloaded.flush()
    h.check("nessun errore di scrittura: \(reloaded.saveError ?? "-")", reloaded.saveError == nil)

    // MARK: Progressione a corpo libero

    h.section("store · progressione a corpo libero")

    // Le trazioni non hanno carico: le serie non entrano nelle "serie di lavoro",
    // quindi lo store deve cercare l'ultima sessione fra le serie registrate.
    let bodyweightDirectory = TempDirectory.make()
    defer { TempDirectory.remove(bodyweightDirectory) }
    let bodyweightStore = makeStore(in: bodyweightDirectory)
    await bodyweightStore.load()

    let calisthenics = bodyweightStore.createProgram(name: "Corpo libero")
    let pullDay = bodyweightStore.addDay(name: "Trazioni", toProgram: calisthenics.id)
    // "0652" = pull-up, attrezzo "body weight".
    let pullItem = bodyweightStore.addItem(
        exerciseID: "0652",
        toDay: pullDay.id,
        inProgram: calisthenics.id,
        targetSets: 3,
        measure: .reps(min: 6, max: 10)
    )

    h.check("senza storico nessun hint a corpo libero", bodyweightStore.progressionSuggestion(for: pullItem) == nil)

    if let pullSession = bodyweightStore.startSession(programID: calisthenics.id, dayID: pullDay.id) {
        let entry = pullSession.entries[0]
        let normalSets = entry.sets.filter { $0.kind == .normal }
        h.check("serie a corpo libero senza carico", normalSets.allSatisfy { $0.weightKg == nil })
        for setID in normalSets.map(\.id) {
            bodyweightStore.updateSet(id: setID, inEntry: entry.id) { $0.weightKg = nil; $0.reps = 10 }
            bodyweightStore.completeSet(id: setID, inEntry: entry.id)
        }
        clock.advance(by: 3_600)
        let archived = bodyweightStore.finishSession()
        h.check("sessione a corpo libero archiviata", archived != nil)
        h.check("le serie senza carico non sono serie di lavoro",
                Stats.workingSets(for: "0652", in: archived ?? pullSession).isEmpty)
        h.check("le serie senza carico restano serie registrate",
                Stats.loggedSets(for: "0652", in: archived ?? pullSession).count == normalSets.count)

        if let hint = bodyweightStore.progressionSuggestion(for: pullItem) {
            h.check("trazioni: lo store propone le ripetizioni", hint.kind == .reps)
            h.check("trazioni: una ripetizione in più", hint.suggestedReps == 11)
            h.checkClose("trazioni: nessun incremento di carico", hint.incrementKg, 0)
            h.check("trazioni: motivazione senza kg", !hint.reason.contains("kg"))
        } else {
            h.fail("nessun hint di ripetizioni dopo una sessione di trazioni al massimo del range")
        }
    } else {
        h.fail("sessione di trazioni non avviata")
    }

    await bodyweightStore.flush()

    // MARK: Debounce

    h.section("store · debounce del salvataggio")

    let debounceDirectory = TempDirectory.make()
    defer { TempDirectory.remove(debounceDirectory) }
    let debounceFileStore = JSONFileStore(directory: debounceDirectory)
    let debounced = AppStore(
        store: debounceFileStore,
        exercises: repository,
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(300),
        now: clock.provider
    )
    await debounced.load()

    for index in 0..<20 { debounced.createProgram(name: "Scheda \(index)") }
    h.check("le mutazioni sono immediate in memoria", debounced.programs.count == 20)

    await debounced.flush()
    do {
        let persisted = try await debounceFileStore.load([Program].self, from: .programs)
        h.check("dopo flush() il disco è allineato", persisted?.count == 20)
    } catch {
        h.fail("lettura dopo debounce fallita: \(error)")
    }

    // La sessione attiva invece è scritta subito, senza aspettare il debounce
    let immediate = debounced.startFreeSession(name: "Immediata")
    try? await Task.sleep(for: .milliseconds(120))
    do {
        let persisted = try await debounceFileStore.load(WorkoutSession.self, from: .activeSession)
        h.check("la sessione attiva è salvata subito, prima del debounce", persisted?.id == immediate.id)
    } catch {
        h.fail("lettura sessione attiva fallita: \(error)")
    }
    debounced.discardSession()
    await debounced.flush()
    h.check("scartare la sessione cancella il file", await !debounceFileStore.exists(.activeSession))
}
