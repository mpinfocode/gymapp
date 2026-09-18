import SwiftUI
import GymCore
import GymUI

/// Sessione attiva, presentata a schermo intero da `RootView` quando
/// `store.activeSession != nil` (SPEC §5.4). Tema scuro immersivo sempre.
///
/// Struttura: un esercizio alla volta in primo piano dentro una **fisarmonica
/// verticale**. Rispetto al pager orizzontale mantiene un solo asse di scorrimento
/// (le celle numeriche e il timer non litigano con lo swipe), lascia vedere a
/// colpo d'occhio quanto manca alla fine, rende naturale il raggruppamento dei
/// superset e non richiede gesti precisi con le mani sudate.
///
/// `onMinimize` chiude la cover **senza** terminare la sessione.
@MainActor
public struct ActiveSessionScreen: View {

    private let onMinimize: () -> Void

    @Environment(AppEnvironment.self) private var app

    @State private var pinnedEntryID: UUID?
    @State private var sheet: SessionSheet?
    @State private var finishPrompt = false
    @State private var summarySessionID: UUID?
    @State private var didRestoreRest = false

    /// - Parameter onMinimize: chiude la cover lasciando la sessione in corso.
    public init(onMinimize: @escaping () -> Void) {
        self.onMinimize = onMinimize
    }

    public var body: some View {
        ZStack {
            background

            if let session = app.store.activeSession {
                content(session)
            } else {
                EmptyStateView(
                    systemImage: "figure.run",
                    title: "Nessun allenamento",
                    message: "Avvia un allenamento da Oggi."
                )
            }

            if let summarySessionID {
                SessionSummaryScreen(sessionID: summarySessionID)
                    .transition(.opacity)
            }
        }
        .immersiveDark()
        .keyboardDoneToolbar()
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog(
            finishTitle,
            isPresented: $finishPrompt,
            titleVisibility: .visible
        ) {
            finishActions
        }
        .onAppear(perform: restoreRestIfNeeded)
    }

    // MARK: - Sfondo

