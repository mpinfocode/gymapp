// swift-tools-version:6.0
import PackageDescription

// Contratto di progetto: vedi docs/SPEC.md §3. Non modificare senza approvazione del PM.
let package = Package(
    name: "GymKit",
    defaultLocalization: "it",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GymCore", targets: ["GymCore"]),
        .library(name: "GymUI", targets: ["GymUI"]),
        .library(name: "GymFeatures", targets: ["GymFeatures"]),
    ],
    targets: [
        .target(name: "GymCore", resources: [.process("Resources")]),
        .target(name: "GymUI"),
        .target(name: "GymFeatures", dependencies: ["GymCore", "GymUI"], exclude: ["README.md"]),
        .executableTarget(name: "GymChecks", dependencies: ["GymCore"]),
        // Solo macOS: rende le schermate in PNG (docs/preview, fuori da git) per la revisione visiva senza Xcode.
        .executableTarget(name: "GymSnapshots", dependencies: ["GymCore", "GymUI", "GymFeatures"]),
    ]
)
