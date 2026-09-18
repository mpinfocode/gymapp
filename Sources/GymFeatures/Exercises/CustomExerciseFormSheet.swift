import SwiftUI
import GymCore
import GymUI

/// Form dell'esercizio personalizzato: nome, zona colpita, attrezzo, note.
///
/// Nient'altro: gli esercizi che mancano al dataset (face pull, bulgarian split
/// squat…) servono per poterli mettere in scheda e nelle statistiche, non per
/// ricostruire una scheda tecnica.
public struct CustomExerciseFormSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// Esercizio da modificare; `nil` per crearne uno nuovo.
    private let editing: Exercise?
    private let onSaved: ((Exercise) -> Void)?

    @State private var name: String
    @State private var group: MuscleGroup
    @State private var equipment: String
    @State private var notes: String

    /// - Parameters:
    ///   - prefilledName: nome già scritto (arriva dal testo cercato).
    ///   - editing: esercizio personalizzato da modificare.
    ///   - onSaved: richiamata con l'esercizio salvato, per chi deve poi usarlo.
    public init(
        prefilledName: String = "",
        editing: Exercise? = nil,
        onSaved: ((Exercise) -> Void)? = nil
    ) {
        self.editing = editing
        self.onSaved = onSaved
        _name = State(initialValue: editing?.displayName ?? prefilledName)
        _group = State(initialValue: editing.map { MuscleGroup.forExercise($0) } ?? .chest)
        _equipment = State(initialValue: editing?.equipment ?? "")
        _notes = State(initialValue: editing?.notes ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                field("Nome") {
                    TextField("Face pull", text: $name)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .textFieldStyle(.plain)
                        .frame(minHeight: Theme.Size.minTapTarget)
                        .padding(.horizontal, Theme.Spacing.l)
                        .background(Theme.surface, in: Capsule(style: .continuous))
                }

                field("Zona colpita") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
                        ForEach(MuscleGroup.displayOrder) { candidate in
                            FilterChip(candidate.displayName, isSelected: candidate == group) {
                                group = candidate
                            }
                        }
                    }
                }

                field("Attrezzo") {
                    Menu {
                        Button("Nessuno") { equipment = "" }
                        ForEach(equipmentChoices, id: \.value) { choice in
                            Button(choice.label) { equipment = choice.value }
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            Text(equipment.isEmpty ? "Nessuno" : Localization.equipment(equipment))
                                .font(.bodyText)
                                .foregroundStyle(equipment.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                            Spacer(minLength: Theme.Spacing.s)
                            Image(systemName: "chevron.down")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(minHeight: Theme.Size.minTapTarget)
                        .padding(.horizontal, Theme.Spacing.l)
                        .background(Theme.surface, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Attrezzo"))
                }

                field("Note") {
                    TextField("Presa stretta, panca a 30 gradi", text: $notes, axis: .vertical)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)
                        .padding(Theme.Spacing.l)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }

                PrimaryButton("Salva", isEnabled: !trimmedName.isEmpty, action: save)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.l)
        }
        .keyboardDismissable()
        .pageBackground()
        .keyboardDismissOnTap()
        .keyboardDoneToolbar()
    }

    // MARK: - Pezzi

    private var header: some View {
        SheetHeader(
            title: editing == nil ? "Nuovo esercizio" : "Modifica esercizio",
            actionTitle: "Annulla"
        ) {
            dismiss()
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .overlineStyle()
            content()
        }
    }

    private var equipmentChoices: [(value: String, label: String)] {
        Localization.equipmentTranslations
            .map { (value: $0.key, label: $0.value) }
            .sorted { $0.label < $1.label }
    }

    // MARK: - Salvataggio

    private func save() {
        let terms = CustomExerciseTerms.dataset(for: group)
        let saved: Exercise?
        if let editing {
            saved = app.store.editCustomExercise(
                id: editing.id,
                name: trimmedName,
                category: terms.category,
                equipment: equipment,
                target: terms.target,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            saved = app.store.createCustomExercise(
                name: trimmedName,
                category: terms.category,
                equipment: equipment,
                target: terms.target,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if let saved {
            Haptics.play(.light)
            onSaved?(saved)
        }
        dismiss()
    }
}

/// Traduzione della zona colpita nei termini inglesi del dataset, così un esercizio
/// personalizzato ricade nei filtri e nelle statistiche come tutti gli altri.
enum CustomExerciseTerms {

    static func dataset(for group: MuscleGroup) -> (category: String, target: String) {
        switch group {
        case .chest: ("chest", "pectorals")
        case .back: ("back", "lats")
        case .shoulders: ("shoulders", "delts")
        case .biceps: ("upper arms", "biceps")
        case .triceps: ("upper arms", "triceps")
        case .forearms: ("lower arms", "forearms")
        case .abs: ("waist", "abs")
        case .quads: ("upper legs", "quads")
        case .hamstrings: ("upper legs", "hamstrings")
        case .glutes: ("upper legs", "glutes")
        case .calves: ("lower legs", "calves")
        case .cardio: ("cardio", "cardiovascular system")
        case .other: ("", "")
        }
    }
}
