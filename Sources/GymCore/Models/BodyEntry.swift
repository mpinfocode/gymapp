import Foundation

/// Circonferenze corporee misurabili, in centimetri.
public enum BodyMeasure: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case neck
    case shoulders
    case chest
    case armRight
    case armLeft
    case forearm
    case waist
    case hips
    case thighRight
    case thighLeft
    case calf

    public var id: String { rawValue }

    /// Nome esteso in italiano.
    public var displayName: String {
        switch self {
        case .neck: "Collo"
        case .shoulders: "Spalle"
        case .chest: "Petto"
        case .armRight: "Braccio destro"
        case .armLeft: "Braccio sinistro"
        case .forearm: "Avambraccio"
        case .waist: "Vita"
        case .hips: "Fianchi"
        case .thighRight: "Coscia destra"
        case .thighLeft: "Coscia sinistra"
        case .calf: "Polpaccio"
        }
    }

    /// Nome compatto per le card strette ("Braccio dx").
    public var shortName: String {
        switch self {
        case .armRight: "Braccio dx"
        case .armLeft: "Braccio sx"
        case .thighRight: "Coscia dx"
        case .thighLeft: "Coscia sx"
        default: displayName
        }
    }
}

/// Unità di misura di una metrica corporea.
public enum BodyMetricUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case kilograms
    case centimeters
    case percent

    public var symbol: String {
        switch self {
        case .kilograms: "kg"
        case .centimeters: "cm"
        case .percent: "%"
        }
    }

    /// Cifre decimali con cui ha senso mostrare la metrica (una per tutte: 78.4 kg, 82.5 cm, 14.2%).
    public var fractionDigits: Int { 1 }
}

/// Qualunque grandezza corporea tracciabile: peso, composizione o circonferenza.
///
/// Serve a far trattare alla UI tutte le metriche in modo uniforme (grafico,
/// variazione, ultimo valore) senza un ramo per ciascuna.
public enum BodyMetricKind: Codable, Sendable, Hashable, CaseIterable, Identifiable, RawRepresentable {
    case weight
    case bodyFat
    case leanMass
    case muscleMass
    case water
    case measure(BodyMeasure)

    public var rawValue: String {
        switch self {
        case .weight: "weight"
        case .bodyFat: "bodyFat"
        case .leanMass: "leanMass"
        case .muscleMass: "muscleMass"
        case .water: "water"
        case .measure(let measure): "measure.\(measure.rawValue)"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "weight": self = .weight
        case "bodyFat": self = .bodyFat
        case "leanMass": self = .leanMass
        case "muscleMass": self = .muscleMass
        case "water": self = .water
        default:
            let prefix = "measure."
            guard rawValue.hasPrefix(prefix),
                  let measure = BodyMeasure(rawValue: String(rawValue.dropFirst(prefix.count))) else { return nil }
            self = .measure(measure)
        }
    }

    public var id: String { rawValue }

    /// Prima peso e composizione, poi le circonferenze nell'ordine canonico.
    public static var allCases: [BodyMetricKind] {
        [.weight, .bodyFat, .leanMass, .muscleMass, .water] + BodyMeasure.allCases.map(BodyMetricKind.measure)
    }

    /// Solo peso e composizione corporea.
    public static let compositionCases: [BodyMetricKind] = [.weight, .bodyFat, .leanMass, .muscleMass, .water]

    public var displayName: String {
        switch self {
        case .weight: "Peso"
        case .bodyFat: "Massa grassa"
        case .leanMass: "Massa magra"
        case .muscleMass: "Massa muscolare"
        case .water: "Acqua corporea"
        case .measure(let measure): measure.displayName
        }
    }

    /// Nome compatto per le card strette.
    public var shortName: String {
        switch self {
        case .measure(let measure): measure.shortName
        default: displayName
        }
    }

    public var unit: BodyMetricUnit {
        switch self {
        case .weight, .leanMass, .muscleMass: .kilograms
        case .bodyFat, .water: .percent
        case .measure: .centimeters
        }
    }

    /// Valore della metrica in una rilevazione, `nil` se non registrato.
    public func value(in entry: BodyEntry) -> Double? {
        switch self {
        case .weight: entry.weightKg
        case .bodyFat: entry.bodyFatPct
        case .leanMass: entry.leanMassKg
        case .muscleMass: entry.muscleMassKg
        case .water: entry.waterPct
        case .measure(let measure): entry.measurementsCm[measure]
        }
    }

