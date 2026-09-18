import Foundation
import GymCore

// Eseguibile di verifica per GymCore: sul toolchain locale non esistono XCTest
// né Swift Testing (SPEC §1.2), quindi i test sono un binario che esce con
// codice 1 se qualcosa non torna.
//
//   swift run GymChecks

let harness = Harness()

print("GymChecks · verifica di GymCore")

runModelChecks(harness)
runProgramChecks(harness)
let repository = await runDatasetChecks(harness)
await runCorrectionChecks(harness, repository: repository)
await runSecondaryMuscleChecks(harness, repository: repository)
runExerciseNameChecks(harness, repository: repository)
runItalianSearchChecks(harness, repository: repository)
runStatsChecks(harness)
runMuscleDistributionChecks(harness, repository: repository)
runFormattingChecks(harness)
runProgressionChecks(harness)
runRecordHistoryChecks(harness)
await runPersistenceChecks(harness)
await runStoreChecks(harness, repository: repository)
await runCustomExerciseChecks(harness, repository: repository)
await runBackupChecks(harness, repository: repository)
runGeneratorPoolChecks(harness, repository: repository)
runGeneratorChecks(harness, repository: repository)
await runPerformanceChecks(harness, repository: repository)

await runPerformanceBenchmark(repository: repository)

harness.report()
