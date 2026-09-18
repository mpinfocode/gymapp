import SwiftUI
import GymCore
import GymUI

/// Creazione di una scheda e modifica dei suoi dettagli: un passo solo, cinque
/// domande, un bottone.
///
/// L'inserimento deve essere velocissimo: ogni campo ha già il valore giusto nel
/// 90% dei casi (nome con il mese, inizio oggi, 6 settimane, a rotazione, 3 giorni).
///
/// È `public` solo perché la scena di screenshot `scheda-nuova` la rende da sola:
/// dentro l'app la apre soltanto ``ProgramScreen``.
public struct ProgramFormSheet: View {

    /// Cosa sta facendo la sheet.
    public enum Mode: Hashable, Identifiable {
        /// Nuova scheda, che diventerà quella attiva.
        case create
        /// Modifica dei dettagli di una scheda esistente.
        case edit(UUID)

        public var id: String {
            switch self {
            case .create: "create"
            case .edit(let id): id.uuidString
            }
        }
    }

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode

    @State private var name = ""
    @State private var startDate: Date?
    @State private var hasDeadline = true
    @State private var weeks = 6
    @State private var programMode: ProgramMode = .rotation
    @State private var dayCount = 3
    @State private var confirmsReplacement = false
    @FocusState private var nameFocused: Bool

    public init(mode: Mode) {
        self.mode = mode
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                header
                nameField
                startField
                durationField
                modeField
                if case .create = mode { daysField }
                submit
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .pageBackground()
        .keyboardDoneToolbar { nameFocused = false }
        .onAppear(perform: load)
        .alert("C'è già una scheda attiva", isPresented: $confirmsReplacement) {
            Button("Annulla", role: .cancel) {}
            Button("Crea e archivia") { create() }
        } message: {
            Text("La scheda attiva finisce in archivio, con tutto il suo storico.")
        }
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isCreating ? "Nuova scheda" : "Dettagli")
                .sectionTitleStyle()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Theme.Spacing.m)

            Button("Annulla") { dismiss() }
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.Size.minTapTarget)
        }
    }

    // MARK: - Campi

    private var nameField: some View {
        field("Nome") {
            TextField("Scheda", text: $name)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .padding(.horizontal, Theme.Spacing.l)
                .frame(height: 52)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: Capsule(style: .continuous))
                .accessibilityLabel(Text("Nome della scheda"))
        }
    }

    private var startField: some View {
        field("Inizio") {
            HStack {
                DatePicker(
                    "Data di inizio",
                    selection: Binding(
                        get: { startDate ?? app.now },
                        set: { startDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()

                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.Size.minTapTarget)
        }
    }

    private var durationField: some View {
        field("Durata") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    if hasDeadline {
                        ProgramStepper(
                            title: "Durata in settimane",
                            value: weeks,
                            unit: "settimane",
                            range: 1...16
                        ) { weeks = $0 }
                    } else {
                        Text("Senza scadenza")
                            .font(.bodyText)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.Size.minTapTarget)

                Toggle("Senza scadenza", isOn: Binding(
                    get: { !hasDeadline },
                    set: { hasDeadline = !$0 }
                ))
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
                .toggleStyle(.switch)
                .tint(Theme.accent.fill)
                .frame(minHeight: Theme.Size.minTapTarget)
            }
        }
    }

    private var modeField: some View {
        field("Modalità") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                CapsuleSegmentedControl(
                    values: ProgramMode.allCases,
                    selection: $programMode,
                    title: \.displayName
                )
                Text(programMode.explanation)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var daysField: some View {
        field("Giorni") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    ProgramStepper(
                        title: "Numero di giorni",
                        value: dayCount,
                        unit: dayCount == 1 ? "giorno" : "giorni",
                        range: 1...7
                    ) { dayCount = $0 }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.Size.minTapTarget)

                Text(dayNamesPreview)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var dayNamesPreview: String {
        let names = (0..<min(dayCount, 3)).map { ProgramPresentation.defaultDayName(at: $0) }
        let suffix = dayCount > 3 ? ", …" : ""
        return names.joined(separator: ", ") + suffix + " · si rinominano dopo"
    }

    // MARK: - Conferma

    private var submit: some View {
        PrimaryButton(isCreating ? "Crea la scheda" : "Salva") {
            nameFocused = false
            if isCreating {
                if app.store.activeProgram != nil {
                    confirmsReplacement = true
                } else {
                    create()
                }
            } else {
                save()
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: - Stato

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var editedProgram: Program? {
        guard case .edit(let id) = mode else { return nil }
        return app.store.program(id: id)
    }

    private func load() {
        guard startDate == nil else { return }
        if let program = editedProgram {
            name = program.name
            startDate = program.startDate
            hasDeadline = (program.plannedWeeks ?? 0) > 0
            weeks = min(max(program.plannedWeeks ?? 6, 1), 16)
            programMode = program.mode
        } else {
            name = ProgramPresentation.defaultProgramName(now: app.now, calendar: app.calendar)
            startDate = app.now
        }
    }

    private var cleanName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? ProgramPresentation.defaultProgramName(now: app.now, calendar: app.calendar)
            : trimmed
    }

    private func create() {
        let program = app.store.createProgram(
            name: cleanName,
            startDate: startDate ?? app.now,
            plannedWeeks: hasDeadline ? weeks : nil,
            mode: programMode,
            activate: true
        )
        for index in 0..<dayCount {
            app.store.addDay(name: ProgramPresentation.defaultDayName(at: index), toProgram: program.id)
        }
        dismiss()
    }

    private func save() {
        guard case .edit(let id) = mode else { return }
        let start = startDate ?? app.now
        let planned = hasDeadline ? weeks : nil
        let newName = cleanName
        let newMode = programMode
        app.store.editProgram(id: id) { program in
            program.name = newName
            program.startDate = start
            program.plannedWeeks = planned
            program.mode = newMode
        }
        dismiss()
    }

    // MARK: - Blocco di campo

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).overlineStyle()
            content()
        }
    }
}
