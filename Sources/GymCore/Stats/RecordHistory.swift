import Foundation

extension Stats {

    /// Un record battuto in una sessione dello storico.
    ///
    /// È il dato con cui si costruisce la sezione "Record" di Progressi: quando è
    /// successo, su quale esercizio, di che tipo, con quale valore e **quale valore
    /// ha battuto** (la riga "prima 80 kg").
    public struct RecordEntry: Sendable, Hashable, Identifiable {
        /// Sessione in cui il record è stato battuto.
        public let sessionID: UUID
        public let exerciseID: String
        /// Inizio della sessione.
        public let date: Date
        public let kind: RecordKind
        /// Nuovo primato.
        public let value: Double
        /// Primato precedente, sempre minore di ``value``.
        public let previousValue: Double

        public var id: String { "\(sessionID.uuidString)-\(exerciseID)-\(kind.rawValue)" }

        /// Di quanto è migliorato il primato.
        public var improvement: Double { value - previousValue }

        public init(
            sessionID: UUID,
            exerciseID: String,
            date: Date,
            kind: RecordKind,
            value: Double,
            previousValue: Double
        ) {
            self.sessionID = sessionID
            self.exerciseID = exerciseID
            self.date = date
            self.kind = kind
            self.value = value
            self.previousValue = previousValue
        }
    }

    /// Cronologia dei record, dal più recente al più vecchio. Funzione pura.
    ///
    /// Regole (le stesse già adottate dalla UI Progressi):
    /// - la **prima comparsa** di un esercizio non è un record: senza un primato
    ///   precedente non c'è niente da battere, e contarla riempirebbe la lista di
    ///   "record" nati solo dal primo allenamento;
    /// - le serie di **riscaldamento** non contano (né quelle non spuntate);
    /// - una sessione produce al massimo un record per esercizio e per tipo, con il
    ///   valore migliore della sessione;
    /// - il pareggio non è un record: serve un valore **strettamente** maggiore.
    ///
    /// Il rilevamento in tempo reale durante l'allenamento
    /// (``Stats/records(for:achievedBy:sessionVolumeKg:history:earlierSetsInSession:)``)
    /// resta più generoso: lì la prima serie in assoluto è comunque un'informazione
    /// utile da mostrare in palestra.
    ///
    /// - Parameters:
    ///   - sessions: storico, in qualunque ordine.
    ///   - kinds: tipi di record da calcolare. Il default è il solo carico massimo,
    ///     che è la lettura mostrata nella schermata Record.
    public static func recordHistory(
        in sessions: [WorkoutSession],
        kinds: Set<RecordKind> = [.maxWeight]
    ) -> [RecordEntry] {
        guard !kinds.isEmpty else { return [] }

        var best: [RecordKind: [String: Double]] = [:]
        var entries: [RecordEntry] = []

        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for kind in RecordKind.allCases where kinds.contains(kind) {
                let values = sessionValues(of: kind, in: session)
                var reached = best[kind] ?? [:]
                for exerciseID in values.keys.sorted() {
                    guard let value = values[exerciseID], value > 0 else { continue }
                    guard let previous = reached[exerciseID] else {
                        reached[exerciseID] = value
                        continue
                    }
                    guard value > previous else { continue }
                    reached[exerciseID] = value
                    entries.append(
                        RecordEntry(
                            sessionID: session.id,
                            exerciseID: exerciseID,
                            date: session.startedAt,
                            kind: kind,
                            value: value,
                            previousValue: previous
                        )
                    )
                }
                best[kind] = reached
            }
        }

