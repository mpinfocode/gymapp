import Foundation

extension Stats {

    /// Un punto della serie storica di una metrica corporea.
    public struct BodyPoint: Sendable, Hashable, Identifiable {
        public let date: Date
        public let value: Double

        public var id: Date { date }

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Variazione di una metrica fra due rilevazioni.
    public struct BodyChange: Sendable, Hashable {
        public let metric: BodyMetricKind
        /// Valore di partenza (riferimento).
        public let start: BodyPoint
        /// Valore più recente.
        public let latest: BodyPoint

        public init(metric: BodyMetricKind, start: BodyPoint, latest: BodyPoint) {
            self.metric = metric
            self.start = start
            self.latest = latest
        }

        /// Differenza fra ultimo e primo valore (negativa se è calato).
        public var delta: Double { latest.value - start.value }

        /// Variazione percentuale rispetto al valore di partenza; `nil` se partiva da 0.
        public var percentChange: Double? {
            guard start.value != 0 else { return nil }
            return delta / start.value * 100
        }

        /// Testo con segno, es. `"+1.5 kg"` / `"-2 cm"`.
        public func deltaText(weightUnit: WeightUnit = .kg) -> String {
            let converted = metric.unit == .kilograms ? weightUnit.value(fromKilograms: delta) : delta
            let sign = converted > 0 ? "+" : ""
            let symbol = metric.unit == .kilograms ? weightUnit.symbol : metric.unit.symbol
            return "\(sign)\(WeightUnit.trimmedNumber(converted, fractionDigits: metric.unit.fractionDigits)) \(symbol)"
        }
    }

    // MARK: - Serie storiche

    /// Serie storica di una metrica, dal più vecchio al più recente.
    ///
    /// Le rilevazioni che non contengono quella metrica vengono saltate; a parità
    /// di data vince l'ultima rilevazione inserita.
    public static func bodySeries(of metric: BodyMetricKind, in entries: [BodyEntry]) -> [BodyPoint] {
        entries
            .compactMap { entry in metric.value(in: entry).map { BodyPoint(date: entry.date, value: $0) } }
            .sorted { $0.date < $1.date }
    }

    /// Ultimo valore noto di una metrica.
    public static func latestBodyValue(of metric: BodyMetricKind, in entries: [BodyEntry]) -> BodyPoint? {
        bodySeries(of: metric, in: entries).last
    }

    /// Ultimi valori noti di tutte le metriche registrate almeno una volta,
    /// nell'ordine canonico di ``BodyMetricKind``.
    public static func latestBodyValues(in entries: [BodyEntry]) -> [(metric: BodyMetricKind, point: BodyPoint)] {
        BodyMetricKind.allCases.compactMap { metric in
            latestBodyValue(of: metric, in: entries).map { (metric, $0) }
        }
    }

    /// Metriche che compaiono almeno una volta nello storico.
    public static func recordedBodyMetrics(in entries: [BodyEntry]) -> [BodyMetricKind] {
        BodyMetricKind.allCases.filter { metric in
            entries.contains { metric.value(in: $0) != nil }
        }
    }

    // MARK: - Variazioni

    /// Variazione di una metrica da una data in poi (tipicamente l'inizio della scheda).
    ///
    /// Il riferimento è l'ultima rilevazione **a quella data o prima**; se non esiste,
    /// la prima rilevazione successiva. Restituisce `nil` se la metrica non è mai stata
    /// registrata. Con un solo dato disponibile la variazione è zero.
    public static func bodyChange(
        of metric: BodyMetricKind,
        in entries: [BodyEntry],
        since date: Date
    ) -> BodyChange? {
        let series = bodySeries(of: metric, in: entries)
        guard let latest = series.last else { return nil }
        let start = series.last { $0.date <= date } ?? series[0]
        return BodyChange(metric: metric, start: start, latest: latest)
    }

    /// Variazioni di tutte le metriche registrate, nell'ordine canonico.
    public static func bodyChanges(in entries: [BodyEntry], since date: Date) -> [BodyChange] {
        BodyMetricKind.allCases.compactMap { bodyChange(of: $0, in: entries, since: date) }
    }
}
