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
///
/// La **scelta del giorno** vive in ``HomeDaySection``, non qui: cambiare chip deve
/// ridisegnare i chip e l'elenco, non anche la testata con il nome della scheda e il
/// calcolo della settimana.
public struct HomeScreen: View {

    @Environment(AppEnvironment.self) private var app

    /// Giorno imposto dall'esterno (screenshot); `nil` = si ricorda l'ultimo scelto.
    private let initialDayID: UUID?

    public init() {
        self.initialDayID = nil
    }

    /// Init con un giorno già scelto: la usano gli screenshot per fotografare un
    /// giorno preciso senza dipendere da quello ricordato.
    public init(dayID: UUID) {
        self.initialDayID = dayID
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let program = app.store.activeProgram {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        HomeHeader(program: program)
                        HomeDaySection(program: program, initialDayID: initialDayID)
                    }
                    .padding(.top, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.xxl)
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
    }

    private static let topAnchor = "home-top"

    // MARK: - Nessuna scheda

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
}

// MARK: - Testata

/// Nome della scheda, stato ("Settimana 3 di 6") e ingranaggio delle Impostazioni.
///
/// Riceve la scheda già risolta e non legge altro: cambiare giorno non la tocca.
private struct HomeHeader: View {

    @Environment(AppEnvironment.self) private var app

    let program: Program

    var body: some View {
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
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .padding(.horizontal, Theme.Spacing.page)
    }

    /// Avviso sobrio: il testo cambia colore solo quando la scheda sta per finire.
    private var statusColor: Color {
        let expired = program.isExpired(asOf: app.now, calendar: app.calendar)
        let expiring = program.isExpiringSoon(asOf: app.now, calendar: app.calendar)
        return (expired || expiring) ? Theme.Metric.arancio.deep : Theme.textSecondary
    }
}

// MARK: - Giorni ed esercizi

/// Chip dei giorni ed elenco del giorno scelto.
///
/// Possiede la selezione: toccare un chip rivaluta **questo** body e basta.
private struct HomeDaySection: View {

    @Environment(AppEnvironment.self) private var app

    let program: Program
    let initialDayID: UUID?

    /// Ultimo giorno consultato, ricordato fra un avvio e l'altro.
    @AppStorage("home.lastDayID") private var storedDayID = ""

    @State private var selectedDayID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if program.days.count > 1 {
                dayChips
            }

            if let day = selectedDay {
                items(of: day)
            } else {
                hint("Questa scheda non ha ancora giorni. Creali dal tab Scheda.")
            }
        }
        .onAppear(perform: restoreSelection)
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(program.days) { day in
                    FilterChip(day.name, isSelected: day.id == selectedDay?.id) {
                        select(day.id)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
        }
    }

    @ViewBuilder
    private func items(of day: ProgramDay) -> some View {
        if day.items.isEmpty {
            hint("Nessun esercizio in \(day.name). Aggiungili dal tab Scheda.")
        } else {
            let letters = ProgramPresentation.supersetLetters(in: day)
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(day.items) { item in
                    HomeItemRow(
                        item: item,
                        route: .planItem(programID: program.id, dayID: day.id, itemID: item.id),
                        letter: item.supersetGroup.flatMap { letters[$0] }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.captionText)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.page)
    }

    // MARK: - Selezione del giorno

    private var selectedDay: ProgramDay? {
        if let selectedDayID, let day = program.day(id: selectedDayID) { return day }
        return program.days.first
    }

    private func select(_ dayID: UUID) {
        selectedDayID = dayID
        storedDayID = dayID.uuidString
    }

    private func restoreSelection() {
        guard selectedDayID == nil else { return }
        if let initialDayID, program.day(id: initialDayID) != nil {
            selectedDayID = initialDayID
            return
        }
        guard let stored = UUID(uuidString: storedDayID), program.day(id: stored) != nil else { return }
        selectedDayID = stored
    }
}

/// Una riga del giorno: thumbnail, nome, "4 × 6-8 · 80 kg · 2:30" e la nota.
///
/// È un `NavigationLink` su una rotta condivisa: il dettaglio con la prescrizione si
/// apre dentro il path del tab, quindi il ritocco dell'icona lo chiude davvero.
private struct HomeItemRow: View {

    @Environment(AppEnvironment.self) private var app

    let item: PlanItem
    let route: AppRoute
    let letter: String?

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                content

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
        .buttonStyle(.plain)
        .accessibilityHint(Text("Apre il dettaglio dell'esercizio"))
    }

    @ViewBuilder
    private var content: some View {
        let summary = ProgramPresentation.itemSummary(item, unit: app.unit)
        if let exercise = app.store.exercise(id: item.exerciseID) {
            ExerciseRowView(
                presentation: app.rowPresentation(for: exercise),
                imageURL: exercise.imageURL,
                subtitle: summary
            ) {
                supersetDot
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
                supersetDot
            }
            .frame(minHeight: Theme.Size.minTapTarget)
            .accessibilityElement(children: .combine)
        }
    }

    /// Pallino del superset: in consultazione basta un segno, la lettera sta
    /// nell'etichetta VoiceOver.
    @ViewBuilder
    private var supersetDot: some View {
        if let letter {
            Circle()
                .fill(Theme.accent.deep)
                .frame(width: 8, height: 8)
                .accessibilityLabel(Text("Superset \(letter)"))
        }
    }
}