        return entries.sorted(by: isMoreRecent)
    }

    /// Esercizi migliorati in un periodo: **un record per esercizio**, il più recente.
    ///
    /// È la forma con cui i record si mostrano all'utente. Chi progredisce ogni
    /// settimana batte il proprio carico di continuo: elencare ogni singolo primato
    /// riempirebbe la pagina di righe uguali e il conteggio grezzo ("63 record") non
    /// direbbe niente. Contano gli **esercizi migliorati**, quindi
    /// `improvedExercises(...).count` è il numero da mostrare.
    ///
    /// - Parameters:
    ///   - from: inizio del periodo, incluso.
    ///   - to: fine del periodo, inclusa.
    public static func improvedExercises(
        in sessions: [WorkoutSession],
        kinds: Set<RecordKind> = [.maxWeight],
        from: Date = .distantPast,
        to: Date = .distantFuture
    ) -> [RecordEntry] {
        latestPerExercise(recordHistory(in: sessions, kinds: kinds).filter { $0.date >= from && $0.date <= to })
    }

    /// Un record per esercizio (il più recente) da una cronologia già calcolata.
    public static func latestPerExercise(_ entries: [RecordEntry]) -> [RecordEntry] {
        var seen: Set<String> = []
        return entries.sorted(by: isMoreRecent).filter { seen.insert($0.exerciseID).inserted }
    }

    /// Record battuti in una certa sessione, per esercizio.
    public static func records(inSession sessionID: UUID, entries: [RecordEntry]) -> [String: RecordEntry] {
        var result: [String: RecordEntry] = [:]
        for entry in entries.sorted(by: isMoreRecent) where entry.sessionID == sessionID {
            if result[entry.exerciseID] == nil { result[entry.exerciseID] = entry }
        }
        return result
    }

    /// Miglior valore di ogni esercizio dentro una sessione, per un tipo di record.
    private static func sessionValues(of kind: RecordKind, in session: WorkoutSession) -> [String: Double] {
        var result: [String: Double] = [:]
        for entry in session.entries {
            let sets = entry.sets.filter(\.isWorkingSet)
            guard !sets.isEmpty else { continue }
            let value: Double?
            switch kind {
            case .maxWeight: value = sets.compactMap(\.weightKg).max()
            case .best1RM: value = best1RM(in: sets)
            case .sessionVolume: value = sets.reduce(0) { $0 + $1.volumeKg }
            }
            guard let value else { continue }
            if kind == .sessionVolume {
                // L'esercizio può comparire su più righe: il volume di sessione si somma.
                result[entry.exerciseID, default: 0] += value
            } else {
                result[entry.exerciseID] = max(result[entry.exerciseID] ?? 0, value)
            }
        }
        return result
    }

    /// Ordinamento stabile: prima i più recenti, poi esercizio, poi tipo di record.
    private static func isMoreRecent(_ lhs: RecordEntry, _ rhs: RecordEntry) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.exerciseID != rhs.exerciseID { return lhs.exerciseID < rhs.exerciseID }
        let order = RecordKind.allCases
        return (order.firstIndex(of: lhs.kind) ?? 0) < (order.firstIndex(of: rhs.kind) ?? 0)
    }

    // MARK: - Ricostruzione dei badge della sessione in corso

    /// Ricalcola i record battuti dalle serie **già spuntate** di una sessione.
    ///
    /// Serve a ricostruire i badge PR della sessione in corso dopo un riavvio
    /// dell'app: le serie vengono ripercorse nell'ordine in cui sono state
    /// completate e confrontate con lo storico e con le serie precedenti della
    /// stessa sessione, esattamente come fa il calcolo in tempo reale.
    ///
    /// - Parameters:
    ///   - session: la sessione da ricostruire (tipicamente quella attiva).
    ///   - history: sessioni **concluse**, senza quella in corso.
    /// - Returns: i record per id di serie; le serie senza record non compaiono.
    public static func liveRecords(
        in session: WorkoutSession,
        history: [WorkoutSession]
    ) -> [UUID: Set<RecordKind>] {
        struct Completed {
            let date: Date
            let entryIndex: Int
            let setIndex: Int
            let exerciseID: String
            let set: SetLog
        }

        var completed: [Completed] = []
        for (entryIndex, entry) in session.entries.enumerated() {
            for (setIndex, set) in entry.sets.enumerated() where set.isCompleted {
                completed.append(
                    Completed(
                        date: set.completedAt ?? session.startedAt,
                        entryIndex: entryIndex,
                        setIndex: setIndex,
                        exerciseID: entry.exerciseID,
                        set: set
                    )
                )
            }
        }
        completed.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.entryIndex != rhs.entryIndex { return lhs.entryIndex < rhs.entryIndex }
            return lhs.setIndex < rhs.setIndex
        }

        var result: [UUID: Set<RecordKind>] = [:]
        var earlier: [String: [SetLog]] = [:]
        var volume: [String: Double] = [:]

        for item in completed {
            volume[item.exerciseID, default: 0] += item.set.volumeKg
            let achieved = records(
                for: item.exerciseID,
                achievedBy: item.set,
                sessionVolumeKg: volume[item.exerciseID] ?? 0,
                history: history,
                earlierSetsInSession: earlier[item.exerciseID] ?? []
            )
            if !achieved.isEmpty { result[item.set.id] = achieved }
            if item.set.isWorkingSet { earlier[item.exerciseID, default: []].append(item.set) }
        }
        return result
    }
}
