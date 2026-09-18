import CoreGraphics
import Foundation

/// Cache in memoria delle immagini **già decodificate**.
///
/// ``MediaCache`` conserva i byte (rete e disco); qui vivono i `CGImage` pronti per
/// la composizione. Serve allo scroll: quando una riga ricompare, la thumbnail è
/// disponibile **sincronamente**, prima di qualunque `await`, quindi la cella nasce
/// già piena al primo fotogramma invece di passare dal segnaposto.
///
/// È costruita su `NSCache`, quindi è thread-safe e si svuota da sola quando il
/// sistema è sotto pressione di memoria (su iOS si aggiunge anche l'ascolto
/// esplicito dell'avviso di memoria).
///
/// La chiave è URL + lato in pixel: la stessa immagine a due dimensioni di resa è
/// decodificata due volte, e la ricerca "a qualsiasi dimensione" (``anyImage(for:)``)
/// serve a chi vuole solo un poster provvisorio.
public final class DecodedImageCache: @unchecked Sendable {

    /// Istanza condivisa dall'app.
    public static let shared = DecodedImageCache()

    /// Box di riferimento: `NSCache` accetta solo tipi classe, e il costo per voce
    /// si calcola una volta sola alla scrittura.
    private final class Entry {
        let image: CGImage
        let bytes: Int

        init(image: CGImage) {
            self.image = image
            self.bytes = max(image.height * image.bytesPerRow, 1)
        }
    }

    private let storage = NSCache<NSString, Entry>()

    /// Indice dei lati in pixel noti per ogni URL, per ``anyImage(for:)``.
    /// Piccolo (poche decine di byte per voce) e protetto da un lock: le voci
    /// eliminate da `NSCache` restano finché non le si incontra, e allora si potano.
    private let lock = NSLock()
    private var knownSides: [URL: [Int]] = [:]

    /// - Parameters:
    ///   - countLimit: numero massimo di immagini tenute (default 160: molte più
    ///     delle righe visibili, così un giro avanti e indietro nella lista non
    ///     ridecodifica nulla).
    ///   - totalCostLimit: tetto in byte dei pixel decodificati (default 48 MB:
    ///     circa 1300 thumbnail 96×96 RGBA, o 150 immagini 360×360).
    public init(countLimit: Int = 160, totalCostLimit: Int = 48 * 1024 * 1024) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
        storage.name = "GymUI.DecodedImageCache"
        observeMemoryPressure()
    }

    // MARK: - API

    /// Immagine decodificata esattamente a quel lato in pixel, se presente.
    ///
    /// Non fa I/O e non attende nulla: si può chiamare dentro `body`.
    public func image(for url: URL?, pixelSide: Int) -> CGImage? {
        guard let url else { return nil }
        return storage.object(forKey: Self.key(url, pixelSide))?.image
    }

    /// Immagine decodificata dello stesso URL a **una qualsiasi** dimensione già in
    /// cache, la più grande disponibile.
    ///
    /// Usata per il poster: meglio un fotogramma leggermente scalato subito che una
    /// tile vuota per mezzo secondo.
    public func anyImage(for url: URL?) -> CGImage? {
        guard let url else { return nil }
        lock.lock()
        let sides = knownSides[url] ?? []
        lock.unlock()
        guard !sides.isEmpty else { return nil }

        var best: CGImage?
        var bestSide = 0
        var alive: [Int] = []
        for side in sides.sorted(by: >) {
            guard let entry = storage.object(forKey: Self.key(url, side)) else { continue }
            alive.append(side)
            if side > bestSide {
                best = entry.image
                bestSide = side
            }
        }

        lock.lock()
        if alive.isEmpty {
            knownSides[url] = nil
        } else if alive.count != sides.count {
            knownSides[url] = alive
        }
        lock.unlock()

        return best
    }

    /// Memorizza un'immagine decodificata.
    public func insert(_ image: CGImage, for url: URL, pixelSide: Int) {
        let entry = Entry(image: image)
        storage.setObject(entry, forKey: Self.key(url, pixelSide), cost: entry.bytes)

        lock.lock()
        var sides = knownSides[url] ?? []
        if !sides.contains(pixelSide) {
            sides.append(pixelSide)
            knownSides[url] = sides
        }
        // L'indice non deve crescere senza fine se l'app vive a lungo.
        if knownSides.count > 2048 { knownSides = [url: sides] }
        lock.unlock()
    }

    /// Svuota la cache (es. dal bottone "svuota cache" delle impostazioni).
    public func removeAll() {
        storage.removeAllObjects()
        lock.lock()
        knownSides.removeAll()
        lock.unlock()
    }

    // MARK: - Interni

    private static func key(_ url: URL, _ pixelSide: Int) -> NSString {
        "\(url.absoluteString)|\(pixelSide)" as NSString
    }

    private func observeMemoryPressure() {
        #if os(iOS)
        // Nome grezzo invece di `UIApplication.didReceiveMemoryWarningNotification`:
        // identico a runtime, ma non trascina UIKit né l'isolamento al main actor
        // in un tipo che deve restare utilizzabile da qualunque thread.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.removeAll()
        }
        #endif
    }
}