    /// Nero pieno con il gradiente della scheda, molto tenue, solo dietro all'header.
    private var background: some View {
        ZStack(alignment: .top) {
            Theme.background
            BlobGradient(seed: programSeed, intensity: 0.3)
                .frame(height: 300)
                .mask(
                    LinearGradient(
                        colors: [Theme.textPrimary, Theme.textPrimary.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0.4)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var programSeed: Int {
        guard let programID = app.store.activeSession?.programID,
              let program = app.store.program(id: programID) else { return 0 }
        return program.accent
    }

    // MARK: - Contenuto

    private func content(_ session: WorkoutSession) -> some View {
        VStack(spacing: 0) {
            header(session)

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.m) {
                    ForEach(SessionPresentation.blocks(in: session)) { block in
                        blockView(block, in: session)
                    }
                    addExerciseRow
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if SessionRestTimer.shared.isRunning {
                RestPanel(onFinished: restDidFinish)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func header(_ session: WorkoutSession) -> some View {
        let progress = SessionPresentation.progress(in: session)

        return VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Riduci a icona"))

                Spacer(minLength: 0)

                TimelineView(.periodic(from: app.now, by: 1)) { _ in
                    Text(Formatters.clock(session.elapsed(asOf: app.now)))
                        .bigNumberStyle()
                        .accessibilityLabel(Text("Durata dell'allenamento"))
                }

                Spacer(minLength: 0)

                Button {
                    finishTapped(session)
                } label: {
                    Text("Termina")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(height: Theme.Size.minTapTarget)
                        .padding(.horizontal, Theme.Spacing.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(subtitle(session, progress: progress))
                .font(.captionText)
                .textCase(.lowercase)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
    }

    private func subtitle(_ session: WorkoutSession, progress: (current: Int, total: Int)) -> String {
        guard progress.total > 0 else { return session.name }
        return "\(session.name) · esercizio \(progress.current) di \(progress.total)"
    }

    @ViewBuilder
    private func blockView(_ block: SessionPresentation.Block, in session: WorkoutSession) -> some View {
        if block.isSuperset {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("superset")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Theme.accent.deep)
                    .padding(.leading, Theme.Spacing.m)

                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Capsule(style: .continuous)
                        .fill(Theme.accent.fill.opacity(0.6))
                        .frame(width: 3)
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(block.entries) { entry in
                            card(entry, in: session)
                        }
                    }
                }
            }
        } else {
            ForEach(block.entries) { entry in
                card(entry, in: session)
            }
        }
    }

    private func card(_ entry: SessionEntry, in session: WorkoutSession) -> some View {
        SessionExerciseCard(
            entry: entry,
            isExpanded: entry.id == SessionPresentation.foregroundEntryID(in: session, pinned: pinnedEntryID),
            onExpand: {
                withAnimation(Theme.Motion.spring) { pinnedEntryID = entry.id }
            },
            onComplete: { entryID in startRest(for: entryID) },
            onAction: handle
        )
    }

    private var addExerciseRow: some View {
        Button {
            sheet = .addExercise
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Aggiungi esercizio")
                    .font(.bodyText)
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 56)
            .padding(.horizontal, Theme.Spacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recupero

    private func startRest(for entryID: UUID) {
        guard let session = app.store.activeSession,
              let entry = session.entries.first(where: { $0.id == entryID }) else { return }
        guard SessionPresentation.startsRest(entryID: entryID, in: session) else { return }
        let seconds = entry.restSeconds > 0 ? entry.restSeconds : app.store.settings.defaultRestSeconds
        withAnimation(Theme.Motion.spring) {
            SessionRestTimer.shared.start(
                seconds: seconds,
                entryID: entryID,
                exerciseName: app.store.exerciseDisplayName(id: entry.exerciseID),
                sessionID: session.id,
                now: app.now
            )
        }
    }

    private func restDidFinish() {
        Haptics.play(.success)
        withAnimation(Theme.Motion.spring) { SessionRestTimer.shared.stop() }
    }

    /// Riapertura a metà allenamento: il recupero riparte dallo stato salvato
    /// (l'istante di completamento dell'ultima serie più il recupero dell'esercizio).
    private func restoreRestIfNeeded() {
        guard !didRestoreRest else { return }
        didRestoreRest = true
        guard let session = app.store.activeSession else { return }
        SessionRestTimer.shared.reset(for: session.id)
        guard !SessionRestTimer.shared.isRunning,
              let pending = SessionPresentation.pendingRest(in: session, asOf: app.now) else { return }
        SessionRestTimer.shared.restore(
            endsAt: pending.endsAt,
            totalSeconds: pending.totalSeconds,
            entryID: pending.entryID,
            exerciseName: app.store.exerciseDisplayName(id: pending.exerciseID),
            sessionID: session.id,
            now: app.now
        )
    }

    // MARK: - Azioni sugli esercizi

    private func handle(_ action: SessionEntryAction) {
        switch action {
        case .instructions(let exerciseID):
            sheet = .instructions(exerciseID)
        case .note(let entryID):
            sheet = .note(entryID)
        case .replace(let entryID):
            sheet = .replace(entryID)
        case .setOptions(let entryID, let setID):
            sheet = .setOptions(entryID, setID)
        case .addSet(let entryID):
            _ = app.store.addSet(toEntry: entryID)
            Haptics.play(.light)
        case .remove(let entryID):
            withAnimation(Theme.Motion.spring) {
                app.store.removeEntryFromActiveSession(id: entryID)
            }
        case .moveUp(let entryID):
            move(entryID, by: -1)
        case .moveDown(let entryID):
            move(entryID, by: 1)
        }
    }

    private func move(_ entryID: UUID, by offset: Int) {
        guard let session = app.store.activeSession,
              let index = session.entries.firstIndex(where: { $0.id == entryID }) else { return }
        let destination = offset < 0 ? index - 1 : index + 2
        guard destination >= 0, destination <= session.entries.count else { return }
        withAnimation(Theme.Motion.spring) {
            app.store.moveEntriesInActiveSession(fromOffsets: IndexSet(integer: index), toOffset: destination)
        }
    }

    // MARK: - Fine allenamento

    private func finishTapped(_ session: WorkoutSession) {
        let pending = session.entries.contains { entry in entry.sets.contains { !$0.isCompleted } }
        if pending || !session.hasLoggedWork {
            finishPrompt = true
        } else {
            openSummary(session)
        }
    }

    private var finishTitle: String {
        guard let session = app.store.activeSession else { return "Termina" }
        return session.hasLoggedWork
            ? "Ci sono serie non completate"
            : "Non hai completato nessuna serie"
    }

    @ViewBuilder
    private var finishActions: some View {
        if let session = app.store.activeSession {
            if session.hasLoggedWork {
                Button("Termina comunque") { openSummary(session) }
            } else {
                // Niente da salvare: l'unica uscita sensata è scartare.
                Button("Scarta allenamento", role: .destructive) {
                    SessionRestTimer.shared.stop()
                    SessionSetStopwatch.shared.stop()
                    app.store.discardSession()
                }
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func openSummary(_ session: WorkoutSession) {
        SessionRestTimer.shared.stop()
        SessionSetStopwatch.shared.stop()
        withAnimation(Theme.Motion.smooth) { summarySessionID = session.id }
    }

    // MARK: - Sheet

    @ViewBuilder
    private func sheetContent(_ sheet: SessionSheet) -> some View {
        switch sheet {
        case .instructions(let exerciseID):
            ExerciseInstructionsSheet(exerciseID: exerciseID)
        case .note(let entryID):
            EntryNoteSheet(entryID: entryID)
        case .replace(let entryID):
            ReplaceExerciseSheet(entryID: entryID)
        case .setOptions(let entryID, let setID):
            SetOptionsSheet(entryID: entryID, setID: setID)
        case .addExercise:
            ExercisePickerSheet(
                title: "Aggiungi esercizio",
                allowsMultipleSelection: true,
                excludedIDs: Set(app.store.activeSession?.exerciseIDs ?? [])
            ) { picked in
                self.sheet = nil
                for exercise in picked {
                    _ = app.store.addExerciseToActiveSession(exercise.id)
                }
            }
        }
    }
}

/// Sheet locali della sessione: nessuna rotta condivisa, restano dentro la feature.
enum SessionSheet: Identifiable {
    case instructions(String)
    case note(UUID)
    case replace(UUID)
    case setOptions(UUID, UUID)
    case addExercise

    var id: String {
        switch self {
        case .instructions(let value): "istruzioni-\(value)"
        case .note(let value): "nota-\(value.uuidString)"
        case .replace(let value): "sostituisci-\(value.uuidString)"
        case .setOptions(let entry, let set): "serie-\(entry.uuidString)-\(set.uuidString)"
        case .addExercise: "aggiungi"
        }
    }
}
