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
    /// Gli stessi id come insieme: la riga chiede "sono selezionato?" a ogni `body`,
    /// e su una zona da ~290 righe una scansione lineare per riga si sente.
    @State private var selectedIDs: Set<String> = []
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
        // Stesso principio della shell: la barra "Aggiungi (n)" sta SOTTO l'elenco
        // in un `VStack`, non in un `safeAreaInset`. L'elenco finisce dove comincia
        // la barra, quindi l'ultima riga resta raggiungibile senza dipendere da
        // come la safe area si propaga dentro la sheet.
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            confirmBar
        }
        .pageBackground()
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

    @ViewBuilder
    private var content: some View {
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
    }

    // MARK: - Testate

    private var rootHeader: some View {
        SheetHeader(title: title, actionTitle: "Annulla") { dismiss() }
            .sheetHeaderMargins()
    }

    private func groupHeader(_ section: ExerciseSection) -> some View {
        SheetHeader(
            title: section.title,
            back: {
                openedSection = nil
                equipment = []
            },
            backTitle: "Zone",
            actionTitle: "Annulla"
        ) {
            dismiss()
        }
        .sheetHeaderMargins()
    }

    // MARK: - Riga

    @ViewBuilder
    private func row(_ exercise: Exercise) -> some View {
        let presentation = app.rowPresentation(for: exercise)
        if excludedIDs.contains(exercise.id) {
            ExerciseRowView(presentation: presentation, imageURL: exercise.imageURL) {
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
                    ExerciseRowView(presentation: presentation, imageURL: exercise.imageURL)
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

    private func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    private func isAdded(_ id: String) -> Bool {
        excludedIDs.contains(id) || (allowsMultipleSelection && isSelected(id))
    }

    private func toggle(_ id: String) {
        guard allowsMultipleSelection else {
            pick([app.store.exercise(id: id)].compactMap { $0 })
            return
        }
        if selectedIDs.remove(id) != nil {
            selection.removeAll { $0 == id }
        } else {
            selection.append(id)
            selectedIDs.insert(id)
        }
        Haptics.play(.selection)
    }

    /// "Aggiungi alla scheda" dal dettaglio: segna la riga e riporta all'elenco.
    private func add(id: String) {
        guard allowsMultipleSelection else {
            pick([app.store.exercise(id: id)].compactMap { $0 })
            return
        }
        guard selectedIDs.insert(id).inserted else { return }
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
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
            // Fondo pieno proprio, esteso sotto l'home indicator.
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
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
