import SwiftUI
import GymCore
import GymUI

/// Elenco degli esercizi di una sezione (una zona colpita, i preferiti, i propri):
/// titolo, una riga di chip per attrezzo con i conteggi, la lista.
///
/// Gli esercizi "canonici" vengono prima, le varianti ridondanti del dataset dopo
/// (SPEC §2, punto 4). Ricerca e facet girano fuori dal main thread e si rifanno solo
/// quando cambia davvero qualcosa.
///
/// ## Perché una `List` e non una `LazyVStack`
/// Una zona arriva a ~290 righe, ognuna con una thumbnail remota. Una `LazyVStack`
/// dentro una `ScrollView` crea le righe pigramente ma le tiene tutte vive una volta
/// create: scorrendo avanti e indietro la gerarchia cresce e non torna più indietro.
/// La `List` in stile `plain` ricicla le celle come ha sempre fatto UIKit: il numero
/// di righe montate resta quello che si vede, le thumbnail fuori schermo rilasciano
/// la loro bitmap e la memoria è costante. In cambio serve mettere testata e chip
/// dentro la lista come righe: costo basso, sfondo trasparente e separatori nascosti
/// li rendono indistinguibili da prima.
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
        List {
            Group {
                header()
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.s)

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
                        .padding(.bottom, Theme.Spacing.s)
                }
            }
            .plainListRow()

            ForEach(results) { exercise in
                row(exercise)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.vertical, Theme.Spacing.s)
                    .plainListRow()
            }

            // Ultima riga sempre raggiungibile: lo spazio della tab bar lo riserva
            // già la shell, qui basta il respiro di fine pagina.
            Color.clear
                .frame(height: Theme.Spacing.l)
                .plainListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
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

    /// Cambia solo quando cambia davvero cosa c'è da mostrare.
    ///
    /// Il conteggio arriva da ``AppStore/exerciseIndex``, che non copia niente, e i
    /// preferiti si leggono dalla proprietà granulare: aprire un esercizio (che
    /// scrive i recenti) non rifà la ricerca.
    private var signature: String {
        let selected = equipment.sorted().joined(separator: ",")
        let library = app.store.exerciseIndex?.count ?? 0
        return "\(section.id)|\(selected)|\(library)|\(app.store.favoriteExerciseIDs.count)"
    }

    private func load() async {
        if section.isCustomOnly {
            results = ExerciseListOrder.sorted(app.store.availableCustomExercises)
            chips = []
            return
        }
        guard let snapshot = app.store.exerciseSearchSnapshot() else { return }

        var filter = section.filter
        let baseFilter = filter
        filter.equipment = equipment
        let searchFilter = filter

        let outcome = await Task.detached(priority: .userInitiated) {
            let found = snapshot.search(searchFilter)
            let facets = snapshot.facets(for: baseFilter)
            return (ExerciseListOrder.sorted(found), facets.equipment)
        }.value

        guard !Task.isCancelled else { return }
        results = outcome.0
        chips = outcome.1
    }
}

extension View {

    /// Riga di `List` senza decorazioni: niente sfondo, niente separatore, niente
    /// margini di sistema. Le liste dell'app disegnano tutto da sé.
    func plainListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
