import Foundation
import Observation
import GymCore

#if canImport(UserNotifications)
import UserNotifications
#endif

/// Timer di recupero della sessione.
///
/// Vive **fuori** dalla vita della view: la cover della sessione può essere
/// minimizzata e riaperta, il recupero continua lo stesso. Il conto alla rovescia
/// è basato su una **data assoluta** (``endsAt``), quindi sopravvive a background,
/// minimizzazione e sospensione: non c'è nessun contatore che possa "perdere colpi".
///
/// La vista legge il tempo restante passando il proprio "adesso"
/// (``AppEnvironment/now``), così gli screenshot restano riproducibili.
@MainActor
@Observable
public final class SessionRestTimer {

    /// Istanza condivisa da tutta la sessione.
    public static let shared = SessionRestTimer()

    /// Sessione a cui appartiene il recupero in corso.
    public private(set) var sessionID: UUID?
    /// Esercizio che ha fatto partire il recupero.
    public private(set) var entryID: UUID?
    /// Nome dell'esercizio, per il pannello e per la notifica.
    public private(set) var exerciseName: String = ""
    /// Istante di fine del recupero; `nil` quando non sta correndo niente.
    public private(set) var endsAt: Date?
    /// Durata totale, per l'anello che si svuota.
    public private(set) var totalSeconds: Int = 0

    @ObservationIgnored private var didAskPermission = false

    /// Identificatore unico: c'è sempre al massimo un recupero programmato.
    private static let notificationID = "gymapp.rest.finished"

    public init() {}

    public var isRunning: Bool { endsAt != nil }

    /// Secondi mancanti a una certa data (0 quando il recupero è finito).
    public func remaining(asOf date: Date) -> Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(date).rounded()))
    }

    /// Avvia il recupero dopo una serie completata.
    public func start(
        seconds: Int,
        entryID: UUID,
        exerciseName: String,
        sessionID: UUID,
        now: Date
    ) {
        guard seconds > 0 else {
            stop()
            return
        }
        self.sessionID = sessionID
        self.entryID = entryID
        self.exerciseName = exerciseName
        totalSeconds = seconds
        endsAt = now.addingTimeInterval(TimeInterval(seconds))
        askPermissionIfNeeded()
        scheduleNotification(after: seconds)
    }

    /// Riprende un recupero dedotto dalla sessione salvata (vedi ``SessionPresentation/pendingRest(in:asOf:)``).
    public func restore(
        endsAt: Date,
        totalSeconds: Int,
        entryID: UUID,
        exerciseName: String,
        sessionID: UUID,
        now: Date
    ) {
        self.sessionID = sessionID
        self.entryID = entryID
        self.exerciseName = exerciseName
        self.totalSeconds = max(totalSeconds, 1)
        self.endsAt = endsAt
        scheduleNotification(after: remaining(asOf: now))
    }

    /// Sposta la fine del recupero di `seconds` (usato da "-15" e "+15").
    public func adjust(by seconds: Int, now: Date) {
        guard let current = endsAt else { return }
        let updated = max(now, current.addingTimeInterval(TimeInterval(seconds)))
        endsAt = updated
        totalSeconds = max(totalSeconds, remaining(asOf: now))
        scheduleNotification(after: remaining(asOf: now))
    }

    /// Ferma il recupero (salta, fine naturale, fine sessione).
    public func stop() {
        endsAt = nil
        entryID = nil
        exerciseName = ""
        totalSeconds = 0
        cancelNotification()
    }

    /// Azzera tutto quando cambia sessione.
    public func reset(for sessionID: UUID?) {
        guard self.sessionID != sessionID else { return }
        self.sessionID = sessionID
        stop()
    }

    // MARK: - Notifica locale

    /// `true` solo dentro un'app vera: gli eseguibili da riga di comando (gli
    /// screenshot) non hanno bundle e non devono toccare il centro notifiche.
    private var canUseNotifications: Bool {
        #if canImport(UserNotifications)
        return Bundle.main.bundleIdentifier != nil
        #else
        return false
        #endif
    }

    /// Permesso chiesto al **primo recupero**, non all'avvio dell'app.
    private func askPermissionIfNeeded() {
        #if canImport(UserNotifications)
        guard canUseNotifications, !didAskPermission else { return }
        didAskPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        #endif
    }

    private func scheduleNotification(after seconds: Int) {
        #if canImport(UserNotifications)
        guard canUseNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recupero finito"
        content.body = exerciseName.isEmpty ? "Si riparte." : "Si riparte con \(exerciseName)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        )
        center.add(request) { _ in }
        #endif
    }

    private func cancelNotification() {
        #if canImport(UserNotifications)
        guard canUseNotifications else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        #endif
    }
}

/// Cronometro della singola serie a tempo (plank, cardio).
///
/// Anche qui il tempo si misura fra due date assolute: mettere l'app in background
/// non falsa i secondi registrati. Il valore viene scritto nella serie solo allo
/// stop, così non si salva il file della sessione una volta al secondo.
@MainActor
@Observable
public final class SessionSetStopwatch {

    public static let shared = SessionSetStopwatch()

    /// Serie attualmente cronometrata.
    public private(set) var setID: UUID?
    private var startedAt: Date?

    public init() {}

    public func isRunning(_ setID: UUID) -> Bool { self.setID == setID }

    /// Secondi trascorsi dall'avvio.
    public func elapsed(asOf date: Date) -> Int {
        guard let startedAt else { return 0 }
        return max(0, Int(date.timeIntervalSince(startedAt).rounded()))
    }

    public func start(setID: UUID, now: Date) {
        self.setID = setID
        startedAt = now
    }

    /// Ferma il cronometro e restituisce i secondi reali da salvare.
    @discardableResult
    public func stop(asOf date: Date) -> Int {
        let seconds = elapsed(asOf: date)
        setID = nil
        startedAt = nil
        return seconds
    }

    public func stop() {
        setID = nil
        startedAt = nil
    }
}
