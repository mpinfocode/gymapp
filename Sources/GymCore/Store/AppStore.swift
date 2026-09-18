import Foundation
import Observation

/// Facciata unica fra UI e dati: stato osservabile, mutazioni CRUD, persistenza.
///
/// - Il salvataggio delle collezioni è **debounced** (~300 ms) per non scrivere
///   a ogni battuta di tasto.
/// - La **sessione attiva** viene invece salvata subito a ogni modifica, così
///   sopravvive a un crash o a un kill dell'app (SPEC §4).
/// - Le scritture sono serializzate in coda: l'ultimo stato vince sempre.
@MainActor
@Observable
public final class AppStore {

    // MARK: - Stato osservabile

    /// Tutte le schede, attiva e archiviate.
    public private(set) var programs: [Program] = []
    /// Sessioni concluse, dalla più recente alla più vecchia.
    public private(set) var sessions: [WorkoutSession] = []
    /// Rilevazioni corporee, dalla più recente alla più vecchia.
    public private(set) var bodyEntries: [BodyEntry] = []
    public private(set) var settings = UserSettings()
    /// Sessione in corso, `nil` se non se ne sta svolgendo nessuna.
    public private(set) var activeSession: WorkoutSession?
    /// Libreria esercizi; disponibile dopo ``load()``.
    ///
    /// Contiene **solo** i 1.324 record del dataset (già corretti da
    /// ``ExerciseCorrections``). Per ricerca, filtri e lookup usa i metodi dello
    /// store, che uniscono anche gli esercizi personalizzati.
    public private(set) var exercises: ExerciseRepository?
    /// Esercizi creati dall'utente, compresi quelli eliminati ma ancora citati
    /// dallo storico (``Exercise/isDeleted``). Ordinati per nome.
    public private(set) var customExercises: [Exercise] = []

    /// `true` quando ``load()`` è terminata.
    public private(set) var isLoaded = false
    /// Errori incontrati durante il caricamento (file corrotti, risorsa mancante).
    public private(set) var loadErrors: [String] = []
    /// Ultimo errore di scrittura, da mostrare in Impostazioni.
    public private(set) var saveError: String?
    /// Record battuti nella sessione in corso, per serie. Solo in memoria:
    /// dopo un riavvio dell'app i badge PR della sessione ripristinata non ricompaiono.
    public private(set) var liveRecords: [UUID: Set<Stats.RecordKind>] = [:]

    // MARK: - Dipendenze

    @ObservationIgnored private let store: JSONFileStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored public let calendar: Calendar
    @ObservationIgnored private let saveDelay: Duration

    /// Libreria + personalizzati, ricostruita solo quando i personalizzati cambiano.
    @ObservationIgnored private var mergedLibraryCache: ExerciseRepository?

    @ObservationIgnored private var dirtyFiles: Set<StoreFile> = []
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var writeChain: Task<Void, Never>?

    /// - Parameters:
    ///   - store: persistenza (directory iniettabile).
    ///   - exercises: libreria già caricata; se `nil` viene caricata da ``load()``.
    ///   - calendar: calendario per gli aggregati (default: settimana da lunedì).
    ///   - saveDelay: debounce delle scritture non urgenti.
    ///   - now: sorgente del tempo, iniettabile per i check.
    public init(
        store: JSONFileStore,
        exercises: ExerciseRepository? = nil,
        calendar: Calendar = Stats.weekCalendar(),
        saveDelay: Duration = .milliseconds(300),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.exercises = exercises
        self.calendar = calendar
        self.saveDelay = saveDelay
        self.now = now
    }

    /// Store che scrive in `Application Support/GymApp/`.
    public static func makeDefault() throws -> AppStore {
        AppStore(store: try JSONFileStore.makeDefault())
    }

    /// Istante corrente secondo la sorgente di tempo iniettata.
    public var currentDate: Date { now() }

    // MARK: - Caricamento

    /// Carica tutto da disco. Chiamarla più volte non ha effetto.
    ///
    /// Al primo avvio **non** crea nessuna scheda: la UI mostra un empty state
    /// che invita a crearla o a usare ``loadSampleProgram()``.
    public func load() async {
        guard !isLoaded else { return }

        programs = await loadCollection([Program].self, from: .programs, fallback: [])
        sessions = await loadCollection([WorkoutSession].self, from: .sessions, fallback: [])
            .sorted { $0.startedAt > $1.startedAt }
        bodyEntries = await loadCollection([BodyEntry].self, from: .bodyEntries, fallback: [])
            .sorted { $0.date > $1.date }
        settings = await loadCollection(UserSettings.self, from: .settings, fallback: UserSettings())
        activeSession = await loadOptional(WorkoutSession.self, from: .activeSession)
        customExercises = Self.sortedCustomExercises(
            await loadCollection([Exercise].self, from: .customExercises, fallback: [])
        )

        if exercises == nil {
            do {
                exercises = try await ExerciseRepository.loadFromBundle()
            } catch {
                loadErrors.append("esercizi: \(error)")
            }
        }

        mergedLibraryCache = nil
        isLoaded = true
    }

