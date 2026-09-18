import SwiftUI
import GymCore
import GymUI

/// Tab **Oggi**: una pagina corta e calma (SPEC §5.1, DESIGN "Home corta").
///
/// Dall'alto: data e saluto, la hero dell'allenamento di oggi, una riga per
/// scegliere un altro giorno, lo stato della scheda, la settimana e tre numeri.
/// Lo storico non sta qui: sta in Progressi.
public struct TodayScreen: View {

    @Environment(AppEnvironment.self) private var app

    @State private var showsSettings = false
    @State private var showsDayPicker = false
    /// Giorno scelto a mano al posto di quello proposto dalla scheda.
    @State private var choice: TodayDayPickerSheet.Choice?

    public init() {}

    public var body: some View {
        ZStack {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    hero
                    if let program = app.store.activeProgram, !program.days.isEmpty {
                        chooseDayRow
                        statusRow(for: program)
                    }
                    if showsWeek {
                        weekSection
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            // La pagina sta in una schermata: l'indicatore non serve. Serve invece
            // a togliere i 18 punti che la barra di scorrimento "legacy" di macOS
            // si prende a destra quando il contenuto sborda, rendendo asimmetrici
            // i margini negli screenshot (su iOS l'indicatore è sempre in overlay).
            .scrollIndicators(.never)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsScreen()
        }
        .sheet(isPresented: $showsDayPicker) {
            TodayDayPickerSheet(
                days: app.store.activeProgram?.days ?? [],
                current: choice,
                onPick: { choice = $0 }
            )
        }
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(Formatters.longDateUppercased(app.now, calendar: app.calendar))
                    .overlineStyle()
                Text(TodayModel.greeting(at: app.now, name: app.store.settings.displayName, calendar: app.calendar))
                    .greetingStyle()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: Theme.Spacing.s)

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Impostazioni"))
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        if let variant = heroVariant, let program = app.store.activeProgram {
            TodayHeroCard(
                seed: program.accent,
                chipText: program.name,
                variant: variant,
                onPrimary: primaryAction,
                onTrainAnyway: { showsDayPicker = true }
            )
        } else if app.store.activeProgram == nil {
            EmptyStateView(
                systemImage: "list.bullet.rectangle",
                title: "Nessuna scheda",
                message: "Ricopia la scheda dell'istruttore e l'allenamento di oggi comparirà qui.",
                actionTitle: "Crea la tua scheda",
                action: { app.router.tab = .program }
            )
        } else {
            EmptyStateView(
                systemImage: "calendar",
                title: "Scheda senza giorni",
                message: "Aggiungi il primo giorno alla scheda per vedere qui l'allenamento.",
                actionTitle: "Apri la scheda",
                action: { app.router.tab = .program }
            )
        }
    }

    /// Stato della hero, in ordine di precedenza.
    private var heroVariant: TodayHeroCard.Variant? {
        guard app.store.activeProgram != nil else { return nil }

        if let session = app.store.activeSession {
            let minutes = Formatters.minutes(session.elapsed(asOf: app.now))
            let sets = session.completedSets
            let word = sets == 1 ? "serie completata" : "serie completate"
            return .running(title: session.name, summary: "\(sets) \(word) · \(minutes)")
        }

        if choice == nil, let done = TodayModel.sessionCompletedToday(
            in: app.store.sessions,
            now: app.now,
            calendar: app.calendar
        ) {
            return .completed(
                title: done.name,
                value: Formatters.volume(done.totalVolumeKg, unit: app.unit, includeSymbol: false),
                detail: "\(app.unit.symbol) sollevati in \(Formatters.minutes(done.duration))"
            )
        }

        if choice == .free {
            return .workout(
                title: "Allenamento libero",
                summary: "senza scheda, aggiungi gli esercizi mentre ti alleni"
            )
        }

        if let day = selectedDay {
            return .workout(title: day.name, summary: TodayModel.summary(of: day))
        }

        return app.store.todaysWorkout().isRest ? .rest : nil
    }

    /// Giorno che la hero propone: quello scelto a mano, altrimenti quello della scheda.
    private var selectedDay: ProgramDay? {
        guard let program = app.store.activeProgram else { return nil }
        if case .day(let id) = choice { return program.day(id: id) }
        return app.store.todaysWorkout().programDay
    }

    private func primaryAction() {
        if app.store.activeSession != nil {
            // La cover la presenta la shell: qui basta togliere la minimizzazione.
            app.router.resumeSession()
            return
        }
        if choice == .free {
            app.store.startFreeSession()
            choice = nil
            return
        }
        guard let program = app.store.activeProgram, let day = selectedDay else { return }
        app.store.startSession(programID: program.id, dayID: day.id)
        choice = nil
    }

    // MARK: - Scegli un altro giorno

    private var chooseDayRow: some View {
        Button {
            showsDayPicker = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Text("Scegli un altro giorno")
                    .font(.system(.subheadline, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Scegli un altro giorno"))
    }

    // MARK: - Stato della scheda

    @ViewBuilder
    private func statusRow(for program: Program) -> some View {
        switch TodayModel.status(of: program, now: app.now, calendar: app.calendar) {
        case .none:
            EmptyView()

        case .progress(let text, let fraction):
            HStack(spacing: Theme.Spacing.l) {
                Text(text)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                ThickProgressBar(
                    value: fraction,
                    total: 1,
                    height: 6,
                    tint: Theme.ink,
                    accessibilityTitle: "Avanzamento della scheda"
                )
                .frame(maxWidth: 120)
            }
            .accessibilityElement(children: .combine)

        case .warning(let text):
            Text(text)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.Metric.arancio.deep)
        }
    }

    // MARK: - Settimana

    private var showsWeek: Bool {
        app.store.activeProgram != nil || !app.store.sessions.isEmpty
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Questa settimana")
                .overlineStyle()

            WeekStrip(days: TodayModel.weekDays(
                now: app.now,
                calendar: app.calendar,
                sessions: app.store.sessions,
                program: app.store.activeProgram
            ))

            weeklyNumbers
        }
    }

    private var weeklyNumbers: some View {
        let summary = app.store.currentWeekSummary()
        return HStack(alignment: .top, spacing: Theme.Spacing.l) {
            number("\(summary.workouts)", label: summary.workouts == 1 ? "allenamento" : "allenamenti")
            number("\(summary.minutes)", label: "minuti")
            number(
                Formatters.volume(summary.volumeKg, unit: app.unit, includeSymbol: false),
                label: "\(app.unit.symbol) di volume"
            )
        }
    }

    private func number(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(value)
                .bigNumberStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .captionStyle()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
