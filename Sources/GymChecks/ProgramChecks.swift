import Foundation
import GymCore

@MainActor
func runProgramChecks(_ h: Harness) {

    let calendar = Fixtures.calendar
    let decoder = JSONDecoder()

    // MARK: SetMeasure

    h.section("scheda · obiettivo della serie")

    let repsRange = SetMeasure.reps(min: 6, max: 8)
    h.check("range: kind", repsRange.kind == .reps)
    h.check("range: testo", repsRange.displayText == "6-8")
    h.check("range: estremi", repsRange.repsRange == 6...8)
    h.check("range: nessuna durata", repsRange.durationSeconds == nil)
    h.check("valore singolo", SetMeasure.reps(min: 10, max: 10).displayText == "10")
    h.check("max sotto min viene corretto", SetMeasure.reps(min: 10, max: 5).repsRange == 10...10)

    let timed = SetMeasure.duration(seconds: 45)
    h.check("durata: kind", timed.kind == .duration)
    h.check("durata: testo sotto il minuto", timed.displayText == "45s")
    h.check("durata: testo sopra il minuto", SetMeasure.duration(seconds: 90).displayText == "1:30")
    h.check("durata: minuto tondo", SetMeasure.duration(seconds: 120).displayText == "2:00")
    h.check("durata: secondi", timed.durationSeconds == 45)
    h.check("durata: nessun range", timed.repsRange == nil)

    for measure in [repsRange, timed] {
        if let data = try? JSONEncoder().encode(measure),
           let restored = try? decoder.decode(SetMeasure.self, from: data) {
            h.check("SetMeasure round-trip (\(measure.kind.rawValue))", restored == measure)
        } else {
            h.fail("SetMeasure round-trip fallito (\(measure.kind.rawValue))")
        }
    }

    if let data = try? JSONEncoder().encode(repsRange), let text = String(data: data, encoding: .utf8) {
        h.check("SetMeasure serializzato con discriminante", text.contains("\"kind\":\"reps\""))
    }
    h.check("SetMeasure con kind ignoto → default",
            (try? decoder.decode(SetMeasure.self, from: Data(#"{"kind":"boh"}"#.utf8))) == nil)
    if let partial = try? decoder.decode(SetMeasure.self, from: Data(#"{"kind":"reps"}"#.utf8)) {
        h.check("SetMeasure senza estremi → default", partial == .reps(min: 8, max: 8))
    } else {
        h.fail("SetMeasure parziale non decodificato")
    }
    if let partial = try? decoder.decode(SetMeasure.self, from: Data(#"{"kind":"duration"}"#.utf8)) {
        h.check("durata senza secondi → default", partial.durationSeconds == 30)
    } else {
        h.fail("durata parziale non decodificata")
    }
    h.check("colonne della tabella", MeasureKind.reps.columnTitle == "REPS" && MeasureKind.duration.columnTitle == "TEMPO")

    // MARK: PlanItem e ProgramDay

    h.section("scheda · voci e giorni")

    let bench = PlanItem(
        exerciseID: "0025",
        targetSets: 4,
        measure: .reps(min: 6, max: 8),
        targetWeightKg: 80,
        warmupSets: 2,
        restSeconds: 150,
        note: "presa media"
    )
    h.check("riepilogo della voce", bench.summary() == "4 × 6-8 · 80 kg")
    h.check("riepilogo senza carico previsto", PlanItem(exerciseID: "x", targetSets: 3).summary() == "3 × 8-12")
    h.check("valori negativi normalizzati", PlanItem(exerciseID: "x", targetSets: -2, warmupSets: -1, restSeconds: -5).targetSets == 0)

    let day = ProgramDay(
        name: "Push",
        items: [bench, PlanItem(exerciseID: "0047", targetSets: 3, supersetGroup: 1), PlanItem(exerciseID: "0201", targetSets: 3, supersetGroup: 1)]
    )
    h.check("serie previste dal giorno", day.totalSets == 10)
    h.check("id esercizi del giorno", day.exerciseIDs == ["0025", "0047", "0201"])
    h.check("gruppi di superset", day.supersetGroups == [1])

    if let partial = try? decoder.decode(PlanItem.self, from: Data(#"{"exerciseID":"0025"}"#.utf8)) {
        h.check("PlanItem parziale: id generato", partial.exerciseID == "0025" && partial.targetSets == 3)
        h.check("PlanItem parziale: measure di default", partial.measure == .default)
    } else {
        h.fail("PlanItem parziale non decodificato")
    }
    if let partial = try? decoder.decode(ProgramDay.self, from: Data(#"{"name":"Giorno A"}"#.utf8)) {
        h.check("ProgramDay parziale", partial.name == "Giorno A" && partial.items.isEmpty && partial.weekday == nil)
    } else {
        h.fail("ProgramDay parziale non decodificato")
    }

    // MARK: Program: durata e scadenza

    h.section("scheda · durata e scadenza")

    let start = Fixtures.date(2025, 3, 3) // lunedì
    let program = Program(
        name: "Massa inverno",
        startDate: start,
        plannedWeeks: 6,
        mode: .rotation,
        days: [day, ProgramDay(name: "Pull"), ProgramDay(name: "Legs")]
    )

    h.check("data di fine = inizio + 6 settimane", program.endDate(calendar: calendar) == Fixtures.date(2025, 4, 14, 0, 0))
    h.check("giorno di inizio normalizzato a mezzanotte", program.normalizedStart(calendar: calendar) == Fixtures.date(2025, 3, 3, 0, 0))
    h.check("settimane trascorse: il primo giorno", program.weeksElapsed(asOf: start, calendar: calendar) == 0)
    h.check("settimane trascorse: dopo 6 giorni", program.weeksElapsed(asOf: Fixtures.date(2025, 3, 9), calendar: calendar) == 0)
    h.check("settimane trascorse: dopo 7 giorni", program.weeksElapsed(asOf: Fixtures.date(2025, 3, 10), calendar: calendar) == 1)
    h.check("settimana corrente in base 1", program.currentWeek(asOf: Fixtures.date(2025, 3, 18), calendar: calendar) == 3)
    h.check("testo di stato", program.statusText(asOf: Fixtures.date(2025, 3, 18), calendar: calendar) == "Settimana 3 di 6")

    h.check("non scaduta prima della fine", !program.isExpired(asOf: Fixtures.date(2025, 4, 13), calendar: calendar))
    h.check("scaduta il giorno di fine", program.isExpired(asOf: Fixtures.date(2025, 4, 14), calendar: calendar))
    h.check("scaduta dopo la fine", program.isExpired(asOf: Fixtures.date(2025, 5, 1), calendar: calendar))
    h.check("testo di stato a scadenza", program.statusText(asOf: Fixtures.date(2025, 4, 20), calendar: calendar) == "Scheda scaduta")

    h.check("giorni alla scadenza", program.daysToExpiry(asOf: Fixtures.date(2025, 4, 10), calendar: calendar) == 4)
    h.check("giorni alla scadenza non va sotto zero", program.daysToExpiry(asOf: Fixtures.date(2025, 5, 1), calendar: calendar) == 0)
    h.check("avviso a 7 giorni dalla fine", program.isExpiringSoon(asOf: Fixtures.date(2025, 4, 8), calendar: calendar))
    h.check("nessun avviso a 8 giorni dalla fine", !program.isExpiringSoon(asOf: Fixtures.date(2025, 4, 6), calendar: calendar))
    h.check("nessun avviso quando è già scaduta", !program.isExpiringSoon(asOf: Fixtures.date(2025, 4, 20), calendar: calendar))

    let endless = Program(name: "Senza fine", startDate: start, plannedWeeks: nil)
    h.check("senza durata non ha data di fine", endless.endDate(calendar: calendar) == nil)
    h.check("senza durata non scade mai", !endless.isExpired(asOf: Fixtures.date(2030, 1, 1), calendar: calendar))
    h.check("senza durata nessun conto alla rovescia", endless.daysToExpiry(asOf: start, calendar: calendar) == nil)
    h.check("senza durata testo di stato", endless.statusText(asOf: start, calendar: calendar) == "Senza scadenza")

    h.check("serie totali della scheda", program.totalSets == 10)
    h.check("esercizi della scheda senza duplicati", program.exerciseIDs == ["0025", "0047", "0201"])
    h.check("lookup del giorno", program.day(id: day.id)?.name == "Push")
    h.check("lookup della voce in qualunque giorno", program.item(id: bench.id)?.exerciseID == "0025")

    if let data = try? JSONCoding.makeEncoder().encode(program),
       let restored = try? JSONCoding.makeDecoder().decode(Program.self, from: data) {
        h.check("Program round-trip: giorni e voci", restored.days.map(\.id) == program.days.map(\.id))
        h.check("Program round-trip: modalità e durata", restored.mode == .rotation && restored.plannedWeeks == 6)
        h.check("Program round-trip: obiettivi", restored.days[0].items[0].measure == .reps(min: 6, max: 8))
    } else {
        h.fail("Program round-trip fallito")
    }

    if let partial = try? decoder.decode(Program.self, from: Data(#"{"name":"Vecchia"}"#.utf8)) {
        h.check("Program parziale: nome", partial.name == "Vecchia")
        h.check("Program parziale: modalità di default", partial.mode == .rotation)
        h.check("Program parziale: senza giorni né scadenza", partial.days.isEmpty && partial.plannedWeeks == nil)
        h.check("Program parziale: startDate ricade su createdAt", partial.startDate == partial.createdAt)
        h.check("Program parziale: non archiviata", !partial.isArchived)
    } else {
        h.fail("Program parziale non decodificato")
    }

    // MARK: Allenamento di oggi

    h.section("scheda · allenamento di oggi")

    let pushDay = program.days[0]
    let pullDay = program.days[1]
    let legsDay = program.days[2]

    // Rotazione senza storico → primo giorno
    h.check("rotazione senza storico → primo giorno",
            Stats.todaysWorkout(for: program, on: start, sessions: [], calendar: calendar).programDay?.id == pushDay.id)

    func done(_ dayID: UUID, at date: Date, programID: UUID) -> WorkoutSession {
        WorkoutSession(
            programID: programID,
            programDayID: dayID,
            name: "x",
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            entries: [SessionEntry(exerciseID: "0025", sets: [SetLog(kind: .normal, weightKg: 80, reps: 8, completedAt: date)])]
        )
    }

    let afterPush = [done(pushDay.id, at: Fixtures.date(2025, 3, 3), programID: program.id)]
    h.check("rotazione: dopo Push tocca Pull",
            Stats.todaysWorkout(for: program, on: Fixtures.date(2025, 3, 4), sessions: afterPush, calendar: calendar).programDay?.id == pullDay.id)

    let afterLegs = afterPush + [
        done(pullDay.id, at: Fixtures.date(2025, 3, 5), programID: program.id),
        done(legsDay.id, at: Fixtures.date(2025, 3, 7), programID: program.id),
    ]
    h.check("rotazione: dopo l'ultimo giorno si riparte dal primo",
            Stats.todaysWorkout(for: program, on: Fixtures.date(2025, 3, 8), sessions: afterLegs, calendar: calendar).programDay?.id == pushDay.id)

    let otherProgram = [done(pushDay.id, at: Fixtures.date(2025, 3, 9), programID: UUID())]
    h.check("rotazione: le sessioni di altre schede non contano",
            Stats.todaysWorkout(for: program, on: Fixtures.date(2025, 3, 10), sessions: afterPush + otherProgram, calendar: calendar).programDay?.id == pullDay.id)

    let freeSession = [WorkoutSession(name: "libero", startedAt: Fixtures.date(2025, 3, 9))]
    h.check("rotazione: gli allenamenti liberi non contano",
            Stats.todaysWorkout(for: program, on: Fixtures.date(2025, 3, 10), sessions: afterPush + freeSession, calendar: calendar).programDay?.id == pullDay.id)

    h.check("rotazione: si guarda solo il passato",
            Stats.todaysWorkout(for: program, on: Fixtures.date(2025, 3, 4), sessions: afterLegs, calendar: calendar).programDay?.id == pullDay.id)

    let removedDay = [done(UUID(), at: Fixtures.date(2025, 3, 3), programID: program.id)]
    h.check("rotazione: un giorno cancellato non blocca la proposta",
            Stats.todaysWorkout(for: program, on: Fixtures.date(2025, 3, 4), sessions: removedDay, calendar: calendar).programDay?.id == pushDay.id)

    // Giorni fissi
    var weekdayProgram = program
    weekdayProgram.mode = .weekdays
    weekdayProgram.days[0].weekday = .monday
    weekdayProgram.days[1].weekday = .wednesday
    weekdayProgram.days[2].weekday = .friday

    h.check("giorni fissi: lunedì → Push",
            Stats.todaysWorkout(for: weekdayProgram, on: Fixtures.date(2025, 3, 3), sessions: [], calendar: calendar).programDay?.name == "Push")
    h.check("giorni fissi: mercoledì → Pull",
            Stats.todaysWorkout(for: weekdayProgram, on: Fixtures.date(2025, 3, 5), sessions: [], calendar: calendar).programDay?.name == "Pull")
    h.check("giorni fissi: venerdì → Legs",
            Stats.todaysWorkout(for: weekdayProgram, on: Fixtures.date(2025, 3, 7), sessions: [], calendar: calendar).programDay?.name == "Legs")
    h.check("giorni fissi: martedì → riposo",
            Stats.todaysWorkout(for: weekdayProgram, on: Fixtures.date(2025, 3, 4), sessions: [], calendar: calendar).isRest)
    h.check("giorni fissi: domenica → riposo",
            Stats.todaysWorkout(for: weekdayProgram, on: Fixtures.date(2025, 3, 9), sessions: [], calendar: calendar) == .rest)
    h.check("giorni fissi: lo storico non cambia la proposta",
            Stats.todaysWorkout(for: weekdayProgram, on: Fixtures.date(2025, 3, 3), sessions: afterLegs, calendar: calendar).programDay?.name == "Push")

    var emptyProgram = program
    emptyProgram.days = []
    h.check("scheda senza giorni → empty",
            Stats.todaysWorkout(for: emptyProgram, on: start, sessions: [], calendar: calendar) == .empty)
    emptyProgram.mode = .weekdays
    h.check("scheda senza giorni → empty anche a giorni fissi",
            Stats.todaysWorkout(for: emptyProgram, on: start, sessions: [], calendar: calendar) == .empty)

    h.check("riposo non propone nessun giorno",
            Stats.todaysWorkout(for: weekdayProgram, on: Fixtures.date(2025, 3, 4), sessions: [], calendar: calendar).programDay == nil)
    h.check("indice dell'ultimo giorno completato", Stats.lastCompletedDayIndex(of: program, in: afterLegs) == 2)
    h.check("nessun giorno completato → nil", Stats.lastCompletedDayIndex(of: program, in: []) == nil)

    // MARK: Suggerimento di progressione

    h.section("scheda · suggerimento di progressione")

    func session(_ exerciseID: String, sets: [(Double, Int)], kind: SetKind = .normal) -> WorkoutSession {
        let date = Fixtures.date(2025, 3, 10)
        return WorkoutSession(
            name: "x",
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            entries: [SessionEntry(
                exerciseID: exerciseID,
                sets: sets.map { SetLog(kind: kind, weightKg: $0.0, reps: $0.1, completedAt: date) }
            )]
        )
    }

    let item = PlanItem(exerciseID: "0025", targetSets: 3, measure: .reps(min: 6, max: 8), targetWeightKg: 80)
    let maxedOut = session("0025", sets: [(80, 8), (80, 8), (80, 8)])

    if let suggestion = Stats.progressionSuggestion(for: item, lastSession: maxedOut, equipment: "barbell") {
        h.checkClose("bilanciere: +2,5 kg", suggestion.incrementKg, 2.5)
        h.checkClose("carico attuale", suggestion.currentWeightKg, 80)
        h.checkClose("carico proposto", suggestion.suggestedWeightKg, 82.5)
        h.check("motivazione in italiano", suggestion.reason.contains("82.5 kg") && suggestion.reason.contains("3 serie"))
        h.check("esercizio corretto", suggestion.exerciseID == "0025")
    } else {
        h.fail("nessun suggerimento quando il range è stato completato")
    }

    let dumbbellItem = PlanItem(exerciseID: "0334", targetSets: 3, measure: .reps(min: 12, max: 15))
    if let suggestion = Stats.progressionSuggestion(
        for: dumbbellItem,
        lastSession: session("0334", sets: [(12, 15), (12, 15), (12, 15)]),
        equipment: "dumbbell"
    ) {
        h.checkClose("manubri: +1,25 kg", suggestion.incrementKg, 1.25)
        h.checkClose("carico proposto sui manubri", suggestion.suggestedWeightKg, 13.25)
    } else {
        h.fail("nessun suggerimento sui manubri")
    }

    h.check("incremento piccolo sui cavi", Stats.suggestedIncrement(forEquipment: "cable") == 1.25)
    h.check("incremento standard sul bilanciere", Stats.suggestedIncrement(forEquipment: "barbell") == 2.5)
    h.check("incremento insensibile a maiuscole", Stats.suggestedIncrement(forEquipment: "DUMBBELL") == 1.25)

    h.check("nessuno storico → nessun suggerimento",
            Stats.progressionSuggestion(for: item, lastSession: nil, equipment: "barbell") == nil)
    h.check("una serie sotto il massimo → nessun suggerimento",
            Stats.progressionSuggestion(for: item, lastSession: session("0025", sets: [(80, 8), (80, 8), (80, 7)]), equipment: "barbell") == nil)
    h.check("meno serie del previsto → nessun suggerimento",
            Stats.progressionSuggestion(for: item, lastSession: session("0025", sets: [(80, 8), (80, 8)]), equipment: "barbell") == nil)
    h.check("carico sotto quello previsto → nessun suggerimento",
            Stats.progressionSuggestion(for: item, lastSession: session("0025", sets: [(70, 8), (70, 8), (70, 8)]), equipment: "barbell") == nil)
    h.check("solo warmup → nessun suggerimento",
            Stats.progressionSuggestion(for: item, lastSession: session("0025", sets: [(80, 8), (80, 8), (80, 8)], kind: .warmup), equipment: "barbell") == nil)
    h.check("serie a cedimento non contano",
            Stats.progressionSuggestion(for: item, lastSession: session("0025", sets: [(80, 8), (80, 8), (80, 8)], kind: .failure), equipment: "barbell") == nil)
    h.check("esercizio diverso → nessun suggerimento",
            Stats.progressionSuggestion(for: item, lastSession: session("9999", sets: [(80, 8), (80, 8), (80, 8)]), equipment: "barbell") == nil)
    h.check("esercizio a tempo → nessun suggerimento",
            Stats.progressionSuggestion(
                for: PlanItem(exerciseID: "0464", targetSets: 3, measure: .duration(seconds: 45)),
                lastSession: session("0464", sets: [(0, 0)]),
                equipment: "body weight"
            ) == nil)

    // Superare il massimo del range vale come averlo raggiunto
    if Stats.progressionSuggestion(for: item, lastSession: session("0025", sets: [(80, 9), (80, 8), (80, 10)]), equipment: "barbell") != nil {
        h.check("superare il range conta come completato", true)
    } else {
        h.fail("superare il range avrebbe dovuto dare un suggerimento")
    }

    // Senza carico previsto si parte da quello usato
    if let suggestion = Stats.progressionSuggestion(
        for: PlanItem(exerciseID: "0025", targetSets: 3, measure: .reps(min: 6, max: 8)),
        lastSession: session("0025", sets: [(70, 8), (70, 8), (70, 8)]),
        equipment: "barbell"
    ) {
        h.checkClose("senza carico previsto si parte dall'ultimo usato", suggestion.suggestedWeightKg, 72.5)
    } else {
        h.fail("nessun suggerimento senza carico previsto")
    }

    // MARK: Rilevazioni corporee

    h.section("corpo · BodyEntry e metriche")

    h.check("11 circonferenze", BodyMeasure.allCases.count == 11)
    h.check("nomi italiani delle circonferenze", BodyMeasure.waist.displayName == "Vita" && BodyMeasure.armRight.displayName == "Braccio destro")
    h.check("nomi compatti", BodyMeasure.armRight.shortName == "Braccio dx" && BodyMeasure.thighLeft.shortName == "Coscia sx")
    h.check("metriche totali: 5 di composizione + 11 misure", BodyMetricKind.allCases.count == 16)
    h.check("ordine: prima peso e composizione", Array(BodyMetricKind.allCases.prefix(5)) == BodyMetricKind.compositionCases)

    h.check("unità del peso", BodyMetricKind.weight.unit == .kilograms)
    h.check("unità della massa grassa", BodyMetricKind.bodyFat.unit == .percent)
    h.check("unità della massa magra", BodyMetricKind.leanMass.unit == .kilograms)
    h.check("unità di una circonferenza", BodyMetricKind.measure(.waist).unit == .centimeters)
    h.check("simboli", BodyMetricUnit.kilograms.symbol == "kg" && BodyMetricUnit.centimeters.symbol == "cm" && BodyMetricUnit.percent.symbol == "%")
    h.check("nomi italiani delle metriche",
            BodyMetricKind.weight.displayName == "Peso"
            && BodyMetricKind.bodyFat.displayName == "Massa grassa"
            && BodyMetricKind.leanMass.displayName == "Massa magra"
            && BodyMetricKind.muscleMass.displayName == "Massa muscolare"
            && BodyMetricKind.water.displayName == "Acqua corporea")
    h.check("metrica di una circonferenza prende il nome della misura", BodyMetricKind.measure(.calf).displayName == "Polpaccio")

    h.check("rawValue stabile", BodyMetricKind.measure(.waist).rawValue == "measure.waist")
    h.check("rawValue invertibile", BodyMetricKind.allCases.allSatisfy { BodyMetricKind(rawValue: $0.rawValue) == $0 })
    h.check("rawValue ignoto → nil", BodyMetricKind(rawValue: "measure.orecchio") == nil)

    h.check("formattazione in kg", BodyMetricKind.weight.format(78.4) == "78.4 kg")
    h.check("formattazione in libbre", BodyMetricKind.weight.format(100, weightUnit: .lb) == "220.5 lb")
    h.check("formattazione in cm", BodyMetricKind.measure(.waist).format(82) == "82 cm")
    h.check("formattazione in percentuale", BodyMetricKind.bodyFat.format(14.2) == "14.2%")
    h.check("percentuale arrotondata a un decimale", BodyMetricKind.bodyFat.format(14.26) == "14.3%")
    h.check("percentuale intera senza decimali", BodyMetricKind.water.format(58) == "58%")

    var entry = BodyEntry(date: Fixtures.date(2025, 3, 3), weightKg: 78.4, bodyFatPct: 14.2)
    entry[.waist] = 82
    entry[.armRight] = 38.5
    h.check("accesso per circonferenza", entry[.waist] == 82)
    h.check("accesso per metrica", entry[BodyMetricKind.weight] == 78.4 && entry[BodyMetricKind.measure(.armRight)] == 38.5)
    h.check("metrica non registrata → nil", entry[BodyMetricKind.water] == nil)
    entry[BodyMetricKind.water] = 58
    h.check("scrittura per metrica", entry.waterPct == 58)
    h.check("misure registrate in ordine canonico", entry.recordedMeasures == [.armRight, .waist])
    h.check("metriche registrate", entry.recordedMetrics == [.weight, .bodyFat, .water, .measure(.armRight), .measure(.waist)])
    h.check("rilevazione non vuota", !entry.isEmpty)
    h.check("rilevazione vuota", BodyEntry(date: Date()).isEmpty)

    if let data = try? JSONCoding.makeEncoder().encode(entry),
       let restored = try? JSONCoding.makeDecoder().decode(BodyEntry.self, from: data) {
        h.check("BodyEntry round-trip: valori", restored.weightKg == 78.4 && restored[.waist] == 82 && restored.waterPct == 58)
        h.check("BodyEntry round-trip: id", restored.id == entry.id)
    } else {
        h.fail("BodyEntry round-trip fallito")
    }
    if let data = try? JSONEncoder().encode(entry), let text = String(data: data, encoding: .utf8) {
        h.check("circonferenze serializzate come oggetto", text.contains("\"waist\""))
    }

    if let partial = try? decoder.decode(BodyEntry.self, from: Data(#"{"weightKg":80}"#.utf8)) {
        h.check("BodyEntry parziale: solo peso", partial.weightKg == 80 && partial.measurementsCm.isEmpty && partial.bodyFatPct == nil)
    } else {
        h.fail("BodyEntry parziale non decodificato")
    }
    if let unknown = try? decoder.decode(BodyEntry.self, from: Data(#"{"measurementsCm":{"waist":80,"orecchio":7}}"#.utf8)) {
        h.check("BodyEntry ignora le misure sconosciute", unknown.measurementsCm == [.waist: 80])
    } else {
        h.fail("BodyEntry con misura ignota non decodificato")
    }

    // MARK: Serie storiche e variazioni

    h.section("corpo · serie storiche e variazioni")

    let entries = [
        BodyEntry(date: Fixtures.date(2025, 2, 24), weightKg: 80.0, measurementsCm: [.waist: 86]),
        BodyEntry(date: Fixtures.date(2025, 3, 3), weightKg: 79.2, bodyFatPct: 15.0, measurementsCm: [.waist: 85]),
        BodyEntry(date: Fixtures.date(2025, 3, 17), weightKg: 78.4, bodyFatPct: 14.2, measurementsCm: [.waist: 83, .armRight: 38.5]),
        BodyEntry(date: Fixtures.date(2025, 3, 31), weightKg: 78.0, measurementsCm: [.armRight: 39.0]),
    ]

    let weightSeries = Stats.bodySeries(of: .weight, in: entries)
    h.check("serie del peso: un punto per rilevazione", weightSeries.count == 4)
    h.check("serie del peso: ordine cronologico", zip(weightSeries, weightSeries.dropFirst()).allSatisfy { $0.date < $1.date })
    h.checkClose("serie del peso: primo valore", weightSeries.first?.value ?? 0, 80.0)

    let fatSeries = Stats.bodySeries(of: .bodyFat, in: entries)
    h.check("serie della massa grassa salta le rilevazioni senza il dato", fatSeries.count == 2)
    h.check("serie di una misura mai registrata è vuota", Stats.bodySeries(of: .measure(.calf), in: entries).isEmpty)
    h.check("serie di una circonferenza", Stats.bodySeries(of: .measure(.waist), in: entries).count == 3)

    h.checkClose("ultimo peso noto", Stats.latestBodyValue(of: .weight, in: entries)?.value ?? 0, 78.0)
    h.checkClose("ultima massa grassa nota", Stats.latestBodyValue(of: .bodyFat, in: entries)?.value ?? 0, 14.2)
    h.checkClose("ultima vita nota", Stats.latestBodyValue(of: .measure(.waist), in: entries)?.value ?? 0, 83)
    h.check("metrica mai registrata non ha ultimo valore", Stats.latestBodyValue(of: .muscleMass, in: entries) == nil)
    h.check("storico vuoto non ha ultimo valore", Stats.latestBodyValue(of: .weight, in: []) == nil)

    h.check("metriche presenti nello storico",
            Stats.recordedBodyMetrics(in: entries) == [.weight, .bodyFat, .measure(.armRight), .measure(.waist)])
    h.check("ultimi valori di tutte le metriche", Stats.latestBodyValues(in: entries).count == 4)

    if let change = Stats.bodyChange(of: .weight, in: entries, since: Fixtures.date(2025, 3, 3)) {
        h.checkClose("riferimento = rilevazione alla data di inizio", change.start.value, 79.2)
        h.checkClose("variazione del peso", change.delta, -1.2, tolerance: 0.000_1)
        h.check("testo della variazione", change.deltaText() == "-1.2 kg")
        h.checkClose("variazione percentuale", change.percentChange ?? 0, -1.515_15, tolerance: 0.001)
    } else {
        h.fail("variazione del peso non calcolata")
    }

    if let change = Stats.bodyChange(of: .measure(.waist), in: entries, since: Fixtures.date(2025, 3, 3)) {
        h.checkClose("variazione della vita", change.delta, -2)
        h.check("testo della variazione in cm", change.deltaText() == "-2 cm")
    } else {
        h.fail("variazione della vita non calcolata")
    }

    if let change = Stats.bodyChange(of: .measure(.armRight), in: entries, since: Fixtures.date(2025, 3, 3)) {
        h.checkClose("senza dato alla data si parte dal primo disponibile", change.start.value, 38.5)
        h.check("testo con segno positivo", change.deltaText() == "+0.5 cm")
    } else {
        h.fail("variazione del braccio non calcolata")
    }

    if let change = Stats.bodyChange(of: .weight, in: [entries[0]], since: Fixtures.date(2025, 3, 3)) {
        h.checkClose("con un solo dato la variazione è zero", change.delta, 0)
        h.check("con un solo dato non c'è percentuale utile", change.percentChange == 0)
    } else {
        h.fail("variazione con un solo dato non calcolata")
    }

    h.check("metrica assente → nessuna variazione", Stats.bodyChange(of: .muscleMass, in: entries, since: Fixtures.date(2025, 3, 3)) == nil)
    h.check("storico vuoto → nessuna variazione", Stats.bodyChange(of: .weight, in: [], since: Date()) == nil)
    h.check("variazioni di tutte le metriche", Stats.bodyChanges(in: entries, since: Fixtures.date(2025, 3, 3)).count == 4)
}
