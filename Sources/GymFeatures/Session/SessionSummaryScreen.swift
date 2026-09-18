import Foundation
import SwiftUI
import GymCore
import GymUI

/// Riepilogo di fine allenamento: durata, volume, serie, record, nota (SPEC §5.4).
/// Tema scuro immersivo con il gradiente della scheda a tutta pagina.
///
/// Serve due momenti con la stessa firma:
/// - subito dopo "Termina", quando la sessione è ancora quella in corso: "Fatto"
///   la archivia con la nota (`store.finishSession(notes:)`);
/// - riaperto da una sessione già salvata: "Fatto" aggiorna la nota e chiude.
@MainActor
public struct SessionSummaryScreen: View {

    private let sessionID: UUID

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    @State private var didLoadNote = false

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    public var body: some View {
        ZStack {
            Theme.background
            BlobGradient(seed: seed, intensity: 0.3)
            // Velo appena accennato: i pastello restano visibili ma le etichette
            // piccole mantengono il contrasto.
            Theme.background.opacity(0.3)
            content
        }
        .ignoresSafeArea()
        .immersiveDark()
        .keyboardDoneToolbar()
        .onAppear(perform: loadNote)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    Text(whisper)
                        .whisperStyle()

                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        stat("DURATA", value: durationText, unit: "min")
                        stat("VOLUME", value: volumeText, unit: app.unit.symbol)
                        stat("SERIE", value: "\(session?.completedSets ?? 0)", unit: nil)
                    }

                    if !records.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            Text("RECORD").overlineStyle()
                            ForEach(records) { record in
                                recordRow(record)
                            }
                        }
                    }

                    TextField("Nota", text: $note, axis: .vertical)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)
                        .padding(Theme.Spacing.l)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .fill(Theme.surface.opacity(0.7))
                        )
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.xxxl)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton("Fatto", variant: .light, action: done)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private func stat(_ title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).overlineStyle()
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(value).hugeNumberStyle()
                if let unit {
                    Text(unit)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func recordRow(_ record: SessionPresentation.RecordHighlight) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Text(app.store.exerciseDisplayName(id: record.exerciseID))
                .font(.bodyEmphasis)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            Text(record.kinds.first?.displayName ?? "")
                .font(.captionText)
                .foregroundStyle(Theme.accent.deep)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Dati

    /// La sessione: quella in corso finché non si tocca "Fatto", altrimenti l'archiviata.
    private var session: WorkoutSession? {
        if let active = app.store.activeSession, active.id == sessionID { return active }
        return app.store.session(id: sessionID)
    }

    private var seed: Int {
        guard let programID = session?.programID,
              let program = app.store.program(id: programID) else { return 0 }
        return program.accent
    }

    private var whisper: String {
        guard let session, session.completedSets > 0 else { return "allenamento chiuso" }
        return "ottimo lavoro"
    }

    /// Durata in minuti: numero grande, unità piccola (DESIGN.md).
    private var durationText: String {
        guard let session else { return Formatters.missing }
        let interval = session.isActive ? session.elapsed(asOf: app.now) : session.duration
        return "\(max(0, Int(interval.rounded()) / 60))"
    }

    private var volumeText: String {
        guard let session else { return Formatters.missing }
        return Formatters.volume(session.totalVolumeKg, unit: app.unit, includeSymbol: false)
    }

    /// Al massimo cinque righe: il riepilogo resta una schermata calma.
    private var records: [SessionPresentation.RecordHighlight] {
        guard let session else { return [] }
        let all = session.isActive
            ? SessionPresentation.liveHighlights(in: session, liveRecords: app.store.liveRecords)
            : SessionPresentation.archivedHighlights(in: session) { app.store.records(for: $0) }
        return Array(all.prefix(5))
    }

    // MARK: - Azioni

    private func loadNote() {
        guard !didLoadNote else { return }
        didLoadNote = true
        note = session?.notes ?? ""
    }

    private func done() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if app.store.activeSession?.id == sessionID {
            SessionRestTimer.shared.stop()
            SessionSetStopwatch.shared.stop()
            Haptics.play(.success)
            // Archivia la sessione: `RootView` chiude da sé la cover.
            _ = app.store.finishSession(notes: trimmed)
        } else if var stored = app.store.session(id: sessionID) {
            stored.notes = trimmed
            app.store.updateSession(stored)
            dismiss()
        } else {
            dismiss()
        }
    }
}
