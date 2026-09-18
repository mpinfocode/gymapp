import SwiftUI
import GymCore
import GymUI

// MARK: - Firma del calcolo

/// Firma della ripartizione: cambia **solo** quando cambia davvero il risultato.
///
/// È quello che permette di calcolare fuori dal `body` con `.task(id:)` invece che a
/// ogni ridisegno (GymFeatures/README, "Nel body non si calcola"): la scheda ha un
/// `updatedAt` che lo store aggiorna a ogni modifica, quindi id + data bastano.
struct MuscleDistributionSignature: Hashable {
    let programID: UUID
    let dayID: UUID?
    let updatedAt: Date?
    let libraryReady: Bool
}

extension AppEnvironment {

    /// Firma corrente per una scheda (ed eventualmente un suo giorno).
    func muscleDistributionSignature(programID: UUID, dayID: UUID?) -> MuscleDistributionSignature {
        MuscleDistributionSignature(
            programID: programID,
            dayID: dayID,
            updatedAt: store.program(id: programID)?.updatedAt,
            libraryReady: exercises != nil
        )
    }

    /// Calcola la ripartizione descritta da una firma. Da chiamare in `.task`, mai nel `body`.
    func muscleDistribution(for signature: MuscleDistributionSignature) -> Stats.MuscleDistribution {
        guard let program = store.program(id: signature.programID) else { return .empty }
        guard let dayID = signature.dayID else { return store.muscleDistribution(for: program) }
        guard let day = program.day(id: dayID) else { return .empty }
        return store.muscleDistribution(for: day)
    }
}

// MARK: - Sezione collegata allo store

/// ``MuscleDistributionSummary`` agganciata allo store: calcola una volta sola e
/// ricalcola solo quando la scheda cambia.
public struct MuscleDistributionSection: View {

    private let programID: UUID
    private let dayID: UUID?
    private let title: String?

    @Environment(AppEnvironment.self) private var app
    @State private var distribution: Stats.MuscleDistribution?

    /// - Parameters:
    ///   - programID: scheda da analizzare.
    ///   - dayID: se presente, la ripartizione riguarda solo quel giorno.
    ///   - title: intestazione della sezione; `nil` per non mostrarne.
    public init(programID: UUID, dayID: UUID? = nil, title: String? = "Muscoli colpiti") {
        self.programID = programID
        self.dayID = dayID
        self.title = title
    }

    public var body: some View {
        let signature = app.muscleDistributionSignature(programID: programID, dayID: dayID)
        return VStack(alignment: .leading, spacing: 0) {
            if let distribution {
                MuscleDistributionSummary(
                    distribution: distribution,
                    title: title,
                    showsMissingGroups: dayID == nil
                )
            }
        }
        .task(id: signature) {
            distribution = app.muscleDistribution(for: signature)
        }
    }
}
