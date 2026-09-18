import SwiftUI
import GymCore
import GymUI

/// Elenco degli esercizi di una sezione (una zona colpita, i preferiti, i propri):
/// titolo, una riga di chip per attrezzo con i conteggi, la lista.
///
/// Gli esercizi "canonici" vengono prima, le varianti ridondanti del dataset dopo
/// (SPEC §2, punto 4). Ricerca e facet girano fuori dal main thread e si rifanno solo
/// quando cambia davvero qualcosa.
struct ExerciseGroupList<Header: View, Row: View>: View {

    @Environment(AppEnvironment.self) private var app

    let section: ExerciseSection
    /// Attrezzi selezionati con i chip.
    @Binding var equipment: Set<String>
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Exercise) -> Row

    @State private var results: [Exercise] = []
    @State private var chips: [FacetCount] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header()
                    .padding(.horizontal, Theme.Spacing.page)

                if !chips.isEmpty {
                    equipmentChips
                        .padding(.top, Theme.Spacing.l)
                }

                if results.isEmpty {
                    EmptyStateView(
                        systemImage: "line.3.horizontal.decrease",
                        title: "Nessun esercizio",
                        message: "Nessun esercizio con questo attrezzo.",
                        actionTitle: equipment.isEmpty ? nil : "Azzera gli attrezzi",
                        action: equipment.isEmpty ? nil : { equipment.removeAll() }
                    )
                    .padding(.top, Theme.Spacing.xxl)
                } else {
                    Text(ExerciseBrowseFormat.resultsText(results.count))
                        .captionStyle(color: Theme.textTertiary)
                        .padding(.horizontal, Theme.Spacing.page)
                        .padding(.top, Theme.Spacing.l)

                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        ForEach(results) { row($0) }
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.l)
                }
            }
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .task(id: signature) { await load() }
    }

    // MARK: - Chip per attrezzo

    private var equipmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(chips) { facet in
                    FilterChip(
                        facet.label,
                        count: facet.count,
                        isSelected: equipment.contains(facet.value)
                    ) {
                        if equipment.contains(facet.value) {
                            equipment.remove(facet.value)
                        } else {
                            equipment.insert(facet.value)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
        }
    }

    // MARK: - Caricamento

    private var signature: String {
        let selected = equipment.sorted().joined(separator: ",")
        let library = app.store.searchableLibrary?.count ?? 0
        return "\(section.id)|\(selected)|\(library)|\(app.store.settings.favoriteExerciseIDs.count)"
    }

    private func load() async {
        if section.isCustomOnly {
            results = ExerciseListOrder.sorted(app.store.availableCustomExercises)
            chips = []
            return
        }
        guard let library = app.store.searchableLibrary else { return }

        let favorites = app.store.settings.favoriteExerciseIDs
        var filter = section.filter
        let baseFilter = filter
        filter.equipment = equipment

        let outcome = await Task.detached(priority: .userInitiated) {
            let found = library.search(filter, favorites: favorites)
            let facets = library.facets(for: baseFilter, favorites: favorites)
            return (ExerciseListOrder.sorted(found), facets.equipment)
        }.value

        guard !Task.isCancelled else { return }
        results = outcome.0
        chips = outcome.1
    }
}
