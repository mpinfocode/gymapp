import CoreGraphics
import Foundation
import ImageIO

/// Un fotogramma decodificato con la sua durata.
///
/// `CGImage` è immutabile e thread-safe ma non dichiarato `Sendable`: il wrapper
/// rende esplicito che il trasferimento fra task è sicuro.
public struct GIFFrame: @unchecked Sendable {
    public let image: CGImage
    /// Durata del fotogramma in secondi.
    public let duration: Double
}

/// Una GIF decodificata: fotogrammi, durate cumulative e durata totale del ciclo.
public struct GIFAnimation: @unchecked Sendable {
    public let frames: [GIFFrame]
    /// Istante di fine di ogni fotogramma, per la ricerca dell'indice.
    public let cumulative: [Double]
    /// Durata totale di un ciclo.
    public let totalDuration: Double
    /// Durata del fotogramma più breve (usata come passo della TimelineView).
    public let shortestFrame: Double

    /// Indice del fotogramma da mostrare a `time` secondi dall'inizio del ciclo.
    public func frameIndex(at time: Double) -> Int {
        guard totalDuration > 0, frames.count > 1 else { return 0 }
        let position = time.truncatingRemainder(dividingBy: totalDuration)
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulative[mid] <= position { low = mid + 1 } else { high = mid }
        }
        return min(low, frames.count - 1)
    }
}

/// Decodifica GIF con ImageIO, senza UIKit/AppKit.
public enum GIFDecoder {

    /// Durata minima ammessa: i browser trattano i delay < 0.011 s come 0.1 s.
    private static let minimumFrameDuration: Double = 0.011
    private static let fallbackFrameDuration: Double = 0.1

    /// Tetto di fotogrammi tenuti in memoria per una GIF.
    ///
    /// Le GIF del dataset stanno sotto questa soglia; quelle più lunghe vengono
    /// campionate in modo uniforme conservando la durata totale del ciclo, così il
    /// movimento resta alla stessa velocità con meno bitmap vive.
    public static let defaultMaximumFrames = 60

    /// Decodifica i fotogrammi. Restituisce `nil` se i dati non sono un'immagine valida.
    ///
    /// Chiamare fuori dal main actor.
    ///
    /// - Parameters:
    ///   - data: byte della GIF.
    ///   - maxPixelSize: lato massimo in pixel di ogni fotogramma. Passando la
    ///     dimensione di resa, ImageIO decodifica direttamente alla scala giusta
    ///     (bitmap più piccole, nessun ricampionamento al disegno). `nil` = originale.
    ///   - maxFrames: tetto ai fotogrammi tenuti in memoria (`nil` = tutti).
    public static func decode(
        _ data: Data,
        maxPixelSize: Int? = nil,
        maxFrames: Int? = nil
    ) -> GIFAnimation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        // Un fotogramma ogni `step`: con `maxFrames` nil o già sufficiente, step = 1.
        let limit = max(maxFrames ?? count, 1)
        let step = max(Int((Double(count) / Double(limit)).rounded(.up)), 1)

        let options: CFDictionary? = maxPixelSize.map { size in
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                // Decodifica adesso, sul task di caricamento, invece che al primo
                // disegno sul main thread.
                kCGImageSourceShouldCacheImmediately: true,
            ] as [CFString: Any] as CFDictionary
        }

        var frames: [GIFFrame] = []
        frames.reserveCapacity((count + step - 1) / step)
        // Durata dei fotogrammi scartati (o non decodificabili): confluisce nel
        // fotogramma tenuto, così la durata del ciclo resta quella originale.
        var carriedDuration = 0.0
        var index = 0
        while index < count {
            let end = min(index + step, count)
            var groupDuration = carriedDuration
            for inner in index..<end {
                groupDuration += frameDuration(source, at: inner)
            }

            let image: CGImage? = if let options {
                CGImageSourceCreateThumbnailAtIndex(source, index, options)
                    ?? CGImageSourceCreateImageAtIndex(source, index, nil)
            } else {
                CGImageSourceCreateImageAtIndex(source, index, nil)
            }
            if let image {
                frames.append(GIFFrame(image: image, duration: groupDuration))
                carriedDuration = 0
            } else {
                carriedDuration = groupDuration
            }
            index = end
        }
        guard !frames.isEmpty else { return nil }
        if carriedDuration > 0, let last = frames.popLast() {
            frames.append(GIFFrame(image: last.image, duration: last.duration + carriedDuration))
        }

        var cumulative: [Double] = []
        cumulative.reserveCapacity(frames.count)
        var running = 0.0
        for frame in frames {
            running += frame.duration
            cumulative.append(running)
        }

        return GIFAnimation(
            frames: frames,
            cumulative: cumulative,
            totalDuration: running,
            shortestFrame: frames.map(\.duration).min() ?? fallbackFrameDuration
        )
    }

    /// Decodifica solo il primo fotogramma, ridimensionato al massimo a `maxPixelSize`.
    public static func decodeStill(_ data: Data, maxPixelSize: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return thumb
            }
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func frameDuration(_ source: CGImageSource, at index: Int) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return fallbackFrameDuration
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? fallbackFrameDuration
        return delay < minimumFrameDuration ? fallbackFrameDuration : delay
    }
}
