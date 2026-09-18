import Foundation
import GymCore

/// Mini-harness di test: niente XCTest/Swift Testing (non disponibili, vedi SPEC §1.2).
@MainActor
final class Harness {

    private(set) var passed = 0
    private(set) var failed = 0
    private var failures: [String] = []
    private var section = "generale"
    private var sectionPassed = 0
    private var sectionFailed = 0

    /// Apre una nuova sezione di check (stampa il riepilogo di quella precedente).
    func section(_ name: String) {
        closeSection()
        section = name
        sectionPassed = 0
        sectionFailed = 0
    }

    /// Verifica una condizione. Restituisce l'esito, così i check successivi
    /// possono essere saltati quando una precondizione fallisce.
    @discardableResult
    func check(_ message: String, _ condition: Bool) -> Bool {
        if condition {
            passed += 1
            sectionPassed += 1
        } else {
            failed += 1
            sectionFailed += 1
            failures.append("[\(section)] \(message)")
            print("   ✗ \(message)")
        }
        return condition
    }

    /// Registra un fallimento incondizionato (precondizione mancante, throw inatteso).
    func fail(_ message: String) {
        check(message, false)
    }

    /// Confronto fra `Double` con tolleranza.
    @discardableResult
    func checkClose(_ message: String, _ value: Double, _ expected: Double, tolerance: Double = 0.000_1) -> Bool {
        check("\(message) (atteso ~\(expected), ottenuto \(value))", abs(value - expected) <= tolerance)
    }

    /// Confronto fra date con tolleranza (la codifica ISO 8601 arrotonda al secondo).
    @discardableResult
    func checkClose(_ message: String, _ value: Date, _ expected: Date, tolerance: TimeInterval = 1.0) -> Bool {
        check(message, abs(value.timeIntervalSince(expected)) <= tolerance)
    }

    private func closeSection() {
        guard sectionPassed + sectionFailed > 0 else { return }
        let mark = sectionFailed == 0 ? "✓" : "✗"
        print("\(mark) \(section): \(sectionPassed) ok, \(sectionFailed) ko")
    }

    /// Stampa il riepilogo finale ed esce con codice 1 se qualcosa è fallito.
    func report() -> Never {
        closeSection()
        print("")
        if failures.isEmpty {
            print("GymChecks: \(passed) check superati, 0 falliti.")
            exit(0)
        }
        print("GymChecks: \(passed) superati, \(failed) FALLITI")
        for failure in failures { print("  · \(failure)") }
        exit(1)
    }
}

/// Sorgente del tempo controllabile dai check.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) { value = start }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }

    func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        value = date
    }

    /// Closure da passare ad `AppStore(now:)`.
    var provider: @Sendable () -> Date { { [self] in now } }
}

/// Cartella temporanea isolata, cancellata a fine processo.
enum TempDirectory {
    static func make() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymChecks-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Calendario e date fisse usate dai check delle statistiche (fuso Europe/Rome).
enum Fixtures {
    static let calendar: Calendar = Stats.weekCalendar(timeZone: TimeZone(identifier: "Europe/Rome") ?? .gmt)

    /// Data costruita nel fuso di riferimento; ora di default 12:00 per stare
    /// lontani dai bordi del giorno.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
