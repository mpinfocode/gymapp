import SwiftUI
import GymCore
import GymUI

/// Radice della libreria: campo di ricerca e, sotto, le **zone colpite** con i loro
/// conteggi. Niente lista da 1.324 righe all'apertura.
///
/// È lo stesso componente nel tab Esercizi e nel picker della scheda: cambiano solo
/// l'intestazione, la riga (link oppure riga selezionabile) e cosa succede toccando
/// una zona.
///
/// Appena si scrive, le zone lasciano il posto ai risultati su tutto il catalogo.
/// La ricerca è **ritardata di 200 ms e cancellabile**, e gira fuori dal main thread
/// (``ExerciseRepository`` è `Sendable`): digitare non deve mai far scattare 1.324
/// confronti a ogni carattere.
struct ExerciseLibraryRoot<Header: View, Row: View>: View {

    @Environment(AppEnvironment.self) private var app

    @Binding var model: ExerciseSearchModel
    /// Tab di cui osservare il token "torna in cima"; `nil` dentro il picker, che
    /// non è la radice di nessun tab.
    var scrollTopTab: AppTab?
    /// Tocco su una zona o su una scorciatoia.
    let onOpen: (ExerciseSection) -> Void
    /// Apertura del form dell'esercizio personalizzato, con il nome già scritto.
    let onCreateCustom: (String) -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Exercise) -> Row

    /// Oltre questa soglia la ricerca invita a restringere invece di srotolare tutto.
    static var searchLimit: Int { 50 }

    @State private var results: [Exercise] = []
    @State private var hasMoreResults = false
    @State private var isSearching = false
    @State private var counts: [String: Int] = [:]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // La testata arriva già con i propri margini: è ``PageHeader``
                    // nel tab Esercizi e ``SheetHeader`` nel picker.
                    header()

                    SearchField(placeholder: "Cerca: panca, stacco, curl…", text: $model.query)
                        .padding(.horizontal, Theme.Spacing.page)

                    if model.hasQuery {
                        searchResults
                    } else {
                        sections
                    }
                }
                // In fondo solo un piccolo respiro: lo spazio del menu non è più
                // affar suo, lo occupa la fascia della shell.
                .padding(.bottom, Theme.Spacing.l)
                .id(ExerciseLibraryTopAnchor.id)
            }
            .keyboardDismissable()
            // Ritocco sull'icona del tab già selezionato: si torna in cima.
            .onChange(of: app.router.scrollToTopToken(for: scrollTopTab ?? .home)) { _, _ in
                guard scrollTopTab != nil else { return }
                withAnimation(Theme.Motion.quick) { proxy.scrollTo(ExerciseLibraryTopAnchor.id, anchor: .top) }
            }
        }
        .task(id: model.trimmedQuery) { await search() }
        .task(id: librarySignature) { await loadCounts() }
    }

    // MARK: - Zone colpite

    @ViewBuilder
    private var sections: some View {
        let recents = recentExercises()

        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Recenti").overlineStyle()
                    ForEach(recents) { row($0) }
                }
            }

            let shortcuts = availableShortcuts
            if !shortcuts.isEmpty {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(shortcuts) { section in
                        sectionRow(section)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Zone colpite").overlineStyle()
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(availableGroups) { section in
                        sectionRow(section)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.xl)
    }

    private func sectionRow(_ section: ExerciseSection) -> some View {
        PillRow(
            title: section.title,
            detail: count(of: section).map(Formatters.integer),
            systemImage: section.systemImage,
            action: { onOpen(section) }
        )
        .accessibilityHint(Text("Apre l'elenco"))
    }

    private var availableShortcuts: [ExerciseSection] {
        [.favorites, .custom].filter { (count(of: $0) ?? 0) > 0 }
    }

    private var availableGroups: [ExerciseSection] {
        MuscleGroup.displayOrder
            .map(ExerciseSection.group)
            .filter { (count(of: $0) ?? 0) > 0 }
    }

    private func count(of section: ExerciseSection) -> Int? { counts[section.id] }

    // MARK: - Risultati della ricerca

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty {
            if isSearching {
                Color.clear.frame(height: 1)
            } else {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Nessun risultato",
                    message: "Nessun esercizio per \"\(model.trimmedQuery)\". Puoi crearlo tu.",
                    actionTitle: "Crea esercizio personalizzato",
                    action: { onCreateCustom(model.trimmedQuery) }
                )
                .padding(.top, Theme.Spacing.xxl)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(hasMoreResults
                     ? "Primi \(Self.searchLimit) risultati · affina la ricerca"
                     : ExerciseBrowseFormat.resultsText(results.count))
                    .captionStyle(color: Theme.textTertiary)

                ForEach(results) { row($0) }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
        }
    }

    private func recentExercises() -> [Exercise] {
        ExerciseBrowseFormat.recents(ids: app.store.recentExerciseIDs) {
            app.store.exercise(id: $0)
        }
    }

    // MARK: - Lavoro fuori dal main thread

    /// Cambia solo quando cambia davvero la libreria consultabile: evita di
    /// ricontare 1.324 esercizi a ogni ridisegno.
    ///
    /// Il conteggio viene da ``AppStore/exerciseIndex`` e non più da
    /// `searchableLibrary`, che per rispondere fonde due indici in uno.
    private var librarySignature: String {
        let library = app.store.exerciseIndex?.count ?? 0
        let favorites = app.store.favoriteExerciseIDs.count
        return "\(library)-\(favorites)-\(app.store.availableCustomExercises.count)"
    }

    private func loadCounts() async {
        guard let snapshot = app.store.exerciseSearchSnapshot() else { return }
        let customCount = app.store.availableCustomExercises.count

        let computed = await Task.detached(priority: .userInitiated) {
            let facets = snapshot.facets(for: .empty)
            var values: [String: Int] = [:]
            for facet in facets.muscleGroups {
                values[ExerciseSection.group(facet.group).id] = facet.count
            }
            values[ExerciseSection.favorites.id] = facets.favorites
            values[ExerciseSection.custom.id] = customCount
            return values
        }.value

        guard !Task.isCancelled else { return }
        counts = computed
    }

    private func search() async {
        guard model.hasQuery else {
            results = []
            hasMoreResults = false
            isSearching = false
            return
        }
        isSearching = true
        // Debounce: `task(id:)` cancella il tentativo precedente a ogni carattere.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, let snapshot = app.store.exerciseSearchSnapshot() else { return }

        let filter = model.filter
        let limit = Self.searchLimit
        let found = await Task.detached(priority: .userInitiated) {
            snapshot.search(filter, limit: limit + 1)
        }.value

        guard !Task.isCancelled else { return }
        hasMoreResults = found.count > limit
        results = Array(found.prefix(limit))
        isSearching = false
    }
}

/// Ancora "torna in cima" della radice della libreria (un tipo generico non può
/// avere proprietà statiche memorizzate).
private enum ExerciseLibraryTopAnchor {
    static let id = "library-top"
}
