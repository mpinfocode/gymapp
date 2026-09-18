import SwiftUI
import GymCore

/// Destinazioni interne a Progressi.
///
/// Restano locali alla feature (SPEC/README: rotte condivise solo se servono da
/// più tab). Le uniche rotte condivise usate qui sono ``AppRoute/session(id:)`` e
/// ``AppRoute/exercise(id:)``.
enum ProgressDestination: Hashable, Identifiable {
    /// Dettaglio di una metrica di allenamento (allenamenti, volume, costanza).
    case training(TrainingMetric)
    /// Dettaglio di una metrica corporea.
    case body(BodyMetricKind)
    /// Pagina "Misure".
    case measures
    /// Elenco dei record.
    case records
    /// Storico degli allenamenti.
    case history

    var id: String {
        switch self {
        case .training(let metric): "training.\(metric.rawValue)"
        case .body(let metric): "body.\(metric.rawValue)"
        case .measures: "measures"
        case .records: "records"
        case .history: "history"
        }
    }
}

/// Risolutore delle destinazioni: un solo punto, così ogni schermata resta piccola.
struct ProgressDestinationView: View {

    let destination: ProgressDestination

    var body: some View {
        switch destination {
        case .training(let metric): TrainingMetricDetailScreen(metric: metric)
        case .body(let metric): BodyMetricDetailScreen(metric: metric)
        case .measures: BodyMeasuresScreen()
        case .records: RecordsScreen()
        case .history: WorkoutHistoryScreen()
        }
    }
}
