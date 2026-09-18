import Foundation

extension Array {
    /// Riordino per drag & drop con la stessa semantica di `onMove` di SwiftUI.
    ///
    /// Reimplementato qui perché GymCore non può importare SwiftUI (SPEC §3).
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { self[$0] }
        for index in valid.sorted(by: >) { remove(at: index) }
        let shift = valid.filter { $0 < destination }.count
        let insertionIndex = Swift.min(Swift.max(0, destination - shift), count)
        insert(contentsOf: moving, at: insertionIndex)
    }
}
