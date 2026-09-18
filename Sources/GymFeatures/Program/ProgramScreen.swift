import SwiftUI
import GymCore
import GymUI

/// Tab **Scheda**: la scheda attiva in alto (card con il suo gradiente, settimana
/// e scadenza), i giorni come righe semplici, l'archivio in fondo (SPEC §5.3).
///
/// Una cosa sola per schermata: qui si guarda la scheda e si entra in un giorno.
/// Tutto il resto (modifica dettagli, duplica, archivia, elimina) sta nel menu "…".
public struct ProgramScreen: View {

    @Environment(AppEnvironment.self) private var app

    /// Navigazione locale: giorno aperto oppure archivio.
    @State private var route: ProgramRoute?
    /// Sheet di creazione o modifica dei dettagli.
    @State private var form: ProgramFormSheet.Mode?
    @State private var confirmsDeletion = false

    public init() {}

    public var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                if let program = app.store.activeProgram {
                    active(program)
                } else {
                    empty
                }
            }
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .day(let id):
                if let program = app.store.activeProgram {
                    ProgramDayEditor(programID: program.id, dayID: id)
                }
            case .archive:
                ProgramArchiveScreen()
            }
        }
        .sheet(item: $form) { mode in
            ProgramFormSheet(mode: mode)
        }
        .alert("Eliminare la scheda?", isPresented: $confirmsDeletion) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) {
                guard let program = app.store.activeProgram else { return }
                app.store.deleteProgram(id: program.id)
            }
        } message: {
            Text("Gli allenamenti già registrati restano nello storico.")
        }
    }

    // MARK: - Scheda attiva

    private func active(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            card(program)
            days(of: program)
            archiveRow
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xxl)
    }

    private func card(_ program: Program) -> some View {
        ZStack(alignment: .topTrailing) {
            HeroCard(
                seed: program.accent,
                height: 260,
                chipText: program.mode.displayName,
                animated: true
            ) { palette in
                Text(program.name)
                    .font(.greeting)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ProgramPresentation.programStatus(program, now: app.now, calendar: app.calendar))
                    .font(.captionText)
                    .foregroundStyle(palette.foreground.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgramMenu(accessibilityTitle: "Azioni sulla scheda", background: Theme.surfaceElevated) {
                Button("Modifica i dettagli") { form = .edit(program.id) }
                Button("Duplica come nuova scheda") {
                    app.store.duplicateProgram(id: program.id, activate: false)
                }
                Button("Archivia") { app.store.archiveProgram(id: program.id) }
                Button("Elimina", role: .destructive) { confirmsDeletion = true }
            }
            .padding(Theme.Spacing.l)
        }
    }

    // MARK: - Giorni

    private func days(of program: Program) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Giorni").overlineStyle()

            if program.days.isEmpty {
                Text("Nessun giorno. Aggiungi il primo per cominciare a ricopiare la scheda.")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Theme.Spacing.s)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(program.days.enumerated()), id: \.element.id) { index, day in
                        if index > 0 {
                            Divider().overlay(Theme.separator)
                        }
                        dayRow(day, mode: program.mode)
                    }
                }
            }

            Button {
                let name = ProgramPresentation.defaultDayName(at: program.days.count)
                let day = app.store.addDay(name: name, toProgram: program.id)
                route = .day(day.id)
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "plus")
                        .font(.system(.footnote, weight: .semibold))
                    Text("Aggiungi un giorno")
                        .font(.system(.subheadline, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Aggiungi un giorno"))
        }
    }

    private func dayRow(_ day: ProgramDay, mode: ProgramMode) -> some View {
        Button {
            route = .day(day.id)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.name)
                        .font(.bodyEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(ProgramPresentation.daySubtitle(day, mode: mode))
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Theme.Spacing.s)

                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Apre il giorno"))
    }

    // MARK: - Archivio

    @ViewBuilder
    private var archiveRow: some View {
        let archived = app.store.archivedPrograms
        if !archived.isEmpty {
            Button {
                route = .archive
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Archivio")
                        .font(.system(.subheadline, weight: .medium))
                    Spacer(minLength: Theme.Spacing.s)
                    Text("\(archived.count)")
                        .font(.system(.subheadline, weight: .regular))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Archivio, \(archived.count) schede"))
        }
    }

    // MARK: - Nessuna scheda

    private var empty: some View {
        VStack(spacing: Theme.Spacing.m) {
            EmptyStateView(
                systemImage: "list.bullet.rectangle",
                title: "Nessuna scheda",
                message: "Ricopia qui la scheda dell'istruttore: giorni, esercizi, serie e carichi.",
                actionTitle: "Crea la tua scheda",
                action: { form = .create }
            )

            Button {
                app.store.loadSampleProgram()
            } label: {
                Text("Carica una scheda d'esempio")
                    .font(.system(.subheadline, weight: .medium))
                    .underline()
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: Theme.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Carica una scheda d'esempio"))
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.xxxl * 2)
    }
}

/// Destinazioni interne alla sezione Scheda: restano locali, senza toccare `AppRoute`.
enum ProgramRoute: Hashable {
    case day(UUID)
    case archive
}

/// Menu "…" della scheda e del giorno: stesso aspetto ovunque.
struct ProgramMenu<Content: View>: View {

    var accessibilityTitle: String = "Altre azioni"
    /// Riempimento del cerchio: bianco sopra il gradiente della card, grigio sul bianco di pagina.
    var background: Color = Theme.surface
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(accessibilityTitle))
    }
}