    private func loadCollection<T: Decodable & Sendable>(_ type: T.Type, from file: StoreFile, fallback: T) async -> T {
        await loadOptional(type, from: file) ?? fallback
    }

    private func loadOptional<T: Decodable & Sendable>(_ type: T.Type, from file: StoreFile) async -> T? {
        do {
            return try await store.load(type, from: file)
        } catch {
            loadErrors.append("\(file.rawValue): \(error)")
            return nil
        }
    }

    /// Crea la scheda d'esempio Push/Pull/Legs e la rende attiva.
    ///
    /// Pensata per il pulsante "Carica scheda d'esempio" dell'empty state.
    @discardableResult
    public func loadSampleProgram() -> Program {
        let program = SampleProgram.make(startDate: now(), now: now())
        addProgram(program, makeActive: true)
        return program
    }

    // MARK: - Esercizi: punto unico di lookup e ricerca

    /// Esercizi personalizzati utilizzabili (esclusi quelli eliminati).
    public var availableCustomExercises: [Exercise] { customExercises.filter(\.isSelectable) }

    /// Libreria + personalizzati utilizzabili, indicizzati insieme.
    ///
    /// È **il** punto da cui passano ricerca, filtri e facet della UI: gli esercizi
    /// dell'utente si comportano in tutto e per tutto come quelli del dataset.
    /// L'indice si ricostruisce solo quando i personalizzati cambiano (operazione
    /// rara), quindi digitare resta istantaneo.
    public var searchableLibrary: ExerciseRepository? {
        if let mergedLibraryCache { return mergedLibraryCache }
        guard let exercises else { return nil }
        let custom = availableCustomExercises
        let merged = custom.isEmpty ? exercises : ExerciseRepository(exercises: exercises.all + custom)
        mergedLibraryCache = merged
        return merged
    }

    /// Esercizio per id, ovunque si trovi: libreria, personalizzati **o** personalizzati
    /// eliminati (questi ultimi servono a non rompere schede e storico).
    public func exercise(id: String) -> Exercise? {
        if let custom = customExercises.first(where: { $0.id == id }) { return custom }
        return exercises?.exercise(id: id)
    }

    /// Nome da mostrare per un id, anche se l'esercizio non esiste più.
    ///
    /// Serve allo storico: una sessione di sei mesi fa deve continuare a dire cosa
    /// si è allenato, non un id nudo.
    public func exerciseDisplayName(id: String, fallback: String = "Esercizio rimosso") -> String {
        exercise(id: id)?.displayName ?? fallback
    }

    /// Dizionario id → esercizio con libreria **e** personalizzati (anche eliminati):
    /// è quello che serve alle statistiche per risolvere tutto lo storico.
    public func allExercisesByID() -> [String: Exercise] {
        var result = exercises?.exercisesByID() ?? [:]
        for exercise in customExercises { result[exercise.id] = exercise }
        return result
    }

    /// Ricerca su libreria + personalizzati.
    public func searchExercises(_ filter: ExerciseFilter = .empty, limit: Int? = nil) -> [Exercise] {
        searchableLibrary?.search(filter, favorites: settings.favoriteExerciseIDs, limit: limit) ?? []
    }

    /// Facet (categoria, attrezzo, target, zona colpita, preferiti) su libreria + personalizzati.
    public func exerciseFacets(for filter: ExerciseFilter = .empty) -> ExerciseFacets {
        searchableLibrary?.facets(for: filter, favorites: settings.favoriteExerciseIDs)
            ?? ExerciseFacets(categories: [], equipment: [], targets: [], favorites: 0, total: 0)
    }

    // MARK: - Esercizi personalizzati (CRUD)

