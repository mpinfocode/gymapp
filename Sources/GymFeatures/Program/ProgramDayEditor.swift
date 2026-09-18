import SwiftUI
import GymCore
import GymUI

/// Editor di un giorno della scheda: è qui che si ricopia il foglio dell'istruttore.
///
/// Titolo rinominabile, giorno della settimana (solo in modalità a giorni fissi),
/// elenco riordinabile con swipe per eliminare, e un solo bottone primario:
/// "Aggiungi esercizi". Ogni modifica si salva subito, non c'è nessun "Salva".
///
/// È `public` solo perché la scena di screenshot `scheda-giorno` la rende da sola:
/// dentro l'app ci si arriva toccando un giorno in ``ProgramScreen``.
public struct ProgramDayEditor: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let programID: UUID
    private let dayID: UUID

    @State private var name = ""
    @State private var loaded = false
    @State private var showsPicker = false
    @State private var editing: ItemSelection?
    @State private var pendingEdit: UUID?
    @State private var confirmsDeletion = false
    @FocusState private var nameFocused: Bool

    public init(programID: UUID, dayID: UUID) {
        self.programID = programID
        self.dayID = dayID
    }

    public var body: some View {
        ZStack {
            PageBackground()

            if let day {
                VStack(alignment: .leading, spacing: 0) {
                    header(day)
                    content(day)
                    addButton
                }
            }
        }
        .navigationBarTitleDisplayModeInline()
        .onAppear(perform: load)
        .keyboardDoneToolbar { nameFocused = false }
        .sheet(isPresented: $showsPicker, onDismiss: openPendingEdit) {
            ExercisePickerSheet(
                title: "Aggiungi esercizi",
                allowsMultipleSelection: true,
                excludedIDs: Set(day?.exerciseIDs ?? []),
                onPick: add
            )
        }
        .sheet(item: $editing) { selection in
            PlanItemEditorSheet(programID: programID, dayID: dayID, itemID: selection.id)
                .halfHeightSheet()
        }
        .alert("Eliminare il giorno?", isPresented: $confirmsDeletion) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) {
                app.store.removeDay(id: dayID, fromProgram: programID)
                dismiss()
            }
        } message: {
            Text("Gli allenamenti già registrati restano nello storico.")
        }
    }

    // MARK: - Intestazione

    private func header(_ day: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                TextField("Nome del giorno", text: $name)
                    .font(.greeting)
                    .foregroundStyle(Theme.textPrimary)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
                    .onChange(of: name) { _, newValue in rename(to: newValue) }
                    .accessibilityLabel(Text("Nome del giorno"))

                ProgramMenu(accessibilityTitle: "Azioni sul giorno") {
                    Button("Inizia questo allenamento") {
                        app.store.startSession(programID: programID, dayID: dayID)
                    }
                    Button("Duplica il giorno", action: duplicate)
                    Button("Elimina il giorno", role: .destructive) { confirmsDeletion = true }
                }
            }

            if !day.items.isEmpty {
                Text(ProgramPresentation.exerciseCount(day.items.count))
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
            }

            if program?.mode == .weekdays {
                weekdayPicker(day)
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.l)
    }

    private func weekdayPicker(_ day: ProgramDay) -> some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            ForEach(Weekday.allCases) { weekday in
                let isSelected = day.weekday == weekday
                Button {
                    app.store.editDay(id: dayID, inProgram: programID) {
                        $0.weekday = isSelected ? nil : weekday
                    }
                } label: {
                    Text(weekday.letter)
                        .font(.system(.subheadline, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.accent.onFill : Theme.textSecondary)
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                        .background(isSelected ? Theme.accent.fill : Theme.surface, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text(weekday.displayName))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: - Elenco

    @ViewBuilder
    private func content(_ day: ProgramDay) -> some View {
        if day.items.isEmpty {
            VStack(spacing: Theme.Spacing.s) {
                Text("Nessun esercizio")
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Text("Aggiungi gli esercizi del foglio dell'istruttore: serie, ripetizioni e carichi si regolano in due tocchi.")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, Theme.Spacing.xxxl)
        } else {
            let letters = ProgramPresentation.supersetLetters(in: day)
            List {
                ForEach(day.items) { item in
                    Button {
                        editing = ItemSelection(id: item.id)
                    } label: {
                        row(item, letter: item.supersetGroup.flatMap { letters[$0] })
                    }
                    .buttonStyle(PressableButtonStyle())
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.xs,
                        leading: Theme.Spacing.page,
                        bottom: Theme.Spacing.xs,
                        trailing: Theme.Spacing.page
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    app.store.moveItems(
                        inDay: dayID,
                        inProgram: programID,
                        fromOffsets: source,
                        toOffset: destination
                    )
                }
                .onDelete { offsets in
                    for index in offsets where day.items.indices.contains(index) {
                        app.store.removeItem(id: day.items[index].id, fromDay: dayID, inProgram: programID)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
        }
    }

    @ViewBuilder
    private func row(_ item: PlanItem, letter: String?) -> some View {
        let summary = ProgramPresentation.itemSummary(item, unit: app.unit)
        if let exercise = app.store.exercise(id: item.exerciseID) {
            ExerciseRowView(exercise: exercise, subtitle: summary) {
                supersetBadge(letter)
            }
        } else {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.store.exerciseDisplayName(id: item.exerciseID))
                        .font(.bodyEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                supersetBadge(letter)
            }
            .frame(minHeight: Theme.Size.minTapTarget)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func supersetBadge(_ letter: String?) -> some View {
        if let letter {
            Text(letter)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.accent.onFill)
                .frame(width: 24, height: 24)
                .background(Theme.accent.fill, in: Circle())
                .accessibilityLabel(Text("Superset \(letter)"))
        }
    }

    // MARK: - Aggiunta

    private var addButton: some View {
        PrimaryButton("Aggiungi esercizi", systemImage: "plus") {
            showsPicker = true
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
    }

    private func add(_ exercises: [Exercise]) {
        showsPicker = false
        guard !exercises.isEmpty else { return }
        let existing = day?.items.count ?? 0
        app.store.addItems(exerciseIDs: exercises.map(\.id), toDay: dayID, inProgram: programID)
        guard let items = day?.items, items.indices.contains(existing) else { return }
        pendingEdit = items[existing].id
    }

    /// L'editor del primo esercizio aggiunto si apre quando il picker è già chiuso:
    /// due sheet nello stesso istante non si presentano in modo affidabile.
    private func openPendingEdit() {
        guard let pendingEdit else { return }
        self.pendingEdit = nil
        editing = ItemSelection(id: pendingEdit)
    }

    // MARK: - Azioni del giorno

    private func duplicate() {
        app.store.editProgram(id: programID) { program in
            guard let index = program.days.firstIndex(where: { $0.id == dayID }) else { return }
            let original = program.days[index]
            let copy = ProgramDay(
                name: original.name + " (copia)",
                weekday: nil,
                items: original.items.map { item in
                    PlanItem(
                        exerciseID: item.exerciseID,
                        targetSets: item.targetSets,
                        measure: item.measure,
                        targetWeightKg: item.targetWeightKg,
                        warmupSets: item.warmupSets,
                        restSeconds: item.restSeconds,
                        supersetGroup: item.supersetGroup,
                        note: item.note
                    )
                },
                note: original.note
            )
            program.days.insert(copy, at: index + 1)
        }
    }

    private func rename(to newValue: String) {
        guard loaded else { return }
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != day?.name else { return }
        app.store.editDay(id: dayID, inProgram: programID) { $0.name = trimmed }
    }

    // MARK: - Stato

    private var program: Program? { app.store.program(id: programID) }

    private var day: ProgramDay? { program?.day(id: dayID) }

    private func load() {
        guard !loaded else { return }
        name = day?.name ?? ""
        loaded = true
    }
}

/// Voce di piano aperta nell'editor a mezza altezza.
struct ItemSelection: Identifiable, Hashable {
    let id: UUID
}

extension View {

    /// Sheet a mezza altezza, pensata per il pollice: su macOS (screenshot) la
    /// sheet resta quella standard.
    @ViewBuilder
    func halfHeightSheet() -> some View {
        #if os(iOS)
        self.presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }

    /// Titolo di navigazione compatto: `navigationBarTitleDisplayMode` esiste solo su iOS.
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
