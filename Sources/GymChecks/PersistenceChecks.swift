import Foundation
import GymCore

@MainActor
func runPersistenceChecks(_ h: Harness) async {

    h.section("persistenza · round-trip su temp dir")

    // Directory volutamente non creata: lo store la deve creare da solo.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("GymChecks-\(UUID().uuidString)", isDirectory: true)
    defer { TempDirectory.remove(directory) }

    let store = JSONFileStore(directory: directory)

    h.check("file assente prima di scrivere", await !store.exists(.programs))
    do {
        let nothing = try await store.load([Program].self, from: .programs)
        h.check("load su file assente → nil", nothing == nil)
    } catch {
        h.fail("load su file assente ha lanciato: \(error)")
    }

    let started = Fixtures.date(2025, 2, 3, 18, 30)
    let programs = [
        Program(
            name: "Massa",
            notes: "scheda di prova",
            startDate: started,
            plannedWeeks: 6,
            mode: .weekdays,
            days: [
                ProgramDay(
                    name: "Push",
                    weekday: .monday,
                    items: [PlanItem(exerciseID: "0025", targetSets: 4, measure: .reps(min: 6, max: 8), targetWeightKg: 80, warmupSets: 2)]
                ),
                ProgramDay(name: "Core", items: [PlanItem(exerciseID: "0464", targetSets: 3, measure: .duration(seconds: 45))]),
            ],
            createdAt: started,
            updatedAt: started
        ),
        Program(name: "Definizione", startDate: started, isArchived: true, createdAt: started, updatedAt: started),
    ]

    do {
        try await store.save(programs, to: .programs)
        h.check("la directory viene creata al bisogno", FileManager.default.fileExists(atPath: directory.path))
        h.check("il file esiste dopo il salvataggio", await store.exists(.programs))
        h.check("nome del file", await store.url(for: .programs).lastPathComponent == "programs.json")

        let loaded = try await store.load([Program].self, from: .programs)
        h.check("round-trip: numero di schede", loaded?.count == 2)
        h.check("round-trip: identità preservata", loaded?.map(\.id) == programs.map(\.id))
        h.check("round-trip: giorni e voci", loaded?.first?.days.first?.items.first?.exerciseID == "0025")
        h.check("round-trip: obiettivo a ripetizioni", loaded?.first?.days.first?.items.first?.measure == .reps(min: 6, max: 8))
        h.check("round-trip: obiettivo a tempo", loaded?.first?.days.last?.items.first?.measure == .duration(seconds: 45))
        h.check("round-trip: giorno della settimana", loaded?.first?.days.first?.weekday == .monday)
        h.check("round-trip: modalità e archiviazione", loaded?.first?.mode == .weekdays && loaded?.last?.isArchived == true)
        if let date = loaded?.first?.startDate {
            h.checkClose("round-trip: date ISO 8601", date, started)
        } else {
            h.fail("data non ricaricata")
        }
    } catch {
        h.fail("round-trip schede fallito: \(error)")
    }

    // Formato del file su disco
    if let data = try? Data(contentsOf: directory.appendingPathComponent("programs.json")),
       let text = String(data: data, encoding: .utf8) {
        h.check("date scritte in ISO 8601", text.contains("2025-02-03T"))
        h.check("chiavi ordinate alfabeticamente", text.contains("\"accent\":0,\"createdAt\""))
        h.check("slash non escapati", !text.contains("\\/"))
    } else {
        h.fail("file programs.json non leggibile")
    }

    // Sovrascrittura atomica
    do {
        try await store.save([programs[0]], to: .programs)
        let loaded = try await store.load([Program].self, from: .programs)
        h.check("la sovrascrittura sostituisce il contenuto", loaded?.count == 1)
    } catch {
        h.fail("sovrascrittura fallita: \(error)")
    }

    // MARK: Tutte le collezioni

    h.section("persistenza · tutte le collezioni")

    let session = WorkoutSession(
        programID: programs[0].id,
        programDayID: programs[0].days[0].id,
        name: "Push",
        startedAt: started,
        endedAt: started.addingTimeInterval(3_600),
        entries: [SessionEntry(
            exerciseID: "0025",
            planItemID: programs[0].days[0].items[0].id,
            measureKind: .reps,
            sets: [SetLog(kind: .normal, weightKg: 80, reps: 8, rpe: 8.5, completedAt: started)],
            supersetGroup: 1
        )]
    )
    let bodyEntries = [BodyEntry(date: started, weightKg: 78.4, bodyFatPct: 14.2, measurementsCm: [.waist: 82])]
    var settings = UserSettings(displayName: "Francesco", activeProgramID: programs[0].id, unit: .lb, defaultRestSeconds: 120)
    settings.favoriteExerciseIDs = ["0025", "0043"]

    do {
        try await store.save([session], to: .sessions)
        try await store.save(bodyEntries, to: .bodyEntries)
        try await store.save(settings, to: .settings)
        try await store.save(session, to: .activeSession)

        let loadedSessions = try await store.load([WorkoutSession].self, from: .sessions)
        h.check("sessioni ricaricate", loadedSessions?.count == 1)
        h.checkClose("volume preservato", loadedSessions?.first?.totalVolumeKg ?? 0, 640)
        h.check("collegamento alla scheda preservato", loadedSessions?.first?.programID == programs[0].id)
        h.check("collegamento al giorno preservato", loadedSessions?.first?.programDayID == programs[0].days[0].id)
        h.check("collegamento alla voce di piano preservato", loadedSessions?.first?.entries.first?.planItemID == programs[0].days[0].items[0].id)
        h.check("superset e RPE preservati",
                loadedSessions?.first?.entries.first?.supersetGroup == 1
                && loadedSessions?.first?.entries.first?.sets.first?.rpe == 8.5)
        if let endedAt = loadedSessions?.first?.endedAt {
            h.checkClose("data di fine preservata", endedAt, started.addingTimeInterval(3_600))
        } else {
            h.fail("endedAt perso nel round-trip")
        }

        let loadedBody = try await store.load([BodyEntry].self, from: .bodyEntries)
        h.checkClose("peso ricaricato", loadedBody?.first?.weightKg ?? 0, 78.4)
        h.checkClose("massa grassa ricaricata", loadedBody?.first?.bodyFatPct ?? 0, 14.2)
        h.check("circonferenze ricaricate", loadedBody?.first?[.waist] == 82)

        h.check("impostazioni ricaricate", try await store.load(UserSettings.self, from: .settings) == settings)
        h.check("scheda attiva ricordata", try await store.load(UserSettings.self, from: .settings)?.activeProgramID == programs[0].id)
        h.check("sessione attiva ricaricata", try await store.load(WorkoutSession.self, from: .activeSession)?.id == session.id)
    } catch {
        h.fail("round-trip collezioni fallito: \(error)")
    }

    // MARK: Cancellazione

    h.section("persistenza · cancellazione")

    do {
        try await store.delete(.activeSession)
        h.check("il file cancellato non esiste più", await !store.exists(.activeSession))
        h.check("load dopo delete → nil", try await store.load(WorkoutSession.self, from: .activeSession) == nil)
        try await store.delete(.activeSession)
        h.check("cancellare due volte non lancia", true)

        try await store.deleteAll()
        var anyLeft = false
        for file in StoreFile.allCases where await store.exists(file) { anyLeft = true }
        h.check("deleteAll rimuove ogni collezione", !anyLeft)
    } catch {
        h.fail("cancellazione fallita: \(error)")
    }

    // MARK: File corrotto

    h.section("persistenza · file corrotto")

    let corrupted = directory.appendingPathComponent("programs.json")
    try? Data("{ questo non è json".utf8).write(to: corrupted)
    do {
        _ = try await store.load([Program].self, from: .programs)
        h.fail("un file corrotto avrebbe dovuto lanciare")
    } catch {
        h.check("file corrotto → errore propagato", true)
    }

    try? Data().write(to: corrupted)
    do {
        let empty = try await store.load([Program].self, from: .programs)
        h.check("file vuoto → nil (non un errore)", empty == nil)
    } catch {
        h.fail("file vuoto ha lanciato: \(error)")
    }

    // MARK: Directory iniettabile

    h.section("persistenza · directory iniettabile")

    let otherDirectory = TempDirectory.make()
    defer { TempDirectory.remove(otherDirectory) }
    let otherStore = JSONFileStore(directory: otherDirectory)
    do {
        try await otherStore.save(programs, to: .programs)
        h.check("store separati non si vedono", try await otherStore.load([Program].self, from: .programs)?.count == 2)
        h.check("la directory è quella iniettata", await otherStore.directory == otherDirectory)
    } catch {
        h.fail("store separato fallito: \(error)")
    }
}