    /// Crea un esercizio personalizzato con id `custom-<uuid>` e nessun media.
    ///
    /// - Returns: `nil` se il nome è vuoto.
    @discardableResult
    public func createCustomExercise(
        name: String,
        category: String = "",
        equipment: String = "",
        target: String = "",
        secondaryMuscles: [String] = [],
        notes: String = ""
    ) -> Exercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let exercise = Exercise.custom(
            name: trimmed,
            category: category,
            equipment: equipment,
            target: target,
            secondaryMuscles: secondaryMuscles,
            notes: notes
        )
        customExercises.append(exercise)
        customExercisesDidChange()
        return exercise
    }

    /// Esercizio personalizzato per id (anche se eliminato).
    public func customExercise(id: String) -> Exercise? {
        customExercises.first { $0.id == id }
    }

    /// Sostituisce un esercizio personalizzato. Ignora gli id sconosciuti e i record
    /// non personalizzati: la libreria del dataset non si modifica.
    public func updateCustomExercise(_ exercise: Exercise) {
        guard exercise.isCustom,
              let index = customExercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        customExercises[index] = exercise
        customExercisesDidChange()
    }

    /// Modifica sul posto i campi di un esercizio personalizzato.
    @discardableResult
    public func editCustomExercise(
        id: String,
        name: String? = nil,
        category: String? = nil,
        equipment: String? = nil,
        target: String? = nil,
        secondaryMuscles: [String]? = nil,
        notes: String? = nil
    ) -> Exercise? {
        guard let index = customExercises.firstIndex(where: { $0.id == id }) else { return nil }
        let current = customExercises[index]
        let newName = (name ?? current.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = Exercise.custom(
            id: current.id,
            name: newName.isEmpty ? current.name : newName,
            category: category ?? current.category,
            equipment: equipment ?? current.equipment,
            target: target ?? current.target,
            secondaryMuscles: secondaryMuscles ?? current.secondaryMuscles,
            notes: notes ?? current.notes,
            isDeleted: current.isDeleted
        )
        customExercises[index] = updated
        customExercisesDidChange()
        return updated
    }

    /// `true` se l'esercizio è citato da una scheda, dallo storico o dalla sessione in corso.
    public func isExerciseInUse(_ exerciseID: String) -> Bool {
        if programs.contains(where: { $0.days.contains { $0.items.contains { $0.exerciseID == exerciseID } } }) {
            return true
        }
        if sessions.contains(where: { $0.entries.contains { $0.exerciseID == exerciseID } }) { return true }
        if activeSession?.entries.contains(where: { $0.exerciseID == exerciseID }) == true { return true }
        return false
    }

    /// Esito di ``deleteCustomExercise(id:)``.
    public enum CustomExerciseDeletion: String, Sendable, Hashable {
        /// L'esercizio non era usato da nessuna parte: rimosso davvero.
        case removed
        /// L'esercizio era citato da scheda/storico: conservato con il flag di eliminato,
        /// così nome e dati restano e lo storico non si rompe.
        case archived
        /// Id sconosciuto o non personalizzato: nessuna modifica.
        case notFound
    }

    /// Elimina un esercizio personalizzato.
    ///
    /// Se è citato da una scheda, da una sessione passata o da quella in corso viene
    /// fatto un **soft delete**: sparisce da ricerca, filtri e picker ma resta
    /// risolvibile per id, quindi lo storico continua a mostrare nome, zona e note
    /// (SPEC §2, punto 5). Viene anche tolto dai preferiti e dai recenti.
    @discardableResult
    public func deleteCustomExercise(id: String) -> CustomExerciseDeletion {
        guard let index = customExercises.firstIndex(where: { $0.id == id }) else { return .notFound }

        var settingsChanged = false
        if settings.favoriteExerciseIDs.remove(id) != nil { settingsChanged = true }
        if settings.recentExerciseIDs.contains(id) {
            settings.recentExerciseIDs.removeAll { $0 == id }
            settingsChanged = true
        }
        if settingsChanged { markDirty(.settings) }

        if isExerciseInUse(id) {
            customExercises[index] = customExercises[index].markingDeleted(true)
            customExercisesDidChange()
            return .archived
        }
        customExercises.remove(at: index)
        customExercisesDidChange()
        return .removed
    }

    /// Rimette in circolazione un personalizzato eliminato (annulla il soft delete).
    @discardableResult
    public func restoreCustomExercise(id: String) -> Exercise? {
        guard let index = customExercises.firstIndex(where: { $0.id == id }) else { return nil }
        customExercises[index] = customExercises[index].markingDeleted(false)
        customExercisesDidChange()
        return customExercises[index]
    }

    private func customExercisesDidChange() {
        customExercises = Self.sortedCustomExercises(customExercises)
        mergedLibraryCache = nil
        markDirty(.customExercises)
    }

    private static func sortedCustomExercises(_ exercises: [Exercise]) -> [Exercise] {
        exercises.sorted { SearchText.normalize($0.name) < SearchText.normalize($1.name) }
    }

    // MARK: - Schede

    /// La scheda attiva, se c'è.
    public var activeProgram: Program? {
        guard let id = settings.activeProgramID else { return nil }
        return programs.first { $0.id == id && !$0.isArchived }
    }

    /// Schede in archivio, dalla più recente.
    public var archivedPrograms: [Program] {
        programs
            .filter { $0.isArchived || $0.id != settings.activeProgramID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func program(id: UUID) -> Program? {
        programs.first { $0.id == id }
    }

    /// Aggiunge una scheda; se `makeActive` è `true` diventa quella attiva.
    public func addProgram(_ program: Program, makeActive: Bool = true) {
        programs.append(program)
        markDirty(.programs)
        if makeActive { activate(programID: program.id) }
    }

    /// Crea una scheda vuota e la rende attiva.
    @discardableResult
    public func createProgram(
        name: String,
        notes: String = "",
        startDate: Date? = nil,
        plannedWeeks: Int? = nil,
        mode: ProgramMode = .rotation,
        activate: Bool = true
    ) -> Program {
        let program = Program(
            name: name,
            notes: notes,
            startDate: startDate ?? now(),
            plannedWeeks: plannedWeeks,
            mode: mode,
            accent: programs.count,
            createdAt: now(),
            updatedAt: now()
        )
        addProgram(program, makeActive: activate)
        return program
    }

    /// Sostituisce una scheda esistente aggiornandone `updatedAt`.
    public func updateProgram(_ program: Program) {
        guard let index = programs.firstIndex(where: { $0.id == program.id }) else { return }
        var updated = program
        updated.updatedAt = now()
        programs[index] = updated
        markDirty(.programs)
    }

    /// Modifica una scheda sul posto.
    public func editProgram(id: UUID, _ change: (inout Program) -> Void) {
        guard let index = programs.firstIndex(where: { $0.id == id }) else { return }
        change(&programs[index])
        programs[index].updatedAt = now()
        markDirty(.programs)
    }

    /// Rende attiva una scheda, archiviando la precedente.
    public func activate(programID: UUID) {
        guard let index = programs.firstIndex(where: { $0.id == programID }) else { return }
        if let previous = settings.activeProgramID, previous != programID,
           let previousIndex = programs.firstIndex(where: { $0.id == previous }) {
            programs[previousIndex].isArchived = true
            programs[previousIndex].updatedAt = now()
        }
        programs[index].isArchived = false
        programs[index].updatedAt = now()
        settings.activeProgramID = programID
        markDirty(.programs, .settings)
    }

    /// Manda una scheda in archivio; se era quella attiva non resta nessuna scheda attiva.
    public func archiveProgram(id: UUID) {
        guard let index = programs.firstIndex(where: { $0.id == id }) else { return }
        programs[index].isArchived = true
        programs[index].updatedAt = now()
        if settings.activeProgramID == id { settings.activeProgramID = nil }
        markDirty(.programs, .settings)
    }

    /// Elimina una scheda. Lo **storico delle sessioni non viene toccato**:
    /// le sessioni restano, semplicemente non puntano più a una scheda esistente.
    public func deleteProgram(id: UUID) {
        programs.removeAll { $0.id == id }
        if settings.activeProgramID == id { settings.activeProgramID = nil }
        markDirty(.programs, .settings)
    }

    /// Duplica una scheda ("nuova scheda partendo da questa"): nuovi id ovunque,
    /// data di inizio a oggi, archiviazione azzerata.
    @discardableResult
    public func duplicateProgram(id: UUID, activate shouldActivate: Bool = false) -> Program? {
        guard let original = program(id: id) else { return nil }
        let copy = Program(
            name: "\(original.name) (copia)",
            notes: original.notes,
            startDate: now(),
            plannedWeeks: original.plannedWeeks,
            mode: original.mode,
            days: original.days.map { day in
                ProgramDay(
                    name: day.name,
                    weekday: day.weekday,
                    items: day.items.map { item in
                        PlanItem(
                            exerciseID: item.exerciseID,
                            targetSets: item.targetSets,
                            measure: item.measure,
                            targetWeightKg: item.targetWeightKg,
                            warmupSets: item.warmupSets,
                            restSeconds: item.restSeconds,
                            supersetGroup: item.supersetGroup,
                            note: item.note
                        )
                    },
                    note: day.note
                )
            },
            accent: original.accent + 1,
            createdAt: now(),
            updatedAt: now()
        )
        addProgram(copy, makeActive: shouldActivate)
        return copy
    }

    // MARK: - Giorni della scheda

    @discardableResult
    public func addDay(name: String, weekday: Weekday? = nil, toProgram programID: UUID) -> ProgramDay {
        let day = ProgramDay(name: name, weekday: weekday)
        editProgram(id: programID) { $0.days.append(day) }
        return day
    }

    public func removeDay(id dayID: UUID, fromProgram programID: UUID) {
        editProgram(id: programID) { $0.days.removeAll { $0.id == dayID } }
    }

    public func editDay(id dayID: UUID, inProgram programID: UUID, _ change: (inout ProgramDay) -> Void) {
        editProgram(id: programID) { program in
            guard let index = program.days.firstIndex(where: { $0.id == dayID }) else { return }
            change(&program.days[index])
        }
    }

    public func moveDays(inProgram programID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        editProgram(id: programID) { $0.days.moveElements(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Esercizi dentro un giorno

    @discardableResult
    public func addItem(
        exerciseID: String,
        toDay dayID: UUID,
        inProgram programID: UUID,
        targetSets: Int = 3,
        measure: SetMeasure = .default
    ) -> PlanItem {
        let item = PlanItem(
            exerciseID: exerciseID,
            targetSets: targetSets,
            measure: measure,
            restSeconds: settings.defaultRestSeconds
        )
        editDay(id: dayID, inProgram: programID) { $0.items.append(item) }
        return item
    }

    /// Aggiunge più esercizi in un colpo solo (picker con selezione multipla).
    public func addItems(exerciseIDs: [String], toDay dayID: UUID, inProgram programID: UUID) {
        let rest = settings.defaultRestSeconds
        editDay(id: dayID, inProgram: programID) { day in
            day.items.append(contentsOf: exerciseIDs.map { PlanItem(exerciseID: $0, restSeconds: rest) })
        }
    }

    public func updateItem(_ item: PlanItem, inDay dayID: UUID, inProgram programID: UUID) {
        editDay(id: dayID, inProgram: programID) { day in
            guard let index = day.items.firstIndex(where: { $0.id == item.id }) else { return }
            day.items[index] = item
        }
    }

    public func removeItem(id itemID: UUID, fromDay dayID: UUID, inProgram programID: UUID) {
        editDay(id: dayID, inProgram: programID) { $0.items.removeAll { $0.id == itemID } }
    }

    public func moveItems(inDay dayID: UUID, inProgram programID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        editDay(id: dayID, inProgram: programID) { $0.items.moveElements(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Allenamento di oggi

    /// Giorno proposto dalla scheda attiva per oggi.
    public func todaysWorkout(on date: Date? = nil) -> Stats.TodaysWorkout {
        guard let program = activeProgram else { return .empty }
        return Stats.todaysWorkout(
            for: program,
            on: date ?? now(),
            sessions: sessions,
            calendar: calendar
        )
    }

    // MARK: - Storico sessioni

    public func session(id: UUID) -> WorkoutSession? {
        sessions.first { $0.id == id }
    }

    /// Sessioni svolte con una certa scheda (per il filtro dello storico).
    public func sessions(ofProgram programID: UUID) -> [WorkoutSession] {
        sessions.filter { $0.programID == programID }
    }

    public func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        markDirty(.sessions)
    }

    public func updateSession(_ session: WorkoutSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
        sessions.sort { $0.startedAt > $1.startedAt }
        markDirty(.sessions)
    }

    // MARK: - Rilevazioni corporee

    /// Registra una rilevazione. Se non contiene alcun dato non viene salvata.
    @discardableResult
    public func addBodyEntry(_ entry: BodyEntry) -> BodyEntry? {
        guard !entry.isEmpty else { return nil }
        bodyEntries.append(entry)
        bodyEntries.sort { $0.date > $1.date }
        markDirty(.bodyEntries)
        return entry
    }

    @discardableResult
    public func addBodyEntry(
        date: Date? = nil,
        weightKg: Double? = nil,
        bodyFatPct: Double? = nil,
        leanMassKg: Double? = nil,
        muscleMassKg: Double? = nil,
        waterPct: Double? = nil,
        measurementsCm: [BodyMeasure: Double] = [:]
    ) -> BodyEntry? {
        addBodyEntry(
            BodyEntry(
                date: date ?? now(),
                weightKg: weightKg,
                bodyFatPct: bodyFatPct,
                leanMassKg: leanMassKg,
                muscleMassKg: muscleMassKg,
                waterPct: waterPct,
                measurementsCm: measurementsCm
            )
        )
    }

    public func updateBodyEntry(_ entry: BodyEntry) {
        guard let index = bodyEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        if entry.isEmpty {
            bodyEntries.remove(at: index)
        } else {
            bodyEntries[index] = entry
            bodyEntries.sort { $0.date > $1.date }
        }
        markDirty(.bodyEntries)
    }

    public func deleteBodyEntry(id: UUID) {
        bodyEntries.removeAll { $0.id == id }
        markDirty(.bodyEntries)
    }

    /// Rilevazione più recente.
    public var latestBodyEntry: BodyEntry? { bodyEntries.first }

    /// Ultimo valore noto di una metrica corporea.
    public func latestBodyValue(of metric: BodyMetricKind) -> Stats.BodyPoint? {
        Stats.latestBodyValue(of: metric, in: bodyEntries)
    }

    /// Serie storica di una metrica corporea.
    public func bodySeries(of metric: BodyMetricKind) -> [Stats.BodyPoint] {
        Stats.bodySeries(of: metric, in: bodyEntries)
    }

    /// Variazione di una metrica dall'inizio della scheda attiva (o da una data data).
    public func bodyChange(of metric: BodyMetricKind, since date: Date? = nil) -> Stats.BodyChange? {
        let reference = date ?? activeProgram?.startDate ?? .distantPast
        return Stats.bodyChange(of: metric, in: bodyEntries, since: reference)
    }

    // MARK: - Impostazioni, preferiti, recenti

    /// Modifica le impostazioni sul posto e programma il salvataggio.
    public func updateSettings(_ change: (inout UserSettings) -> Void) {
        change(&settings)
        markDirty(.settings)
    }

    public func isFavorite(_ exerciseID: String) -> Bool {
        settings.isFavorite(exerciseID)
    }

    @discardableResult
    public func toggleFavorite(_ exerciseID: String) -> Bool {
        if settings.favoriteExerciseIDs.contains(exerciseID) {
            settings.favoriteExerciseIDs.remove(exerciseID)
        } else {
            settings.favoriteExerciseIDs.insert(exerciseID)
        }
        markDirty(.settings)
        return settings.isFavorite(exerciseID)
    }

    public func markRecent(_ exerciseID: String) {
        settings.markRecent(exerciseID)
        markDirty(.settings)
    }

    // MARK: - Sessione attiva

    /// Avvia una sessione da un giorno della scheda indicata.
    ///
    /// Per ogni voce crea `warmupSets` serie di riscaldamento e `targetSets` serie di
    /// lavoro, pre-compilate con il carico previsto dalla scheda oppure, se manca,
    /// con quello dell'ultima volta. Gli esercizi a tempo ricevono la durata prevista.
    ///
    /// Se c'è già una sessione in corso non fa nulla e restituisce quella.
    @discardableResult
    public func startSession(programID: UUID, dayID: UUID) -> WorkoutSession? {
        if let activeSession { return activeSession }
        guard let program = program(id: programID), let day = program.day(id: dayID) else { return nil }

        let started = now()
        let session = WorkoutSession(
            programID: program.id,
            programDayID: day.id,
            name: day.name.isEmpty ? program.name : day.name,
            startedAt: started,
            entries: day.items.map { makeEntry(for: $0, before: started) }
        )
        activeSession = session
        liveRecords = [:]
        persistActiveSession()
        return session
    }

    /// Avvia la sessione proposta per oggi dalla scheda attiva.
    @discardableResult
    public func startTodaysSession() -> WorkoutSession? {
        guard let program = activeProgram, let day = todaysWorkout().programDay else { return nil }
        return startSession(programID: program.id, dayID: day.id)
    }

    /// Avvia un allenamento libero, senza scheda.
    @discardableResult
    public func startFreeSession(name: String = "Allenamento libero") -> WorkoutSession {
        if let activeSession { return activeSession }
        let session = WorkoutSession(name: name, startedAt: now())
        activeSession = session
        liveRecords = [:]
        persistActiveSession()
        return session
    }

    /// Aggiunge un esercizio alla sessione in corso, pre-compilando dall'ultima prestazione.
    @discardableResult
    public func addExerciseToActiveSession(
        _ exerciseID: String,
        targetSets: Int = 3,
        measureKind: MeasureKind = .reps
    ) -> SessionEntry? {
        guard activeSession != nil else { return nil }
        let item = PlanItem(
            exerciseID: exerciseID,
            targetSets: max(1, targetSets),
            measure: measureKind == .duration ? .duration(seconds: 30) : .default,
            restSeconds: settings.defaultRestSeconds
        )
        var entry = makeEntry(for: item, before: now())
        entry.planItemID = nil
        activeSession?.entries.append(entry)
        persistActiveSession()
        return entry
    }

    public func removeEntryFromActiveSession(id entryID: UUID) {
        guard activeSession != nil else { return }
        activeSession?.entries.removeAll { $0.id == entryID }
        persistActiveSession()
    }

    public func moveEntriesInActiveSession(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard activeSession != nil else { return }
        activeSession?.entries.moveElements(fromOffsets: source, toOffset: destination)
        persistActiveSession()
    }

    /// Sostituisce l'esercizio di una riga mantenendo le serie già registrate
    /// (macchina occupata: si cambia attrezzo ma il lavoro fatto resta).
    public func replaceExerciseInActiveSession(entryID: UUID, with exerciseID: String) {
        guard let index = activeSession?.entries.firstIndex(where: { $0.id == entryID }) else { return }
        activeSession?.entries[index].exerciseID = exerciseID
        persistActiveSession()
    }

    public func setNote(_ note: String, forEntry entryID: UUID) {
        guard let index = activeSession?.entries.firstIndex(where: { $0.id == entryID }) else { return }
        activeSession?.entries[index].note = note
        persistActiveSession()
    }

    public func setRestSeconds(_ seconds: Int, forEntry entryID: UUID) {
        guard let index = activeSession?.entries.firstIndex(where: { $0.id == entryID }) else { return }
        activeSession?.entries[index].restSeconds = max(0, seconds)
        persistActiveSession()
    }

    public func setSessionNotes(_ notes: String) {
        guard activeSession != nil else { return }
        activeSession?.notes = notes
        persistActiveSession()
    }

    /// Aggiunge una serie in coda a un esercizio, copiando i valori dall'ultima
    /// serie completata (o, se non ce n'è, dall'ultima riga presente).
    @discardableResult
    public func addSet(toEntry entryID: UUID, kind: SetKind = .normal) -> SetLog? {
        guard let index = activeSession?.entries.firstIndex(where: { $0.id == entryID }),
              let entry = activeSession?.entries[index] else { return nil }
        let template = entry.sets.last { $0.isCompleted && $0.kind.countsTowardVolume } ?? entry.sets.last
        let set = SetLog(
            kind: kind,
            weightKg: template?.weightKg,
            reps: template?.reps,
            durationSec: template?.durationSec
        )
        activeSession?.entries[index].sets.append(set)
        persistActiveSession()
        return set
    }

    public func removeSet(id setID: UUID, fromEntry entryID: UUID) {
        guard let index = activeSession?.entries.firstIndex(where: { $0.id == entryID }) else { return }
        activeSession?.entries[index].sets.removeAll { $0.id == setID }
        liveRecords[setID] = nil
        persistActiveSession()
    }

    /// Aggiorna i campi di una serie (carico, reps, durata, tipo, RPE).
    public func updateSet(id setID: UUID, inEntry entryID: UUID, _ change: (inout SetLog) -> Void) {
        guard let entryIndex = activeSession?.entries.firstIndex(where: { $0.id == entryID }),
              let setIndex = activeSession?.entries[entryIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
        change(&activeSession!.entries[entryIndex].sets[setIndex])
        activeSession!.entries[entryIndex].sets[setIndex].rpe =
            SetLog.normalizedRPE(activeSession!.entries[entryIndex].sets[setIndex].rpe)
        persistActiveSession()
    }

    /// Spunta una serie e restituisce i record personali eventualmente battuti.
    @discardableResult
    public func completeSet(id setID: UUID, inEntry entryID: UUID) -> Set<Stats.RecordKind> {
        guard let entryIndex = activeSession?.entries.firstIndex(where: { $0.id == entryID }),
              let setIndex = activeSession?.entries[entryIndex].sets.firstIndex(where: { $0.id == setID }) else { return [] }

        activeSession!.entries[entryIndex].sets[setIndex].completedAt = now()
        let set = activeSession!.entries[entryIndex].sets[setIndex]
        let exerciseID = activeSession!.entries[entryIndex].exerciseID

        let achieved = Stats.records(
            for: exerciseID,
            achievedBy: set,
            sessionVolumeKg: Stats.volume(of: activeSession!, exerciseID: exerciseID),
            history: sessions,
            earlierSetsInSession: Stats.workingSets(for: exerciseID, in: activeSession!)
        )
        liveRecords[setID] = achieved.isEmpty ? nil : achieved
        persistActiveSession()
        return achieved
    }

    /// Toglie la spunta a una serie.
    public func uncompleteSet(id setID: UUID, inEntry entryID: UUID) {
        updateSet(id: setID, inEntry: entryID) { $0.completedAt = nil }
        liveRecords[setID] = nil
    }

    /// Prestazione precedente per un esercizio, escludendo la sessione in corso.
    public func previousPerformance(for exerciseID: String) -> Stats.PreviousPerformance? {
        Stats.previousPerformance(for: exerciseID, in: sessions)
    }

    /// Hint di progressione per una voce della scheda, in base all'ultima volta.
    public func progressionSuggestion(for item: PlanItem) -> Stats.ProgressionSuggestion? {
        let last = sessions
            .filter { !Stats.workingSets(for: item.exerciseID, in: $0).isEmpty }
            .max { $0.startedAt < $1.startedAt }
        return Stats.progressionSuggestion(
            for: item,
            lastSession: last,
            equipment: exercise(id: item.exerciseID)?.equipment ?? ""
        )
    }

    /// Esercizi con cui sostituire quello indicato (stesso target, poi stessa categoria).
    ///
    /// Cerca fra libreria **e** personalizzati, così la macchina occupata si può
    /// rimpiazzare anche con un esercizio inventato dall'utente.
    public func alternatives(for exerciseID: String, limit: Int = 12) -> [Exercise] {
        guard let repository = searchableLibrary, let exercise = exercise(id: exerciseID) else { return [] }
        return repository.alternatives(for: exercise, favorites: settings.favoriteExerciseIDs, limit: limit)
    }

    /// Chiude la sessione in corso, scarta le serie non spuntate e la archivia.
    ///
    /// - Returns: la sessione archiviata, oppure `nil` se non c'era nulla di registrato
    ///   (in quel caso la sessione viene semplicemente scartata).
    @discardableResult
    public func finishSession(notes: String? = nil) -> WorkoutSession? {
        guard var session = activeSession else { return nil }
        if let notes { session.notes = notes }
        session.endedAt = now()
        session.entries = session.entries.compactMap { entry in
            var trimmed = entry
            trimmed.sets = trimmed.sets.filter(\.isCompleted)
            return trimmed.sets.isEmpty ? nil : trimmed
        }

        activeSession = nil
        liveRecords = [:]
        persistActiveSession()

        guard session.hasLoggedWork else { return nil }

        sessions.append(session)
        sessions.sort { $0.startedAt > $1.startedAt }
        markDirty(.sessions)
        for exerciseID in Set(session.exerciseIDs) { settings.markRecent(exerciseID) }
        markDirty(.settings)
        return session
    }

    /// Abbandona la sessione in corso senza salvarla.
    public func discardSession() {
        activeSession = nil
        liveRecords = [:]
        persistActiveSession()
    }

    /// Costruisce la riga di sessione per una voce di scheda:
    /// serie di riscaldamento + serie di lavoro pre-compilate.
    private func makeEntry(for item: PlanItem, before date: Date) -> SessionEntry {
        let previous = Stats.previousPerformance(for: item.exerciseID, in: sessions, before: date)
        let duration = item.measure.durationSeconds
        let defaultReps = item.measure.repsRange?.lowerBound

        var sets: [SetLog] = (0..<item.warmupSets).map { _ in SetLog(kind: .warmup) }
        sets.append(contentsOf: (0..<max(1, item.targetSets)).map { position -> SetLog in
            let reference = previous.flatMap { performance -> SetLog? in
                performance.sets.indices.contains(position) ? performance.sets[position] : performance.sets.last
            }
            return SetLog(
                kind: .normal,
                weightKg: item.targetWeightKg ?? reference?.weightKg,
                reps: duration == nil ? (reference?.reps ?? defaultReps) : nil,
                durationSec: duration
            )
        })

        return SessionEntry(
            exerciseID: item.exerciseID,
            planItemID: item.id,
            measureKind: item.measure.kind,
            sets: sets,
            note: item.note,
            restSeconds: item.restSeconds > 0 ? item.restSeconds : settings.defaultRestSeconds,
            supersetGroup: item.supersetGroup
        )
    }

    // MARK: - Statistiche pronte all'uso

    /// Riepiloghi settimanali basati sullo storico, sulla libreria corretta e sugli
    /// esercizi personalizzati (anche eliminati: lo storico resta completo).
    public func weeklySummaries() -> [Stats.WeekSummary] {
        Stats.weeklySummaries(
            sessions: sessions,
            exercisesByID: allExercisesByID(),
            calendar: calendar
        )
    }

    /// Riepilogo della settimana corrente.
    public func currentWeekSummary() -> Stats.WeekSummary {
        Stats.weekSummary(
            containing: now(),
            sessions: sessions,
            exercisesByID: allExercisesByID(),
            calendar: calendar
        )
    }

    /// Serie completate per zona colpita su tutto lo storico (o su un sottoinsieme).
    public func setsByMuscleGroup(in sessions: [WorkoutSession]? = nil) -> [MuscleGroup: Int] {
        Stats.setsByMuscleGroup(in: sessions ?? self.sessions, exercisesByID: allExercisesByID())
    }

    public func weekStreak() -> Int {
        Stats.weekStreak(sessions: sessions, asOf: now(), calendar: calendar)
    }

    public func activityGrid(days: Int = 30) -> [Stats.ActivityDay] {
        Stats.activityGrid(sessions: sessions, days: days, asOf: now(), calendar: calendar)
    }

    public func series(for exerciseID: String) -> [Stats.ExerciseDataPoint] {
        Stats.series(for: exerciseID, in: sessions, calendar: calendar)
    }

    public func records(for exerciseID: String) -> Stats.ExerciseRecords? {
        Stats.records(for: exerciseID, in: sessions)
    }

    // MARK: - Backup

    /// Esporta tutto (tranne la sessione in corso) in un unico JSON versionato.
    public func exportBackup() throws -> Data {
        try BackupPayload(
            exportedAt: now(),
            programs: programs,
            sessions: sessions,
            bodyEntries: bodyEntries,
            settings: settings,
            customExercises: customExercises
        ).encoded()
    }

    /// Importa un backup **sostituendo** i dati correnti, poi salva subito su disco.
    ///
    /// La sessione eventualmente in corso viene scartata: il backup non la contiene.
    public func importBackup(_ data: Data) async throws {
        let payload = try BackupPayload.decoded(from: data)
        programs = payload.programs
        sessions = payload.sessions.sorted { $0.startedAt > $1.startedAt }
        bodyEntries = payload.bodyEntries.sorted { $0.date > $1.date }
        settings = payload.settings
        customExercises = Self.sortedCustomExercises(payload.customExercises)
        mergedLibraryCache = nil
        activeSession = nil
        liveRecords = [:]
        persistActiveSession()
        markDirty(.programs, .sessions, .bodyEntries, .settings, .customExercises)
        await flush()
    }

    // MARK: - Persistenza

    /// Segna delle collezioni come da salvare e fa ripartire il debounce.
    private func markDirty(_ files: StoreFile...) {
        dirtyFiles.formUnion(files)
        debounceTask?.cancel()
        let delay = saveDelay
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushDirtyFiles()
        }
    }

    /// Scrive subito tutto quello che è in attesa e aspetta la fine delle scritture.
    ///
    /// Da chiamare quando l'app va in background e nei check.
    public func flush() async {
        debounceTask?.cancel()
        debounceTask = nil
        flushDirtyFiles()
        await writeChain?.value
    }

    private func flushDirtyFiles() {
        guard !dirtyFiles.isEmpty else { return }
        let files = dirtyFiles
        dirtyFiles.removeAll()

        let programsSnapshot = programs
        let sessionsSnapshot = sessions
        let bodySnapshot = bodyEntries
        let settingsSnapshot = settings
        let customSnapshot = customExercises

        enqueueWrite { [weak self] store in
            for file in files.sorted(by: { $0.rawValue < $1.rawValue }) {
                do {
                    switch file {
                    case .programs: try await store.save(programsSnapshot, to: .programs)
                    case .sessions: try await store.save(sessionsSnapshot, to: .sessions)
                    case .bodyEntries: try await store.save(bodySnapshot, to: .bodyEntries)
                    case .settings: try await store.save(settingsSnapshot, to: .settings)
                    case .customExercises: try await store.save(customSnapshot, to: .customExercises)
                    case .activeSession: break // gestita da persistActiveSession()
                    }
                } catch {
                    self?.saveError = "\(file.rawValue): \(error)"
                }
            }
        }
    }

    /// Scrive (o cancella) subito il file della sessione attiva.
    private func persistActiveSession() {
        let snapshot = activeSession
        enqueueWrite { [weak self] store in
            do {
                if let snapshot {
                    try await store.save(snapshot, to: .activeSession)
                } else {
                    try await store.delete(.activeSession)
                }
            } catch {
                self?.saveError = "activeSession: \(error)"
            }
        }
    }

    /// Accoda una scrittura dopo la precedente: l'ordine è garantito, l'ultima vince.
    private func enqueueWrite(_ work: @escaping @MainActor (JSONFileStore) async -> Void) {
        let previous = writeChain
        let store = self.store
        writeChain = Task { @MainActor in
            await previous?.value
            await work(store)
        }
    }
}
