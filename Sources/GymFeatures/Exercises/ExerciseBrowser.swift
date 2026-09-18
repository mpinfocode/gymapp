import SwiftUI
import GymCore
import GymUI

/// La libreria esercizi navigabile: campo di ricerca, una riga di chip "zona
/// colpita" con i conteggi, un solo bottone filtro e la lista.
///
/// È **lo stesso** componente nel tab Esercizi e nel picker: cambia solo la riga
/// (link di navigazione oppure riga selezionabile) e l'intestazione.
struct ExerciseBrowser<Header: View, Row: View>: View {

    @Environment(AppEnvironment.self) private var app

    @Binding var model: ExerciseSearchModel
    /// Mostra "Recenti" e "Tutti" quando non si sta cercando né filtrando.
    let showsRecents: Bool
    /// Apertura del form dell'esercizio personalizzato, con il nome già scritto.
    let onCreateCustom: (String) -> Void
    let header: () -> Header
    let row: (Exercise) -> Row

    init(
        model: Binding<ExerciseSearchModel>,
        showsRecents: Bool = true,
        onCreateCustom: @escaping (String) -> Void,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder row: @escaping (Exercise) -> Row
    ) {
        self._model = model
        self.showsRecents = showsRecents
        self.onCreateCustom = onCreateCustom
        self.header = header
        self.row = row
    }

    @State private var showsFilters = false

    var body: some View {
        let facets = app.store.exerciseFacets(for: model.filter)
        let results = app.store.searchExercises(model.filter)
        let recents = recentExercises()

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header()
                    .padding(.horizontal, Theme.Spacing.page)

                SearchField(placeholder: "Cerca: panca, stacco, curl…", text: $model.query)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.l)

                // Senza nemmeno un chip da mostrare (ricerca a vuoto) la riga
                // sparisce: resterebbe solo il bottone filtro sospeso nel nulla.
                if !facets.muscleGroups.isEmpty || !orphanGroups(facets).isEmpty {
                    chips(facets)
                        .padding(.top, Theme.Spacing.m)
                }

                if results.isEmpty {
                    noResults
                } else {
                    Text(ExerciseBrowseFormat.resultsText(results.count))
                        .captionStyle(color: Theme.textTertiary)
                        .padding(.horizontal, Theme.Spacing.page)
                        .padding(.top, Theme.Spacing.m)

                    list(results, recents: recents)
                        .padding(.top, Theme.Spacing.l)
                }
            }
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .sheet(isPresented: $showsFilters) {
            ExerciseFiltersSheet(model: $model)
        }
    }

    // MARK: - Chip della zona colpita

    private func chips(_ facets: ExerciseFacets) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(facets.muscleGroups) { facet in
                        FilterChip(
                            facet.label,
                            count: facet.count,
                            isSelected: model.muscleGroups.contains(facet.group)
                        ) {
                            model.toggle(facet.group)
                        }
                    }
                    // I chip selezionati che non hanno più risultati devono restare
                    // visibili, altrimenti il filtro attivo sparisce dalla vista.
                    ForEach(orphanGroups(facets), id: \.self) { group in
                        FilterChip(group.displayName, count: 0, isSelected: true) {
                            model.toggle(group)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.page)
            }

            filterButton
                .padding(.trailing, Theme.Spacing.page)
        }
    }

    private func orphanGroups(_ facets: ExerciseFacets) -> [MuscleGroup] {
        let shown = Set(facets.muscleGroups.map(\.group))
        return MuscleGroup.displayOrder.filter { model.muscleGroups.contains($0) && !shown.contains($0) }
    }

    private var filterButton: some View {
        let isActive = model.sheetFilterCount > 0
        return Button {
            showsFilters = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent.onFill : Theme.textPrimary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(isActive ? Theme.accent.fill : Theme.surface, in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Altri filtri"))
        .accessibilityValue(Text(isActive ? "\(model.sheetFilterCount) attivi" : "nessuno attivo"))
    }

    // MARK: - Lista

    @ViewBuilder
    private func list(_ results: [Exercise], recents: [Exercise]) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !recents.isEmpty {
                Text("Recenti")
                    .overlineStyle()
                ForEach(recents) { row($0) }

                Text("Tutti")
                    .overlineStyle()
                    .padding(.top, Theme.Spacing.s)
            }

            ForEach(results) { row($0) }
        }
        .padding(.horizontal, Theme.Spacing.page)
    }

    private func recentExercises() -> [Exercise] {
        guard showsRecents, model.showsBrowseSections else { return [] }
        return ExerciseBrowseFormat.recents(ids: app.store.settings.recentExerciseIDs) {
            app.store.exercise(id: $0)
        }
    }

    // MARK: - Nessun risultato

    @ViewBuilder
    private var noResults: some View {
        if model.hasQuery {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "Nessun risultato",
                message: "Nessun esercizio per \"\(model.trimmedQuery)\". Puoi crearlo tu.",
                actionTitle: "Crea esercizio personalizzato",
                action: { onCreateCustom(model.trimmedQuery) }
            )
            .padding(.top, Theme.Spacing.xxl)
        } else {
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease",
                title: "Nessun risultato",
                message: "Nessun esercizio con questi filtri.",
                actionTitle: "Azzera i filtri",
                action: { model.clearFilters() }
            )
            .padding(.top, Theme.Spacing.xxl)
        }
    }
}
