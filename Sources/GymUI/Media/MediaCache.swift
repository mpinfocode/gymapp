import CryptoKit
import Foundation

/// Errori della cache dei media remoti.
public enum MediaCacheError: Error, Sendable {
    /// La risposta HTTP non è 2xx.
    case badResponse(status: Int)
    /// Il corpo della risposta è vuoto.
    case emptyData
}

/// Cache su disco dei media degli esercizi (thumbnail e GIF).
///
/// I file vivono in `Application Support/GymApp/Media`, hanno per nome l'hash
/// SHA256 dell'URL e sono esclusi dal backup iCloud (sono riscaricabili).
/// Le richieste per lo stesso URL sono deduplicate: un solo download in volo.
public actor MediaCache {

    /// Istanza condivisa dall'app.
    public static let shared = MediaCache()

    private let directory: URL
    private let session: URLSession

    private var inFlight: [URL: Task<Data, Error>] = [:]

    /// Piccola cache in memoria per evitare riletture da disco durante lo scroll.
    private var memory: [URL: Data] = [:]
    private var memoryOrder: [URL] = []
    private var memoryBytes: Int = 0
    private let memoryLimitBytes: Int

    private var didPrepareDirectory = false

    /// - Parameters:
    ///   - directory: cartella di destinazione; di default `Application Support/GymApp/Media`.
    ///   - session: sessione usata per i download.
    ///   - memoryLimitBytes: tetto della cache in memoria (default 24 MB).
    public init(
        directory: URL? = nil,
        session: URLSession = .shared,
        memoryLimitBytes: Int = 24 * 1024 * 1024
    ) {
        self.directory = directory ?? Self.defaultDirectory()
        self.session = session
        self.memoryLimitBytes = memoryLimitBytes
    }

    // MARK: - API

    /// Restituisce i byte del media, scaricandolo se non è già in cache.
    public func data(for url: URL) async throws -> Data {
        if let cached = memory[url] { return cached }

        let file = fileURL(for: url)
        if let onDisk = try? Data(contentsOf: file), !onDisk.isEmpty {
            remember(onDisk, for: url)
            return onDisk
        }

        if let existing = inFlight[url] {
            return try await existing.value
        }

        let session = self.session
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw MediaCacheError.badResponse(status: http.statusCode)
            }
            guard !data.isEmpty else { throw MediaCacheError.emptyData }
            return data
        }
        inFlight[url] = task

        do {
            let data = try await task.value
            inFlight[url] = nil
            write(data, to: file)
            remember(data, for: url)
            return data
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    /// Indica se il media è già disponibile localmente.
    public func isCached(_ url: URL) -> Bool {
        if memory[url] != nil { return true }
        return FileManager.default.fileExists(atPath: fileURL(for: url).path)
    }

    /// Scarica in anticipo una lista di media con concorrenza limitata.
    ///
    /// - Parameters:
    ///   - urls: media da scaricare; quelli già in cache costano pochissimo.
    ///   - concurrency: download simultanei (default 4).
    ///   - progress: chiamato dopo ogni media con `(completati, totale)`.
    ///     **Non** viene invocato sul main actor: spostarsi esplicitamente se aggiorna la UI.
    /// - Returns: il numero di media effettivamente disponibili al termine.
    @discardableResult
    public func prefetch(
        _ urls: [URL],
        concurrency: Int = 4,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> Int {
        let total = urls.count
        guard total > 0 else { return 0 }

        var completed = 0
        var succeeded = 0
        var nextIndex = 0

        await withTaskGroup(of: Bool.self) { group in
            let limit = max(1, min(concurrency, total))
            while nextIndex < limit {
                let url = urls[nextIndex]
                nextIndex += 1
                group.addTask { [weak self] in
                    guard let self else { return false }
                    return (try? await self.data(for: url)) != nil
                }
            }
            while let ok = await group.next() {
                completed += 1
                if ok { succeeded += 1 }
                progress?(completed, total)
                if nextIndex < total {
                    let url = urls[nextIndex]
                    nextIndex += 1
                    group.addTask { [weak self] in
                        guard let self else { return false }
                        return (try? await self.data(for: url)) != nil
                    }
                }
            }
        }
        return succeeded
    }

    /// Spazio occupato su disco dalla cache, in byte.
    public func cacheSizeBytes() -> Int64 {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return contents.reduce(into: Int64(0)) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }

    /// Svuota cache su disco e in memoria.
    public func clear() {
        memory.removeAll()
        memoryOrder.removeAll()
        memoryBytes = 0
        try? FileManager.default.removeItem(at: directory)
        didPrepareDirectory = false
    }

    // MARK: - Disco

    /// Nome file = SHA256 esadecimale dell'URL assoluto, con l'estensione originale.
    nonisolated func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? hex : "\(hex).\(ext)"
    }

    nonisolated func fileURL(for url: URL) -> URL {
        directory.appendingPathComponent(fileName(for: url), isDirectory: false)
    }

    private func prepareDirectoryIfNeeded() {
        guard !didPrepareDirectory else { return }
        didPrepareDirectory = true

        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    private func write(_ data: Data, to file: URL) {
        prepareDirectoryIfNeeded()
        try? data.write(to: file, options: .atomic)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("GymApp", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

    // MARK: - Memoria

    private func remember(_ data: Data, for url: URL) {
        guard data.count < memoryLimitBytes / 4 else { return }
        if memory[url] == nil {
            memoryOrder.append(url)
            memoryBytes += data.count
        }
        memory[url] = data

        while memoryBytes > memoryLimitBytes, let oldest = memoryOrder.first {
            memoryOrder.removeFirst()
            memoryBytes -= memory[oldest]?.count ?? 0
            memory[oldest] = nil
        }
    }
}
