import SwiftUI

#if os(iOS)
import Combine
import QuartzCore
#endif

/// Etichetta di misura della fluidità: fotogrammi al secondo correnti e durata del
/// fotogramma peggiore degli ultimi 2 secondi.
///
/// Si attiva dalle Impostazioni e si applica con ``SwiftUI/View/frameRateOverlay(_:)``.
/// Su iOS misura con `CADisplayLink`; su macOS (dove gira solo lo strumento di
/// snapshot) è volutamente inerte.
///
/// ## Come si legge
/// - **fps**: fotogrammi consegnati nell'ultimo secondo circa. Su un iPhone ProMotion
///   a riposo scende da solo: conta solo il valore *durante* lo scroll.
/// - **ms**: il fotogramma più lungo degli ultimi 2 secondi. È il numero che conta
///   davvero, perché uno scatto isolato si vede e non sposta la media.
///
/// La lettura si aggiorna 4 volte al secondo: misurare non deve costare un ridisegno
/// a ogni fotogramma.
public struct FrameRateOverlay: View {

    public init() {}

    #if os(iOS)
    @StateObject private var monitor = FrameRateMonitor()

    public var body: some View {
        FrameRateReadout(
            framesPerSecond: monitor.framesPerSecond,
            worstFrameMilliseconds: monitor.worstFrameMilliseconds
        )
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
    #else
    public var body: some View {
        EmptyView()
    }
    #endif
}

/// L'etichetta vera e propria: nessuna misura, solo resa. Cross-platform.
struct FrameRateReadout: View {

    let framesPerSecond: Double
    let worstFrameMilliseconds: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(framesPerSecond > 0 ? "\(Int(framesPerSecond.rounded())) fps" : "fps")
            Text("\(Int(worstFrameMilliseconds.rounded())) ms")
        }
        .font(.system(.caption2, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Theme.onInk)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.ink.opacity(0.85), in: Capsule(style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {

    /// Sovrappone in alto a destra la misura di fluidità (fps e fotogramma peggiore).
    ///
    /// Quando `isVisible` è `false` non viene creato nulla: niente `CADisplayLink`,
    /// niente timer, nessun aggiornamento di stato.
    public func frameRateOverlay(_ isVisible: Bool = true) -> some View {
        overlay(alignment: .topTrailing) {
            if isVisible {
                FrameRateOverlay()
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }
}

#if os(iOS)

/// Campiona la durata dei fotogrammi con `CADisplayLink`.
///
/// Il display link è aggiunto al run loop principale, quindi `step(_:)` arriva sempre
/// sul thread principale come `start()` e `stop()`: il tipo resta volutamente senza
/// annotazione di isolamento, perché `@StateObject` lo costruisce dall'inizializzatore
/// (non isolato) della view. Pubblica al massimo 4 volte al secondo, così la misura
/// non falsa ciò che misura.
final class FrameRateMonitor: NSObject, ObservableObject {

    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var worstFrameMilliseconds: Double = 0

    /// Finestra di osservazione del fotogramma peggiore.
    private let window: CFTimeInterval = 2
    /// Intervallo minimo fra due aggiornamenti della UI.
    private let publishInterval: CFTimeInterval = 0.25

    private var link: CADisplayLink?
    private var previousTimestamp: CFTimeInterval = 0
    private var lastPublish: CFTimeInterval = 0
    private var samples: [Sample] = []

    private struct Sample {
        let timestamp: CFTimeInterval
        let duration: CFTimeInterval
    }

    func start() {
        guard link == nil else { return }
        previousTimestamp = 0
        samples.removeAll(keepingCapacity: true)
        let displayLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        displayLink.add(to: RunLoop.main, forMode: .common)
        link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
        previousTimestamp = 0
        samples.removeAll(keepingCapacity: true)
    }

    @objc
    private func step(_ sender: CADisplayLink) {
        let now = sender.timestamp
        let previous = previousTimestamp
        previousTimestamp = now

        guard previous > 0 else {
            lastPublish = now
            return
        }
        let duration = now - previous
        guard duration > 0 else { return }

        samples.append(Sample(timestamp: now, duration: duration))
        let cutoff = now - window
        if let first = samples.first, first.timestamp < cutoff {
            samples.removeAll { $0.timestamp < cutoff }
        }

        guard now - lastPublish >= publishInterval else { return }
        lastPublish = now

        var total: CFTimeInterval = 0
        var worst: CFTimeInterval = 0
        for sample in samples {
            total += sample.duration
            if sample.duration > worst { worst = sample.duration }
        }
        guard total > 0 else { return }

        let rate = Double(samples.count) / Double(total)
        if abs(rate - framesPerSecond) >= 0.5 {
            framesPerSecond = rate
        }
        let worstMilliseconds = Double(worst) * 1000
        if abs(worstMilliseconds - worstFrameMilliseconds) >= 0.5 {
            worstFrameMilliseconds = worstMilliseconds
        }
    }
}

#endif
