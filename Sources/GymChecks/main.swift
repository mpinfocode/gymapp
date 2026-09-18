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
runStatsChecks(harness)
await runPersistenceChecks(harness)
await runStoreChecks(harness, repository: repository)
await runBackupChecks(harness, repository: repository)

harness.report()
