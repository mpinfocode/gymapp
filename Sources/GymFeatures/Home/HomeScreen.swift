import SwiftUI
import GymCore
import GymUI

/// Home: la scheda attiva in sola **consultazione**, la schermata che si tiene in
/// mano in palestra (SPEC §0).
///
/// In alto il nome della scheda e la settimana, poi i giorni come chip (l'ultimo
/// scelto si ricorda), sotto gli esercizi del giorno. Toccandone uno si apre il suo
/// dettaglio con in testa il blocco "La tua scheda", dove il carico si ritocca al
/// volo. Nessun controllo di modifica: quelli stanno nel tab Scheda.
///
/// Niente gradiente animato qui: è la schermata più usata e la priorità è la
/// fluidità (SPEC §0, "Priorità n.1").
public struct HomeScreen: View {

    @Environment(AppEnvironment.self) private var app

    /// Ultimo giorno consultato, ricordato fra un avvio e l'altro.
    @AppStorage("home.lastDayID") private var storedDayID = ""

    @State private var selectedDayID: UUID?
    @State private var openedItem: PlanItemContext?

    public init() {}

    /// Init con un giorno già scelto: la usano gli screenshot per fotografare un
    /// giorno preciso senza dipendere da quello ricordato.
    public init(dayID: UUID) {
        _selectedDayID = State(initialValue: dayID)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let program = app.store.activeProgram {
                    content(program)
                        .id(Self.topAnchor)
                } else {
                    empty.id(Self.topAnchor)
                }
            }
            // Ritocco sull'icona del tab già selezionato: si torna in cima.
            .onChange(of: app.router.scrollToTopToken(for: .home)) { _, _ in
                withAnimation(Theme.Motion.quick) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
            }
        }
        .pageBackground()
        .navigationDestination(item: $openedItem) { context in
            ExerciseDetailScreen(exerciseID: exerciseID(of: context) ?? "", purpose: .plan(context))
        }
        .onAppear(perform: restoreSelection)
    }

    private static let topAnchor = "home-top"

    // MARK: - Scheda attiva

    private func content(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            header(program)

            if program.days.count > 1 {
                dayChips(program)
            }

            if let day = selectedDay(in: program) {
                items(of: day, in: program)
            } else {
                hint("Questa scheda non ha ancora giorni. Creali dal tab Scheda.")
            }
        }
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xxl)
    }

    private func header(_ program: Program) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(program.name)
                    .greetingStyle()
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(ProgramPresentation.programStatus(program, now: app.now, calendar: app.calendar))
                    .font(.captionText)
                    .foregroundStyle(statusColor(program))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.s)

            settingsButton
        }
        .padding(.horizontal, Theme.Spacing.page)
    }

    /// Avviso sobrio: il testo cambia colore solo quando la scheda sta per finire.
    private func statusColor(_ program: Program) -> Color {
        let expired = program.isExpired(asOf: app.now, calendar: app.calendar)
        let expiring = program.isExpiringSoon(asOf: app.now, calendar: app.calendar)
        return (expired || expiring) ? Theme.Metric.arancio.deep : Theme.textSecondary
    }

    private var settingsButton: some View {
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

    // MARK: - Giorni

    private func dayChips(_ program: Program) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(program.days) { day in
                    FilterChip(day.name, isSelected: day.id == selectedDay(in: program)?.id) {
                        select(day.id)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
        }
    }

    // MARK: - Esercizi del giorno

    @ViewBuilder
    private func items(of day: ProgramDay, in program: Program) -> some View {
        if day.items.isEmpty {
            hint("Nessun esercizio in \(day.name). Aggiungili dal tab Scheda.")
        } else {
            let letters = ProgramPresentation.supersetLetters(in: day)
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(day.items) { item in
                    row(item, in: day, program: program, letter: item.supersetGroup.flatMap { letters[$0] })
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
        }
    }

    private func row(_ item: PlanItem, in day: ProgramDay, program: Program, letter: String?) -> some View {
        Button {
            openedItem = PlanItemContext(programID: program.id, dayID: day.id, itemID: item.id)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                content(of: item, letter: letter)

                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        // Allineata alla colonna del testo, non alla thumbnail.
                        .padding(.leading, 56 + Theme.Spacing.m)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Apre il dettaglio dell'esercizio"))
    }

    @ViewBuilder
    private func content(of item: PlanItem, letter: String?) -> some View {
        let summary = ProgramPresentation.itemSummary(item, unit: app.unit)
        if let exercise = app.store.exercise(id: item.exerciseID) {
            ExerciseRowView(exercise: exercise, subtitle: summary) {
                supersetDot(letter)
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
                supersetDot(letter)
            }
            .frame(minHeight: Theme.Size.minTapTarget)
            .accessibilityElement(children: .combine)
        }
    }

    /// Pallino del superset: in consultazione basta un segno, la lettera sta
    /// nell'etichetta VoiceOver.
    @ViewBuilder
    private func supersetDot(_ letter: String?) -> some View {
        if let letter {
            Circle()
                .fill(Theme.accent.deep)
                .frame(width: 8, height: 8)
                .accessibilityLabel(Text("Superset \(letter)"))
        }
    }

    // MARK: - Stati vuoti

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.captionText)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
    }

    private var empty: some View {
        EmptyStateView(
            systemImage: "list.bullet.rectangle",
            title: "Nessuna scheda",
            message: "Ricopia qui la scheda dell'istruttore: poi la consulti da questa pagina.",
            actionTitle: "Vai alla scheda",
            action: { app.router.tab = .program }
        )
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.xxxl * 2)
    }

    // MARK: - Selezione del giorno

    private func selectedDay(in program: Program) -> ProgramDay? {
        if let selectedDayID, let day = program.day(id: selectedDayID) { return day }
        return program.days.first
    }

    private func select(_ dayID: UUID) {
        selectedDayID = dayID
        storedDayID = dayID.uuidString
    }

    private func restoreSelection() {
        guard selectedDayID == nil, let stored = UUID(uuidString: storedDayID) else { return }
        guard app.store.activeProgram?.day(id: stored) != nil else { return }
        selectedDayID = stored
    }

    private func exerciseID(of context: PlanItemContext) -> String? {
        app.store.program(id: context.programID)?
            .day(id: context.dayID)?
            .items.first { $0.id == context.itemID }?
            .exerciseID
    }
}
