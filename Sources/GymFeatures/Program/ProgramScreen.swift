import SwiftUI
import GymCore
import GymUI

/// Tab **Scheda**: gestione della scheda attiva (card con il suo gradiente, settimana
/// e scadenza), i giorni come righe semplici, l'archivio in fondo (SPEC §0).
///
/// Qui si **modifica**: la consultazione da palestra sta nella Home. Una cosa sola per
/// schermata: si entra in un giorno; tutto il resto (nuovo giorno, dettagli, duplica,
/// archivia, elimina) sta nel menu "…".
public struct ProgramScreen: View {

    @Environment(AppEnvironment.self) private var app

    /// Sheet di creazione o modifica dei dettagli.
    @State private var form: ProgramFormSheet.Mode?
    @State private var confirmsDeletion = false

    private static let topAnchor = "program-top"

    public init() {}

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if let program = app.store.activeProgram {
                        active(program)
                    } else {
                        empty
                    }
                }
                .id(Self.topAnchor)
            }
            // Ritocco sull'icona del tab già selezionato: si torna in cima.
            .onChange(of: app.router.scrollToTopToken(for: .program)) { _, _ in
                withAnimation(Theme.Motion.quick) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
            }
        }
        .pageBackground()
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
            titleBar
            card(program)
            days(of: program)
            archiveRow
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xxl)
    }

    /// Testata minima: il titolo della sezione e l'ingranaggio delle Impostazioni,
    /// che la shell presenta da sé (``Router/presentSettings()``).
    private var titleBar: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text("Scheda")
                .greetingStyle()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Theme.Spacing.s)

            Button {
                app.router.presentSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Impostazioni"))
        }
    }

    private func card(_ program: Program) -> some View {
        ZStack(alignment: .topTrailing) {
            HeroCard(
                seed: program.accent,
                height: 220,
                chipText: expiryWarning(program),
                animated: true
            ) { palette in
                Text(program.name)
                    .font(.sectionTitle)
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
                Button("Aggiungi un giorno") { addDay(to: program) }
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
                Button {
                    addDay(to: program)
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "plus")
                            .font(.system(.footnote, weight: .semibold))
                        Text("Aggiungi il primo giorno")
                            .font(.system(.subheadline, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Aggiungi il primo giorno"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(program.days.enumerated()), id: \.element.id) { index, day in
                        if index > 0 {
                            Divider().overlay(Theme.separator)
                        }
                        dayRow(day, programID: program.id)
                    }
                }
            }
        }
    }

    /// Un giorno nuovo si crea dal menu "…" e si apre subito: è lì che si scrive.
    private func addDay(to program: Program) {
        let name = ProgramPresentation.defaultDayName(at: program.days.count)
        let day = app.store.addDay(name: name, toProgram: program.id)
        app.router.push(.programDay(programID: program.id, dayID: day.id))
    }

    /// Chip della card: compare **solo** quando c'è qualcosa da segnalare.
    private func expiryWarning(_ program: Program) -> String? {
        if program.isExpired(asOf: app.now, calendar: app.calendar) { return "scaduta" }
        if program.isExpiringSoon(asOf: app.now, calendar: app.calendar) { return "in scadenza" }
        return nil
    }

    private func dayRow(_ day: ProgramDay, programID: UUID) -> some View {
        Button {
            app.router.push(.programDay(programID: programID, dayID: day.id))
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.name)
                        .font(.bodyEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(ProgramPresentation.daySubtitle(day))
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
                app.router.push(.programArchive)
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
