import SwiftUI
import GymCore
import GymUI

/// Correzione a posteriori di **una serie** già archiviata.
///
/// Non è un editor della sessione: non si aggiungono né si tolgono serie, non si
/// cambia il tipo né l'esercizio. Si correggono solo i numeri sbagliati al
/// momento della registrazione (carico, ripetizioni o durata, RPE), che è il caso
/// reale: ci si accorge dopo di aver scritto 80 invece di 90.
public struct SetCorrectionSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let sessionID: UUID
    private let entryID: UUID
    private let setID: UUID

    /// Carico nell'unità mostrata all'utente: la conversione in kg avviene al salvataggio.
    @State private var weight: Double?
    @State private var reps: Int?
    @State private var durationSec: Int?
    @State private var rpe: Double?
    @State private var isLoaded = false

    public init(sessionID: UUID, entryID: UUID, setID: UUID) {
        self.sessionID = sessionID
        self.entryID = entryID
        self.setID = setID
    }

    private var entry: SessionEntry? {
        app.store.session(id: sessionID)?.entries.first { $0.id == entryID }
    }

    private var set: SetLog? {
        entry?.sets.first { $0.id == setID }
    }

    private var position: Int {
        guard let entry, let index = entry.sets.firstIndex(where: { $0.id == setID }) else { return 1 }
        return entry.sets.prefix(upTo: index).filter(\.isCompleted).count + 1
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                if let entry {
                    VStack(spacing: 0) {
                        switch entry.measureKind {
                        case .reps:
                            field("Carico", unit: app.unit.symbol) {
                                NumberCapsuleField(
                                    value: $weight,
                                    placeholder: Formatters.missing,
                                    accessibilityTitle: "Carico"
                                )
                            }
                            field("Ripetizioni") {
                                NumberCapsuleField(
                                    value: $reps,
                                    placeholder: Formatters.missing,
                                    accessibilityTitle: "Ripetizioni"
                                )
                            }
                        case .duration:
                            field("Durata", unit: "s") {
                                NumberCapsuleField(
                                    value: $durationSec,
                                    placeholder: Formatters.missing,
                                    accessibilityTitle: "Durata in secondi"
                                )
                            }
                        }
                        field("RPE", showsSeparator: false) {
                            NumberCapsuleField(
                                value: $rpe,
                                placeholder: Formatters.missing,
                                accessibilityTitle: "Sforzo percepito"
                            )
                        }
                    }
                }

                PrimaryButton("Salva", action: save)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .pageBackground()
        .keyboardDoneToolbar()
        .onAppear(perform: load)
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button("Annulla") { dismiss() }
                .font(.bodyText)
                .foregroundStyle(Theme.textSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Correggi serie \(position)")
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)

                if let entry {
                    Text(app.store.exerciseDisplayName(id: entry.exerciseID))
                        .captionStyle()
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Campi

    private func field<Content: View>(
        _ title: String,
        unit: String? = nil,
        showsSeparator: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(.bodyText)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.s)

                content()
                    .frame(width: 92)

                Text(unit ?? "")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18, alignment: .leading)
            }
            .padding(.vertical, Theme.Spacing.s)

            if showsSeparator {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.Size.hairline)
            }
        }
    }

    // MARK: - Dati

    private func load() {
        guard !isLoaded, let set else { return }
        isLoaded = true
        weight = set.weightKg.map { app.unit.value(fromKilograms: $0) }
        reps = set.reps
        durationSec = set.durationSec
        rpe = set.rpe
    }

    private func save() {
        guard var session = app.store.session(id: sessionID),
              let entryIndex = session.entries.firstIndex(where: { $0.id == entryID }),
              let setIndex = session.entries[entryIndex].sets.firstIndex(where: { $0.id == setID })
        else {
            dismiss()
            return
        }

        let measure = session.entries[entryIndex].measureKind
        var set = session.entries[entryIndex].sets[setIndex]
        switch measure {
        case .reps:
            set.weightKg = weight.map { app.unit.kilograms(from: $0) }
            set.reps = reps
        case .duration:
            set.durationSec = durationSec
        }
        set.rpe = SetLog.normalizedRPE(rpe)

        session.entries[entryIndex].sets[setIndex] = set
        app.store.updateSession(session)
        dismiss()
    }
}
