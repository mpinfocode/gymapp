import Foundation
import GymCore

@MainActor
func runBackupChecks(_ h: Harness, repository: ExerciseRepository?) async {

    h.section("backup · export")

    let sourceDirectory = TempDirectory.make()
    defer { TempDirectory.remove(sourceDirectory) }

    let clock = TestClock(Fixtures.date(2025, 4, 7, 19, 0))
    let source = AppStore(
        store: JSONFileStore(directory: sourceDirectory),
        exercises: repository,
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(50),
        now: clock.provider
    )
    await source.load()

    // Dati di prova: scheda d'esempio, una sessione completa, rilevazioni, preferiti
    let program = source.loadSampleProgram()
    guard let day = program.days.first else {
        h.fail("scheda d'esempio senza giorni")
        return
    }
    guard let started = source.startSession(programID: program.id, dayID: day.id),
          let entry = started.entries.first,
          let firstSet = entry.sets.first(where: { $0.kind == .normal }) else {
        h.fail("sessione di prova non avviata")
        return
    }
    source.updateSet(id: firstSet.id, inEntry: entry.id) { $0.weightKg = 100; $0.reps = 5 }
    clock.advance(by: 120)
    source.completeSet(id: firstSet.id, inEntry: entry.id)
    clock.advance(by: 1_800)
    source.finishSession(notes: "test backup")
    source.addBodyEntry(
        date: Fixtures.date(2025, 4, 1),
        weightKg: 78.4,
        bodyFatPct: 14.2,
        leanMassKg: 67.3,
        muscleMassKg: 35.1,
        waterPct: 57.5,
        measurementsCm: [.waist: 82, .armRight: 38.5]
    )
    source.toggleFavorite("0043")
    source.updateSettings { $0.unit = .lb; $0.displayName = "Francesco" }

    let data: Data
    do {
        data = try source.exportBackup()
    } catch {
        h.fail("export fallito: \(error)")
        return
    }

    h.check("il backup non è vuoto", !data.isEmpty)

    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        h.fail("il backup non è un oggetto JSON")
        return
    }
    h.check("campo version presente", object["version"] as? Int == BackupPayload.currentVersion)
    h.check("campo exportedAt presente", object["exportedAt"] is String)
    h.check("tutte le collezioni presenti", ["programs", "sessions", "bodyEntries", "settings"].allSatisfy { object[$0] != nil })
    h.check("la sessione attiva non entra nel backup", object["activeSession"] == nil)
    if let text = String(data: data, encoding: .utf8) {
        h.check("il backup è leggibile (indentato)", text.contains("\n  "))
    }

    // MARK: Import in uno store vergine

    h.section("backup · import")

    let targetDirectory = TempDirectory.make()
    defer { TempDirectory.remove(targetDirectory) }
    let targetFileStore = JSONFileStore(directory: targetDirectory)
    let target = AppStore(
        store: targetFileStore,
        exercises: repository,
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(50),
        now: clock.provider
    )
    await target.load()
    h.check("lo store di destinazione parte vuoto", target.programs.isEmpty && target.sessions.isEmpty)

    // Sessione in corso: l'import la deve scartare
    target.startFreeSession(name: "da scartare")

    do {
        try await target.importBackup(data)
    } catch {
        h.fail("import fallito: \(error)")
        return
    }

    h.check("schede importate", target.programs.map(\.id) == source.programs.map(\.id))
    h.check("scheda attiva importata", target.activeProgram?.id == program.id)
    h.check("giorni e voci importati", target.activeProgram?.days.map(\.name) == ["Push", "Pull", "Legs"])
    h.check("obiettivo a tempo importato", target.activeProgram?.days[2].items.last?.measure == .duration(seconds: 45))
    h.check("storico importato", target.sessions.map(\.id) == source.sessions.map(\.id))
    h.checkClose("volume importato", target.sessions.first?.totalVolumeKg ?? 0, 500)
    h.check("note della sessione importate", target.sessions.first?.notes == "test backup")
    h.check("rilevazioni importate", target.bodyEntries.map(\.id) == source.bodyEntries.map(\.id))
    h.checkClose("composizione corporea importata", target.bodyEntries.first?.leanMassKg ?? 0, 67.3)
    h.check("circonferenze importate", target.bodyEntries.first?[.waist] == 82)
    h.check("impostazioni importate", target.settings == source.settings)
    h.check("preferiti importati", target.isFavorite("0043"))
    h.check("la sessione in corso viene scartata", target.activeSession == nil)

    await target.flush()
    h.check("la sessione scartata è sparita anche da disco", await !targetFileStore.exists(.activeSession))

    // Riavvio: l'import deve essere già su disco
    let afterRestart = AppStore(
        store: JSONFileStore(directory: targetDirectory),
        exercises: repository,
        calendar: Fixtures.calendar,
        saveDelay: .milliseconds(50),
        now: clock.provider
    )
    await afterRestart.load()
    h.check("dopo il riavvio i dati importati ci sono ancora", afterRestart.sessions.count == source.sessions.count)
    h.check("dopo il riavvio le schede sono quelle importate", afterRestart.programs.map(\.id) == source.programs.map(\.id))
    h.check("dopo il riavvio la scheda attiva è quella importata", afterRestart.activeProgram?.id == program.id)

    // Export → import → export deve essere stabile
    do {
        let second = try target.exportBackup()
        let a = try BackupPayload.decoded(from: data)
        let b = try BackupPayload.decoded(from: second)
        h.check("round-trip stabile: schede", a.programs == b.programs)
        h.check("round-trip stabile: rilevazioni", a.bodyEntries == b.bodyEntries)
        h.check("round-trip stabile: impostazioni", a.settings == b.settings)
        h.check("round-trip stabile: sessioni", a.sessions.map(\.id) == b.sessions.map(\.id))
    } catch {
        h.fail("secondo export fallito: \(error)")
    }

    // MARK: Robustezza del formato

    h.section("backup · robustezza del formato")

    let future = Data(#"{"version":99,"programs":[]}"#.utf8)
    do {
        _ = try BackupPayload.decoded(from: future)
        h.fail("un backup di versione futura avrebbe dovuto essere rifiutato")
    } catch let error as BackupError {
        if case .unsupportedVersion(let version) = error {
            h.check("versione futura rifiutata con la versione giusta", version == 99)
        } else {
            h.fail("errore di backup inatteso: \(error)")
        }
    } catch {
        h.fail("errore inatteso: \(error)")
    }

    do {
        let partial = try BackupPayload.decoded(from: Data(#"{"version":1}"#.utf8))
        h.check("backup parziale: collezioni vuote", partial.programs.isEmpty && partial.sessions.isEmpty && partial.bodyEntries.isEmpty)
        h.check("backup parziale: impostazioni di default", partial.settings == UserSettings())
    } catch {
        h.fail("backup parziale rifiutato: \(error)")
    }

    do {
        let noVersion = try BackupPayload.decoded(from: Data("{}".utf8))
        h.check("backup senza version → versione corrente", noVersion.version == BackupPayload.currentVersion)
    } catch {
        h.fail("backup senza version rifiutato: \(error)")
    }

    do {
        _ = try BackupPayload.decoded(from: Data("non json".utf8))
        h.fail("un backup non-JSON avrebbe dovuto lanciare")
    } catch {
        h.check("backup corrotto → errore", true)
    }

    do {
        try await target.importBackup(Data("non json".utf8))
        h.fail("l'import di dati corrotti avrebbe dovuto lanciare")
    } catch {
        h.check("import corrotto → errore, dati intatti", target.sessions.count == source.sessions.count)
    }

    h.check("riepilogo leggibile", (try? BackupPayload.decoded(from: data))?.summary.contains("schede") == true)
}