    /// Formatta un valore con la sua unità, in italiano (virgola decimale).
    ///
    /// Per le metriche in kg rispetta l'unità scelta dall'utente; centimetri e
    /// percentuali restano invariati. La percentuale si scrive **attaccata** al
    /// numero (`"16,4%"`), il resto con lo spazio (`"82,5 kg"`, `"83 cm"`).
    public func format(_ value: Double, weightUnit: WeightUnit = .kg) -> String {
        switch unit {
        case .kilograms:
            return weightUnit.format(kilograms: value, fractionDigits: 1)
        case .centimeters, .percent:
            return ItalianNumberFormat.measurement(value, unit: unit.symbol, fractionDigits: unit.fractionDigits)
        }
    }
}

/// Una rilevazione corporea: peso, composizione e/o circonferenze.
///
/// Ogni campo è opzionale: si può registrare solo il peso, solo alcune misure, o tutto.
public struct BodyEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var date: Date
    /// Peso in kg.
    public var weightKg: Double?
    /// Massa grassa in percentuale (0…100), inserita a mano dalla bilancia.
    public var bodyFatPct: Double?
    /// Massa magra in kg.
    public var leanMassKg: Double?
    /// Massa muscolare in kg.
    public var muscleMassKg: Double?
    /// Acqua corporea in percentuale (0…100).
    public var waterPct: Double?
    /// Circonferenze in centimetri.
    public var measurementsCm: [BodyMeasure: Double]

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        weightKg: Double? = nil,
        bodyFatPct: Double? = nil,
        leanMassKg: Double? = nil,
        muscleMassKg: Double? = nil,
        waterPct: Double? = nil,
        measurementsCm: [BodyMeasure: Double] = [:]
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.leanMassKg = leanMassKg
        self.muscleMassKg = muscleMassKg
        self.waterPct = waterPct
        self.measurementsCm = measurementsCm
    }

    /// Circonferenza di una misura specifica.
    public subscript(measure: BodyMeasure) -> Double? {
        get { measurementsCm[measure] }
        set { measurementsCm[measure] = newValue }
    }

    /// Valore di una qualunque metrica corporea.
    public subscript(metric: BodyMetricKind) -> Double? {
        get { metric.value(in: self) }
        set { setValue(newValue, for: metric) }
    }

    /// Imposta (o azzera) il valore di una metrica.
    public mutating func setValue(_ value: Double?, for metric: BodyMetricKind) {
        switch metric {
        case .weight: weightKg = value
        case .bodyFat: bodyFatPct = value
        case .leanMass: leanMassKg = value
        case .muscleMass: muscleMassKg = value
        case .water: waterPct = value
        case .measure(let measure): measurementsCm[measure] = value
        }
    }

    /// `true` se non contiene alcun dato (da non salvare).
    public var isEmpty: Bool { recordedMetrics.isEmpty }

    /// Metriche effettivamente registrate, nell'ordine canonico.
    public var recordedMetrics: [BodyMetricKind] {
        BodyMetricKind.allCases.filter { $0.value(in: self) != nil }
    }

    /// Circonferenze registrate, nell'ordine canonico.
    public var recordedMeasures: [BodyMeasure] {
        BodyMeasure.allCases.filter { measurementsCm[$0] != nil }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, date, weightKg, bodyFatPct, leanMassKg, muscleMassKg, waterPct, measurementsCm
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        bodyFatPct = try c.decodeIfPresent(Double.self, forKey: .bodyFatPct)
        leanMassKg = try c.decodeIfPresent(Double.self, forKey: .leanMassKg)
        muscleMassKg = try c.decodeIfPresent(Double.self, forKey: .muscleMassKg)
        waterPct = try c.decodeIfPresent(Double.self, forKey: .waterPct)
        // Dizionario serializzato come oggetto `{"waist": 82}`: le chiavi ignote
        // vengono scartate invece di far fallire tutta la decodifica.
        let raw = try c.decodeIfPresent([String: Double].self, forKey: .measurementsCm) ?? [:]
        var result: [BodyMeasure: Double] = [:]
        for (key, value) in raw {
            guard let measure = BodyMeasure(rawValue: key) else { continue }
            result[measure] = value
        }
        measurementsCm = result
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(weightKg, forKey: .weightKg)
        try c.encodeIfPresent(bodyFatPct, forKey: .bodyFatPct)
        try c.encodeIfPresent(leanMassKg, forKey: .leanMassKg)
        try c.encodeIfPresent(muscleMassKg, forKey: .muscleMassKg)
        try c.encodeIfPresent(waterPct, forKey: .waterPct)
        let raw = Dictionary(uniqueKeysWithValues: measurementsCm.map { ($0.key.rawValue, $0.value) })
        try c.encode(raw, forKey: .measurementsCm)
    }
}
