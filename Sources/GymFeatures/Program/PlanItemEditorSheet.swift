import SwiftUI
import GymCore
import GymUI

/// Editor di un esercizio della scheda: sheet a mezza altezza, tutto raggiungibile
/// con il pollice.
///
/// In alto quello che si cambia sempre (serie, ripetizioni o durata, carico,
/// recupero), sotto "Altro" quello che serve di rado (riscaldamento, superset,
/// nota). In fondo "Precedente" e "Successivo": si ricopia un giorno intero senza
/// chiudere mai la sheet. Ogni modifica si salva subito.
///
/// È `public` solo perché la scena di screenshot `scheda-editor-esercizio` la
/// rende da sola: dentro l'app la apre soltanto ``ProgramDayEditor``.
public struct PlanItemEditorSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    private let programID: UUID
    private let dayID: UUID

    @State private var itemID: UUID
    @State private var showsMore = false

    public init(programID: UUID, dayID: UUID, itemID: UUID) {
        self.programID = programID
        self.dayID = dayID
        _itemID = State(initialValue: itemID)
    }

    public var body: some View {
        ZStack {
            PageBackground()

            if let item {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            header
                            setsRow(item)
                            measurePicker(item)
                            measureFields(item)
                            weightField(item)
                            restField(item)
                            moreSection(item)
                        }
                        .padding(.horizontal, Theme.Spacing.page)
                        .padding(.top, Theme.Spacing.xl)
                        .padding(.bottom, Theme.Spacing.l)
                    }
                    .keyboardDismissable()

                    navigationBar
                }
            }
        }
        .keyboardDismissOnTap()
        .keyboardDoneToolbar()
    }

    // MARK: - Intestazione

    private var header: some View {
        SheetHeader(title: exerciseTitle, subtitle: position, actionTitle: "Fine") {
            dismiss()
        }
    }

    /// Titolo senza il prefisso dell'attrezzo, come nelle righe della scheda;
    /// se l'esercizio non si risolve più resta il nome salvato nello storico.
    private var exerciseTitle: String {
        let id = item?.exerciseID ?? ""
        return app.store.exercise(id: id)?.shortDisplayName ?? app.store.exerciseDisplayName(id: id)
    }

    private var position: String {
        guard let index, let total = day?.items.count else { return "" }
        return "esercizio \(index + 1) di \(total)"
    }

    // MARK: - Serie

    private func setsRow(_ item: PlanItem) -> some View {
        block("Serie") {
            HStack {
                ProgramStepper(title: "Serie", value: item.targetSets, range: 1...12) { newValue in
                    update { $0.targetSets = newValue }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Ripetizioni o durata

    private func measurePicker(_ item: PlanItem) -> some View {
        CapsuleSegmentedControl(
            values: MeasureKind.allCases,
            selection: Binding(
                get: { item.measure.kind },
                set: { kind in
                    guard kind != item.measure.kind else { return }
                    update { plan in
                        plan.measure = kind == .reps ? .reps(min: 8, max: 12) : .duration(seconds: 45)
                    }
                }
            ),
            title: \.displayName
        )
    }

    @ViewBuilder
    private func measureFields(_ item: PlanItem) -> some View {
        switch item.measure {
        case .reps(let minimum, let maximum):
            block("Ripetizioni") {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        NumberCapsuleField(
                            value: Binding(
                                get: { Optional(minimum) },
                                set: { newValue in
                                    let low = max(1, newValue ?? minimum)
                                    update { $0.measure = .reps(min: low, max: max(low, maximum)) }
                                }
                            ),
                            accessibilityTitle: "Ripetizioni minime"
                        )
                        .frame(width: 84)

                        Text("-")
                            .font(.bodyText)
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)

                        NumberCapsuleField(
                            value: Binding(
                                get: { Optional(maximum) },
                                set: { newValue in
                                    let high = max(1, newValue ?? maximum)
                                    update { $0.measure = .reps(min: min(minimum, high), max: high) }
                                }
                            ),
                            accessibilityTitle: "Ripetizioni massime"
                        )
                        .frame(width: 84)

                        Spacer(minLength: 0)
                    }

                    shortcuts(ProgramPresentation.repsShortcuts.map { range in
                        Shortcut(
                            title: "\(range.lowerBound)-\(range.upperBound)",
                            isSelected: minimum == range.lowerBound && maximum == range.upperBound
                        ) {
                            update { $0.measure = .reps(min: range.lowerBound, max: range.upperBound) }
                        }
                    })
                }
            }

        case .duration(let total):
            block("Durata") {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        NumberCapsuleField(
                            value: Binding(
                                get: { Optional(total) },
                                set: { newValue in
                                    update { $0.measure = .duration(seconds: max(1, newValue ?? total)) }
                                }
                            ),
                            accessibilityTitle: "Durata in secondi"
                        )
                        .frame(width: 84)
                        Text("s")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                    }

                    shortcuts(ProgramPresentation.durationShortcuts.map { seconds in
                        Shortcut(title: ProgramPresentation.seconds(seconds), isSelected: total == seconds) {
                            update { $0.measure = .duration(seconds: seconds) }
                        }
                    })
                }
            }
        }
    }

    // MARK: - Carico

    private func weightField(_ item: PlanItem) -> some View {
        block("Carico previsto") {
            HStack(spacing: Theme.Spacing.s) {
                NumberCapsuleField(
                    value: Binding(
                        get: { item.targetWeightKg.map { app.unit.value(fromKilograms: $0) } },
                        set: { newValue in
                            update { $0.targetWeightKg = newValue.map { app.unit.kilograms(from: $0) } }
                        }
                    ),
                    placeholder: Formatters.missing,
                    accessibilityTitle: "Carico previsto"
                )
                .frame(width: 110)
                Text(app.unit.symbol)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)

                Spacer(minLength: Theme.Spacing.s)

                ProgramStepperButton(
                    systemImage: "minus",
                    label: "Riduci: carico previsto",
                    isEnabled: previousWeight(item) != nil
                ) {
                    guard let value = previousWeight(item) else { return }
                    update { $0.targetWeightKg = value }
                }

                ProgramStepperButton(
                    systemImage: "plus",
                    label: "Aumenta: carico previsto",
                    isEnabled: nextWeight(item) != nil
                ) {
                    guard let value = nextWeight(item) else { return }
                    update { $0.targetWeightKg = value }
                }
            }
            .frame(minHeight: Theme.Size.minTapTarget)
        }
    }

    /// Attrezzo dell'esercizio, per il passo di carico. Vuoto se l'esercizio non
    /// si risolve (libreria non pronta, esercizio rimosso): ``WeightStep`` ricade
    /// allora sul passo generico di 2,5 kg.
    private func equipment(of item: PlanItem) -> String {
        app.store.exercise(id: item.exerciseID)?.equipment ?? ""
    }

    /// Carico al passo successivo dell'attrezzo (manubri +2, bilanciere +2,5,
    /// macchine +5). Da vuoto parte dal primo passo utile.
    private func nextWeight(_ item: PlanItem) -> Double? {
        WeightStep.next(after: item.targetWeightKg ?? 0, forEquipment: equipment(of: item))
    }

    /// Carico al passo precedente: `nil` a campo vuoto, sotto lo zero o sugli
    /// attrezzi che non si caricano (corpo libero, elastici).
    private func previousWeight(_ item: PlanItem) -> Double? {
        guard let current = item.targetWeightKg else { return nil }
        return WeightStep.previous(before: current, forEquipment: equipment(of: item))
    }

    // MARK: - Recupero

    private func restField(_ item: PlanItem) -> some View {
        block("Recupero", value: ProgramPresentation.seconds(item.restSeconds)) {
            shortcuts(ProgramPresentation.restShortcuts.map { seconds in
                Shortcut(
                    title: ProgramPresentation.seconds(seconds),
                    isSelected: item.restSeconds == seconds
                ) {
                    update { $0.restSeconds = seconds }
                }
            })
        }
    }

    // MARK: - Altro

    @ViewBuilder
    private func moreSection(_ item: PlanItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button {
                withAnimation(Theme.Motion.smooth) { showsMore.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Altro")
                        .font(.system(.subheadline, weight: .medium))
                    Image(systemName: showsMore ? "chevron.up" : "chevron.down")
                        .font(.system(.caption, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: Theme.Size.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Altro"))
            .accessibilityValue(Text(showsMore ? "aperto" : "chiuso"))
            .overlay(alignment: .bottomLeading) {
                if !showsMore {
                    Text("riscaldamento, superset, nota")
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .allowsHitTesting(false)
                        .offset(y: 14)
                }
            }

            if showsMore {
                warmupRow(item)
                supersetRow(item)
                noteRow(item)
            }
        }
    }

    private func warmupRow(_ item: PlanItem) -> some View {
        block("Serie di riscaldamento") {
            HStack {
                ProgramStepper(
                    title: "Serie di riscaldamento",
                    value: item.warmupSets,
                    range: 0...5
                ) { newValue in
                    update { $0.warmupSets = newValue }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func supersetRow(_ item: PlanItem) -> some View {
        if let index, let items = day?.items, items.count > 1 {
            block("Superset") {
                HStack(spacing: Theme.Spacing.s) {
                    if index > 0 {
                        FilterChip(
                            "con il precedente",
                            isSelected: ProgramPresentation.areLinked(items, index, index - 1)
                        ) {
                            link(with: index - 1)
                        }
                    }
                    if index < items.count - 1 {
                        FilterChip(
                            "con il successivo",
                            isSelected: ProgramPresentation.areLinked(items, index, index + 1)
                        ) {
                            link(with: index + 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func noteRow(_ item: PlanItem) -> some View {
        block("Nota") {
            TextField("presa stretta", text: Binding(
                get: { item.note },
                set: { newValue in update { $0.note = newValue } }
            ))
            .font(.bodyText)
            .foregroundStyle(Theme.textPrimary)
            .textFieldStyle(.plain)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: Capsule(style: .continuous))
            .accessibilityLabel(Text("Nota dell'esercizio"))
        }
    }

    // MARK: - Precedente e successivo

    private var navigationBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            PillButton("Precedente", systemImage: "chevron.left") { move(by: -1) }
                .disabled(!canMove(by: -1))
                .opacity(canMove(by: -1) ? 1 : 0.35)

            Spacer(minLength: 0)

            PillButton("Successivo", systemImage: "chevron.right") { move(by: 1) }
                .disabled(!canMove(by: 1))
                .opacity(canMove(by: 1) ? 1 : 0.35)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.l)
        // Fondo pieno proprio, esteso sotto l'home indicator: la barra non dipende
        // da nessuna propagazione di safe area per stare al posto giusto.
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }

    private func canMove(by offset: Int) -> Bool {
        guard let index, let items = day?.items else { return false }
        return items.indices.contains(index + offset)
    }

    private func move(by offset: Int) {
        guard let index, let items = day?.items, items.indices.contains(index + offset) else { return }
        // Nessuna animazione: passare all'esercizio successivo sostituisce tutto il
        // contenuto della sheet, e animare un cambio così ampio significa ricomporre
        // otto blocchi a ogni fotogramma per mezzo secondo. Il salto è più onesto.
        itemID = items[index + offset].id
    }

    // MARK: - Scorciatoie

    private struct Shortcut: Identifiable {
        let title: String
        let isSelected: Bool
        let action: () -> Void
        var id: String { title }
    }

    /// Chip su due righe da tre: restano tutte visibili, senza scorrimento laterale.
    private func shortcuts(_ values: [Shortcut], perRow: Int = 3) -> some View {
        let rows = stride(from: 0, to: values.count, by: perRow).map { start in
            Array(values[start..<min(start + perRow, values.count)])
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(rows[index]) { shortcut in
                        FilterChip(shortcut.title, isSelected: shortcut.isSelected, action: shortcut.action)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Stato e mutazioni

    private var day: ProgramDay? {
        app.store.program(id: programID)?.day(id: dayID)
    }

    private var item: PlanItem? {
        day?.items.first { $0.id == itemID }
    }

    private var index: Int? {
        day?.items.firstIndex { $0.id == itemID }
    }

    /// Applica una modifica alla voce corrente e la salva subito.
    private func update(_ change: (inout PlanItem) -> Void) {
        guard var updated = item else { return }
        change(&updated)
        app.store.updateItem(updated, inDay: dayID, inProgram: programID)
    }

    /// Lega o slega il superset con la voce vicina, aggiornando entrambe.
    private func link(with neighbor: Int) {
        guard let index else { return }
        app.store.editDay(id: dayID, inProgram: programID) { day in
            day.items = ProgramPresentation.toggleSuperset(day.items, at: index, with: neighbor)
        }
    }

    // MARK: - Blocco di campo

    @ViewBuilder
    private func block<Content: View>(
        _ title: String,
        value: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(title).overlineStyle()
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
            }
            content()
        }
    }
}
