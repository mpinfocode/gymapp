import Foundation
import Observation
import GymUI

/// Stato del download offline dei media e dello spazio occupato dalla cache.
///
/// Vive quanto la schermata Impostazioni: se la si chiude il download si annulla.
/// Il callback di avanzamento di ``MediaCache/prefetch(_:concurrency:progress:)``
/// **non** arriva sul main actor, quindi qui si torna esplicitamente sulla UI.
@MainActor
@Observable
final class MediaDownloadModel {

    /// Fase corrente del download.
    enum Phase: Equatable {
        case idle
        case running(done: Int, total: Int)
        case finished(available: Int, total: Int)
    }

    private(set) var phase: Phase = .idle
    /// Spazio occupato su disco, in byte.
    private(set) var cacheBytes: Int64 = 0

    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Spazio occupato, in italiano: "12,4 MB", "meno di 0,1 MB", "vuota".
    var cacheSizeText: String {
        guard cacheBytes > 0 else { return "vuota" }
        let megabytes = Double(cacheBytes) / (1024 * 1024)
        guard megabytes >= 0.1 else { return "meno di \(Formatters.decimal(0.1)) MB" }
        return "\(Formatters.decimal(megabytes)) MB"
    }

    /// Riga di stato del download, `nil` quando non c'è niente da dire.
    var progressText: String? {
        switch phase {
        case .idle:
            return nil
        case .running(let done, let total):
            return "\(Formatters.integer(done)) di \(Formatters.integer(total))"
        case .finished(let available, let total):
            return available >= total
                ? "Tutti i media sono disponibili offline."
                : "\(Formatters.integer(available)) media su \(Formatters.integer(total)) disponibili offline."
        }
    }

    /// Frazione completata, per la barra.
    var fraction: Double {
        guard case .running(let done, let total) = phase, total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    // MARK: - Azioni

    func refreshSize() async {
        cacheBytes = await MediaCache.shared.cacheSizeBytes()
    }

    func start(urls: [URL]) {
        guard !isRunning, !urls.isEmpty else { return }
        let total = urls.count
        phase = .running(done: 0, total: total)

        // Il callback arriva da un task figlio di `prefetch`, non dal main actor:
        // si rientra sulla UI con un hop esplicito.
        let progress: @Sendable (Int, Int) -> Void = { [weak self] done, count in
            Task { @MainActor in
                self?.report(done: done, total: count)
            }
        }

        task = Task { @MainActor [weak self] in
            let available = await MediaCache.shared.prefetch(urls, concurrency: 6, progress: progress)
            guard let self, !Task.isCancelled else { return }
            self.phase = .finished(available: available, total: total)
            await self.refreshSize()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func clearCache() async {
        cancel()
        await MediaCache.shared.clear()
        await refreshSize()
    }

    private func report(done: Int, total: Int) {
        guard case .running = phase else { return }
        phase = .running(done: done, total: total)
    }
}
