import SwiftUI
import GymCore
import GymUI

/// Picker esercizi: lo apre l'editor del giorno ("Aggiungi esercizi").
///
/// Ha la **stessa struttura** del catalogo: ricerca, zone colpite, elenco della zona.
/// Il **tocco sulla riga apre il dettaglio** con la GIF, così si vede subito se è
/// l'esercizio giusto, e da lì "Aggiungi alla scheda" lo segna e riporta all'elenco.
/// Chi sa già cosa vuole usa il cerchio di selezione a destra della riga e la barra
/// "Aggiungi (n)" in basso.
///
/// Chi lo apre resta responsabile della chiusura: `onPick` viene chiamato con gli
/// esercizi scelti; se l'utente annulla, `onPick` non viene chiamato.
public struct ExercisePickerSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let title: String
    private let allowsMultipleSelection: Bool
    private let excludedIDs: Set<String>
    private let onPick: ([Exercise]) -> Void

    @State private var model = ExerciseSearchModel()
    /// Id scelti, nell'ordine di selezione (è l'ordine promesso a chi apre il picker).
    @State private var selection: [String] = []
    @State private var openedSection: ExerciseSection?
    @State private var equipment: Set<String> = []
    @State private var detail: PickerDetail?
    @State private var isCreatingCustom = false
    @State private var prefilledName = ""

    /// - Parameters:
    ///   - title: titolo della sheet ("Aggiungi esercizi").
    ///   - allowsMultipleSelection: selezione multipla con conferma, invece del tocco singolo.
    ///   - excludedIDs: esercizi già presenti nel giorno.
    ///   - onPick: esercizi scelti, nell'ordine di selezione.
    public init(
        title: String,
        allowsMultipleSelection: Bool,
        excludedIDs: Set<String>,
        onPick: @escaping ([Exercise]) -> Void
    ) {
        self.title = title
        self.allowsMultipleSelection = allowsMultipleSelection
        self.excludedIDs = excludedIDs
        self.onPick = onPick
    }

    /// Init con una zona già aperta: la usano gli screenshot.
    public init(
        title: String,
        allowsMultipleSelection: Bool,
        excludedIDs: Set<String>,
        section: ExerciseSection,
        onPick: @escaping ([Exercise]) -> Void
    ) {
        self.init(
            title: title,
            allowsMultipleSelection: allowsMultipleSelection,
            excludedIDs: excludedIDs,
            onPick: onPick
        )
        _openedSection = State(initialValue: section)
    }

    public var body: some View {
        Group {
            if let section = openedSection {
                ExerciseGroupList(
                    section: section,
                    equipment: $equipment,
                    header: { groupHeader(section) },
                    row: { row($0) }
                )
            } else {
                ExerciseLibraryRoot(
                    model: $model,
                    onOpen: { section in
                        equipment = []
                        openedSection = section
                    },
                    onCreateCustom: { name in
                        prefilledName = name
                        isCreatingCustom = true
                    },
                    header: { rootHeader },
                    row: { row($0) }
                )
            }
        }
        .pageBackground()
        .safeAreaInset(edge: .bottom) { confirmBar }
        .sheet(item: $detail) { target in
            ExerciseDetailScreen(
                exerciseID: target.id,
                purpose: .picking(isAdded: isAdded(target.id), add: { add(id: target.id) })
            )
        }
        .sheet(isPresented: $isCreatingCustom) {
            CustomExerciseFormSheet(prefilledName: prefilledName) { created in
                pick([created])
            }
        }
    }

    // MARK: - Testate

    private var rootHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Button("Annulla") { dismiss() }
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)

                Spacer(minLength: Theme.Spacing.s)

                createCustomButton
            }

            Text(title)
                .sectionTitleStyle()
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func groupHeader(_ section: ExerciseSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Button {
                    openedSection = nil
                    equipment = []
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(.footnote, weight: .semibold))
                        Text("Zone")
                    }
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: Theme.Size.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Torna alle zone"))

                Spacer(minLength: Theme.Spacing.s)

                createCustomButton
            }

            Text(section.title)
                .sectionTitleStyle()
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var createCustomButton: some View {
        Button {
            prefilledName = model.trimmedQuery
            isCreatingCustom = true
        } label: {
            Image(systemName: "plus")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Crea esercizio personalizzato"))
    }

    // MARK: - Riga

    @ViewBuilder
    private func row(_ exercise: Exercise) -> some View {
        if excludedIDs.contains(exercise.id) {
            ExerciseRowView(exercise: exercise) {
                Text("già presente")
                    .captionStyle(color: Theme.textTertiary)
            }
            .opacity(0.45)
            .accessibilityValue(Text("già presente"))
        } else {
            HStack(spacing: Theme.Spacing.m) {
                // Il tocco sulla riga apre il dettaglio: si sceglie guardando la GIF.
                Button {
                    detail = PickerDetail(id: exercise.id)
                } label: {
                    ExerciseRowView(exercise: exercise)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Apre il dettaglio"))

                if allowsMultipleSelection {
                    selectionCircle(exercise)
                }
            }
        }
    }

    private func selectionCircle(_ exercise: Exercise) -> some View {
        let selected = isSelected(exercise.id)
        return Button {
            toggle(exercise.id)
        } label: {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(.title3, weight: .regular))
                .foregroundStyle(selected ? Theme.accent.deep : Theme.textTertiary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Seleziona"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Selezione

    private func isSelected(_ id: String) -> Bool { selection.contains(id) }

    private func isAdded(_ id: String) -> Bool {
        excludedIDs.contains(id) || (allowsMultipleSelection && isSelected(id))
    }

    private func toggle(_ id: String) {
        guard allowsMultipleSelection else {
            pick([app.store.exercise(id: id)].compactMap { $0 })
            return
        }
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
        Haptics.play(.selection)
    }

    /// "Aggiungi alla scheda" dal dettaglio: segna la riga e riporta all'elenco.
    private func add(id: String) {
        guard allowsMultipleSelection else {
            pick([app.store.exercise(id: id)].compactMap { $0 })
            return
        }
        guard !isSelected(id) else { return }
        selection.append(id)
        Haptics.play(.success)
    }

    // MARK: - Conferma

    @ViewBuilder
    private var confirmBar: some View {
        if allowsMultipleSelection, !selection.isEmpty {
            PrimaryButton("Aggiungi (\(selection.count))") {
                pick(selection.compactMap { app.store.exercise(id: $0) })
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.m)
            .background(Theme.background)
        }
    }

    private func pick(_ exercises: [Exercise]) {
        guard !exercises.isEmpty else { return }
        for exercise in exercises {
            app.store.markRecent(exercise.id)
        }
        Haptics.play(.success)
        onPick(exercises)
    }
}

/// Esercizio di cui si sta guardando il dettaglio senza uscire dal picker.
private struct PickerDetail: Identifiable, Hashable {
    let id: String
}
