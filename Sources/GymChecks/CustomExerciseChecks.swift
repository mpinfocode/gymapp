import Foundation
import GymCore

/// Esercizi personalizzati end to end (SPEC §2, punto 5): creazione, ricerca unificata,
/// uso in scheda e sessione, statistiche, eliminazione senza rompere lo storico,
/// persistenza e backup.
@MainActor
func runCustomExerciseChecks(_ h: Harness, repository: ExerciseRepository?) async {

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
    await store.load()

    // MARK: Creazione

    h.section("personalizzati · creazione")

    h.check("all'inizio non ce ne sono", store.customExercises.isEmpty)

    guard let facePull = store.createCustomExercise(
        name: "Face pull",
        category: "shoulders",
        equipment: "cable",
        target: "rear deltoids",
        secondaryMuscles: ["upper back", "traps"],
        notes: "Corda alta, gomiti larghi, fermo un secondo"
    ) else {
        h.fail("creazione di un esercizio personalizzato fallita")
        return
    }

    h.check("id con prefisso custom-", facePull.id.hasPrefix("custom-"))
    h.check("id univoco (uuid)", facePull.id.count == "custom-".count + 36)
    h.check("marcato come personalizzato", facePull.isCustom)
    h.check("non è eliminato", !facePull.isDeleted && facePull.isSelectable)
    h.check("nessuna GIF", facePull.gifURL == nil)
    h.check("nessuna immagine", facePull.imageURL == nil)
    h.check("nessuna attribuzione Gym visual", facePull.attribution.isEmpty)
    h.check("nessuna istruzione", facePull.steps.isEmpty)
    h.check("nota conservata", facePull.notes.contains("gomiti larghi"))
    h.check("nome capitalizzato per la UI", facePull.displayName == "Face Pull")
    h.check("zona colpita dedotta dal target", facePull.muscleGroupKind == .shoulders)
    h.check("in collezione", store.customExercises.map(\.id) == [facePull.id])

    h.check("nome vuoto rifiutato", store.createCustomExercise(name: "   ") == nil)
    h.check("gli spazi attorno al nome vengono tolti",
            store.createCustomExercise(name: "  Bulgarian split squat  ")?.name == "Bulgarian split squat")

    guard let bulgarian = store.customExercises.first(where: { $0.name == "Bulgarian split squat" }) else {
        h.fail("secondo personalizzato non creato")
        return
    }
    _ = store.editCustomExercise(
        id: bulgarian.id,
        category: "upper legs",
        equipment: "dumbbell",
        target: "quads",
        notes: "Piede dietro sulla panca"
    )
    h.check("modifica applicata", store.customExercise(id: bulgarian.id)?.target == "quads")
    h.check("modifica conserva l'id", store.customExercise(id: bulgarian.id)?.id == bulgarian.id)
    h.check("modifica conserva il nome se non lo si cambia", store.customExercise(id: bulgarian.id)?.name == "Bulgarian split squat")
    h.check("ordinati per nome", store.customExercises.map(\.name) == ["Bulgarian split squat", "Face pull"])
    h.check("le correzioni non toccano i personalizzati",
            store.customExercise(id: bulgarian.id)?.target == "quads")

    // MARK: Lookup e ricerca unificati

    h.section("personalizzati · lookup e ricerca")

    h.check("lookup per id", store.exercise(id: facePull.id)?.name == "Face pull")
    h.check("lookup della libreria dallo stesso metodo", store.exercise(id: "0025")?.name == "barbell bench press")
    h.check("lookup di un id inesistente", store.exercise(id: "custom-nope") == nil)
    h.check("libreria di ricerca = 1.324 + 2", store.searchableLibrary?.count == 1_326)
    h.check("indice completo per le statistiche", store.allExercisesByID().count == 1_326)

    let byName = store.searchExercises(ExerciseFilter(query: "face pull"))
    h.check("ricerca per nome trova il personalizzato", byName.first?.id == facePull.id)
    h.check("ricerca italiana trova il personalizzato",
            store.searchExercises(ExerciseFilter(query: "cavi")).contains { $0.id == facePull.id })
    h.check("ricerca sulla nota del personalizzato",
            store.searchExercises(ExerciseFilter(query: "gomiti")).contains { $0.id == facePull.id })
    h.check("filtro per zona include i personalizzati",
            store.searchExercises(ExerciseFilter(muscleGroups: [.shoulders])).contains { $0.id == facePull.id })
    h.check("filtro per attrezzo include i personalizzati",
            store.searchExercises(ExerciseFilter(equipment: ["cable"])).contains { $0.id == facePull.id })

    let facets = store.exerciseFacets()
    h.check("facet: totale comprende i personalizzati", facets.total == 1_326)
    h.check("facet zone: somma comprende i personalizzati",
            facets.muscleGroups.reduce(0) { $0 + $1.count } == 1_326)

    h.check("i personalizzati possono essere preferiti", store.toggleFavorite(facePull.id))
    h.check("filtro preferiti li include",
            store.searchExercises(ExerciseFilter(favoritesOnly: true)).map(\.id) == [facePull.id])

    // MARK: Uso in scheda e sessione

    h.section("personalizzati · scheda, sessione e statistiche")

    let program = store.createProgram(name: "Test personalizzati", mode: .rotation)
    let day = store.addDay(name: "Giorno A", toProgram: program.id)
    store.addItems(exerciseIDs: [facePull.id, "0025"], toDay: day.id, inProgram: program.id)
    h.check("il personalizzato entra in scheda",
            store.program(id: program.id)?.days.first?.items.map(\.exerciseID) == [facePull.id, "0025"])

    guard let session = store.startSession(programID: program.id, dayID: day.id) else {
        h.fail("sessione non avviata")
        return
    }
    h.check("la sessione contiene il personalizzato", session.entries.first?.exerciseID == facePull.id)

    guard let entryID = store.activeSession?.entries.first?.id,
          let setID = store.activeSession?.entries.first?.sets.first?.id else {
        h.fail("serie del personalizzato assente")
        return
    }
    store.updateSet(id: setID, inEntry: entryID) { $0.weightKg = 25; $0.reps = 15 }
    store.completeSet(id: setID, inEntry: entryID)
    clock.advance(by: 45 * 60)
    guard let finished = store.finishSession() else {
        h.fail("sessione non archiviata")
        return
    }
    h.check("sessione archiviata con il personalizzato", finished.exerciseIDs.contains(facePull.id))
    h.check("volume calcolato", finished.totalVolumeKg == 25 * 15)

    let week = store.currentWeekSummary()
    h.check("le statistiche attribuiscono la zona al personalizzato", week.setsByMuscleGroup[.shoulders] == 1)
    h.check("le serie per zona tornano", week.setsByMuscleGroup.values.reduce(0, +) == week.completedSets)
    h.check("record del personalizzato", store.records(for: facePull.id)?.maxWeightKg == 25)
    h.check("alternative anche per il personalizzato", !store.alternatives(for: facePull.id).isEmpty)

    // MARK: Eliminazione

    h.section("personalizzati · eliminazione e storico")

    let unusedID = store.createCustomExercise(name: "Sbagliato", category: "waist", target: "abs")?.id ?? ""
    h.check("esercizio inutilizzato creato", !unusedID.isEmpty)
    h.check("eliminare un inutilizzato lo rimuove davvero", store.deleteCustomExercise(id: unusedID) == .removed)
    h.check("sparito dalla collezione", store.customExercise(id: unusedID) == nil)
    h.check("eliminare un id ignoto non fa nulla", store.deleteCustomExercise(id: "custom-mai-esistito") == .notFound)

    h.check("il personalizzato usato risulta in uso", store.isExerciseInUse(facePull.id))
    h.check("eliminare un usato lo archivia", store.deleteCustomExercise(id: facePull.id) == .archived)
    h.check("resta nella collezione", store.customExercise(id: facePull.id) != nil)
    h.check("marcato come eliminato", store.customExercise(id: facePull.id)?.isDeleted == true)
    h.check("nome e dati conservati", store.customExercise(id: facePull.id)?.name == "Face pull")
    h.check("nota conservata", store.customExercise(id: facePull.id)?.notes.contains("gomiti") == true)
    h.check("tolto dai preferiti", !store.settings.isFavorite(facePull.id))
    h.check("tolto dai recenti", !store.settings.recentExerciseIDs.contains(facePull.id))

    h.check("sparisce dalla ricerca", store.searchExercises(ExerciseFilter(query: "face pull")).isEmpty)
    h.check("sparisce dai facet", store.exerciseFacets().total == 1_325)
    h.check("non è più proposto fra le alternative",
            !store.alternatives(for: "0025").contains { $0.id == facePull.id })

    // Lo storico deve continuare a funzionare in tutto e per tutto.
    h.check("lo storico lo risolve ancora", store.exercise(id: facePull.id)?.displayName == "Face Pull")
    h.check("nome disponibile per la UI dello storico", store.exerciseDisplayName(id: facePull.id) == "Face Pull")
    h.check("la sessione salvata lo cita ancora",
            store.sessions.first?.entries.contains { $0.exerciseID == facePull.id } == true)
    h.check("il volume storico non cambia", store.sessions.first?.totalVolumeKg == 25 * 15)
    let weekAfterDelete = store.currentWeekSummary()
    h.check("le statistiche per zona reggono l'eliminazione", weekAfterDelete.setsByMuscleGroup[.shoulders] == 1)
    h.check("i record reggono l'eliminazione", store.records(for: facePull.id)?.maxWeightKg == 25)
    h.check("la scheda lo cita ancora",
            store.program(id: program.id)?.days.first?.items.contains { $0.exerciseID == facePull.id } == true)
    h.check("un id sconosciuto ha comunque un nome per la UI",
            store.exerciseDisplayName(id: "custom-sparito") == "Esercizio rimosso")

    h.check("ripristino possibile", store.restoreCustomExercise(id: facePull.id)?.isDeleted == false)
    h.check("dopo il ripristino torna nella ricerca",
            store.searchExercises(ExerciseFilter(query: "face pull")).first?.id == facePull.id)
    h.check("eliminato di nuovo", store.deleteCustomExercise(id: facePull.id) == .archived)

    // MARK: Persistenza e backup

    h.section("personalizzati · persistenza e backup")

    let backup = (try? store.exportBackup()) ?? Data()
    h.check("il backup contiene i personalizzati",
            (try? BackupPayload.decoded(from: backup))?.customExercises.count == 2)
    h.check("il backup conserva anche quelli eliminati",
            (try? BackupPayload.decoded(from: backup))?.customExercises.contains { $0.isDeleted } == true)

    await store.flush()

    let reopened = makeStore(in: directory)
    await reopened.load()
    h.check("ricaricati da disco", reopened.customExercises.count == 2)
    h.check("flag di eliminato persistito", reopened.customExercise(id: facePull.id)?.isDeleted == true)
    h.check("note persistite", reopened.customExercise(id: facePull.id)?.notes.contains("gomiti") == true)
    h.check("flag personalizzato persistito", reopened.customExercises.allSatisfy(\.isCustom))
    h.check("storico ancora risolvibile dopo il riavvio",
            reopened.exercise(id: facePull.id)?.displayName == "Face Pull")
    h.check("la libreria del dataset non è sporcata", reopened.exercises?.count == 1_324)
    h.check("il personalizzato attivo torna in ricerca",
            reopened.searchExercises(ExerciseFilter(query: "bulgarian")).first?.name == "Bulgarian split squat")

    // Import del backup in uno store vergine.
    let fresh = makeStore(in: TempDirectory.make())
    await fresh.load()
    if (try? await fresh.importBackup(backup)) != nil {
        h.check("import: personalizzati ripristinati", fresh.customExercises.count == 2)
        h.check("import: storico risolvibile", fresh.exercise(id: facePull.id)?.name == "Face pull")
        h.check("import: ricerca aggiornata",
                fresh.searchExercises(ExerciseFilter(query: "bulgarian")).count == 1)
    } else {
        h.fail("import del backup con personalizzati fallito")
    }

    // MARK: Round-trip del modello

    h.section("personalizzati · modello")

    let encoder = JSONCoding.makeEncoder()
    let decoder = JSONCoding.makeDecoder()
    if let data = try? encoder.encode(facePull), let restored = try? decoder.decode(Exercise.self, from: data) {
        h.check("round-trip Codable del personalizzato", restored == facePull)
    } else {
        h.fail("round-trip del personalizzato fallito")
    }
    h.check("un record del dataset non è personalizzato", repository?.exercise(id: "0025")?.isCustom == false)
    h.check("il prefisso dell'id basta a marcarlo",
            Exercise(id: "custom-abc", name: "x").isCustom)
    h.check("id generati distinti", Exercise.makeCustomID() != Exercise.makeCustomID())
}
