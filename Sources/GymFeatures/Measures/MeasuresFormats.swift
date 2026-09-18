import Foundation
import GymCore

/// Finestra temporale dei grafici della tab Misure.
enum ChartRange: String, CaseIterable, Hashable, Identifiable, Sendable {
    case month1
    case month3
    case month6
    case year1

    var id: String { rawValue }

    /// Etichetta del segmento: "1M", "3M", "6M", "1A".
    var title: String {
        switch self {
        case .month1: "1M"
        case .month3: "3M"
        case .month6: "6M"
        case .year1: "1A"
        }
    }

    /// Descrizione del periodo per la riga di variazione ("negli ultimi 3 mesi").
    var periodText: String {
        switch self {
        case .month1: "nell'ultimo mese"
        case .month3: "negli ultimi 3 mesi"
        case .month6: "negli ultimi 6 mesi"
        case .year1: "nell'ultimo anno"
        }
    }

    private var months: Int {
        switch self {
        case .month1: 1
        case .month3: 3
        case .month6: 6
        case .year1: 12
        }
    }

    /// Inizio della finestra rispetto ad "adesso".
    func start(from now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: -months, to: now) ?? now
    }
}

extension String {

    /// Solo la prima lettera maiuscola ("lun 14 set" → "Lun 14 set"), a differenza
    /// di `capitalized` che maiuscolerebbe ogni parola.
    var firstUppercased: String {
        isEmpty ? self : prefix(1).uppercased() + dropFirst()
    }
}

/// Formattazione uniforme delle metriche corporee.
///
/// Qui non si normalizza più niente: ``ItalianNumberFormat`` e i formattatori di
/// GymCore (``BodyMetricKind/format(_:weightUnit:)``, ``Stats/BodyChange/deltaText(weightUnit:)``)
/// producono già la virgola decimale, il segno meno ASCII e la percentuale
/// attaccata al numero. Restano solo la conversione fra unità e la scelta del
/// simbolo, che sono decisioni di questa schermata.
enum BodyFormat {

    /// Solo il numero, senza simbolo ("77,2").
    static func number(_ value: Double, metric: BodyMetricKind, unit: WeightUnit) -> String {
        switch metric.unit {
        case .kilograms:
            return unit.format(kilograms: value, fractionDigits: 1, includeSymbol: false)
        case .centimeters, .percent:
            return ItalianNumberFormat.number(
                value,
                fractionDigits: metric.unit.fractionDigits,
                grouping: false
            )
        }
    }

    /// Simbolo dell'unità ("kg", "cm", "%").
    static func symbol(_ metric: BodyMetricKind, unit: WeightUnit) -> String {
        metric.unit == .kilograms ? unit.symbol : metric.unit.symbol
    }

    /// Numero e simbolo ("77,2 kg", "16,4%").
    static func value(_ value: Double, metric: BodyMetricKind, unit: WeightUnit) -> String {
        metric.format(value, weightUnit: unit)
    }

    /// Valore salvato (kg per peso e composizione) convertito nell'unità mostrata.
    static func displayValue(_ stored: Double, metric: BodyMetricKind, unit: WeightUnit) -> Double {
        metric.unit == .kilograms ? unit.value(fromKilograms: stored) : stored
    }

    /// Valore digitato dall'utente riportato all'unità di salvataggio (kg).
    static func storedValue(_ displayed: Double, metric: BodyMetricKind, unit: WeightUnit) -> Double {
        metric.unit == .kilograms ? unit.kilograms(from: displayed) : displayed
    }

    /// Variazione con segno ("+1,2 kg", "-2 cm", "-1,2%").
    static func delta(_ change: Stats.BodyChange, unit: WeightUnit) -> String {
        change.deltaText(weightUnit: unit)
    }
}
