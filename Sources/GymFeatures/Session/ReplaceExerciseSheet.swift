import SwiftUI
import GymCore
import GymUI

/// Macchina occupata: sostituisce l'esercizio della riga mantenendo le serie già
/// registrate. Propone le alternative calcolate da GymCore (stesso muscolo
/// bersaglio, poi stessa zona) e lascia comunque la porta aperta alla ricerca.
@MainActor
struct ReplaceExerciseSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entryID: UUID

    @State private var isSearching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Sostituisci")
                        .sectionTitleStyle()
                    Text(currentName)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                if alternatives.isEmpty {
                    Text("Nessuna alternativa proposta.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    VStack(spacing: Theme.Spacing.l) {
                        ForEach(alternatives) { exercise in
                            Button {
                                replace(with: exercise.id)
                            } label: {
                                ExerciseRowView(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    isSearching = true
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(.subheadline, weight: .medium))
                        Text("Cerca altro")
                            .font(.bodyText)
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Theme.Size.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pageBackground()
        .immersiveDark()
        .presentationDetents([.large])
        .sheet(isPresented: $isSearching) {
            ExercisePickerSheet(
                title: "Sostituisci",
                allowsMultipleSelection: false,
                excludedIDs: Set([currentID].compactMap { $0 })
            ) { picked in
                isSearching = false
                guard let first = picked.first else { return }
                replace(with: first.id)
            }
        }
    }

    private func replace(with exerciseID: String) {
        app.store.replaceExerciseInActiveSession(entryID: entryID, with: exerciseID)
        Haptics.play(.light)
        dismiss()
    }

    private var currentID: String? {
        app.store.activeSession?.entries.first { $0.id == entryID }?.exerciseID
    }

    private var currentName: String {
        guard let currentID else { return "" }
        return app.store.exerciseDisplayName(id: currentID)
    }

    private var alternatives: [Exercise] {
        guard let currentID else { return [] }
        return app.store.alternatives(for: currentID, limit: 8)
    }
}

/// Nota libera su un esercizio della sessione.
@MainActor
struct EntryNoteSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    let entryID: UUID

    @State private var text = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Nota")
                .sectionTitleStyle()

            TextField("Come è andata", text: $text, axis: .vertical)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding(Theme.Spacing.l)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

            PrimaryButton("Salva", variant: .light) {
                app.store.setNote(text, forEntry: entryID)
                dismiss()
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageBackground()
        .immersiveDark()
        .presentationDetents([.medium])
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            text = app.store.activeSession?.entries.first { $0.id == entryID }?.note ?? ""
        }
    }
}
