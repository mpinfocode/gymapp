import SwiftUI
import GymCore
import GymUI

/// Archivio delle schede: cicli passati, consultabili, riattivabili, duplicabili.
///
/// Lo storico degli allenamenti non si tocca mai: eliminare una scheda qui non
/// cancella nessuna sessione.
///
/// È `public` solo perché la scena di screenshot `scheda-archivio` la rende da
/// sola: dentro l'app ci si arriva dalla riga "Archivio" della scheda.
public struct ProgramArchiveScreen: View {

    @Environment(AppEnvironment.self) private var app

    @State private var pendingDeletion: UUID?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Archivio")
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                if app.store.archivedPrograms.isEmpty {
                    Text("Nessuna scheda in archivio.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(app.store.archivedPrograms) { program in
                        row(program)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .pageBackground()
        .alert("Eliminare la scheda?", isPresented: deletionBinding) {
            Button("Annulla", role: .cancel) { pendingDeletion = nil }
            Button("Elimina", role: .destructive) {
                if let id = pendingDeletion { app.store.deleteProgram(id: id) }
                pendingDeletion = nil
            }
        } message: {
            Text("Gli allenamenti già registrati restano nello storico.")
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    // MARK: - Riga

    private func row(_ program: Program) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(program.name)
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle(of: program))
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            ProgramMenu(accessibilityTitle: "Azioni su \(program.name)", background: Theme.surfaceElevated) {
                Button("Riattiva") { app.store.activate(programID: program.id) }
                Button("Duplica come nuova scheda") {
                    app.store.duplicateProgram(id: program.id, activate: false)
                }
                Button("Elimina", role: .destructive) { pendingDeletion = program.id }
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }

    private func subtitle(of program: Program) -> String {
        var parts = [
            ProgramPresentation.dayCount(program.days.count),
            ProgramPresentation.exerciseCount(program.exerciseIDs.count),
        ]
        parts.append("dal " + ProgramPresentation.longDay(program.startDate, calendar: app.calendar))
        return parts.joined(separator: " · ")
    }
}
