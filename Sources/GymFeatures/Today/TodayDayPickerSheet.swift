import SwiftUI
import GymCore
import GymUI

/// Sheet "Scegli un altro giorno": i giorni della scheda più l'allenamento libero.
///
/// Non avvia niente: sceglie soltanto cosa propone la hero, così l'utente conferma
/// sempre con "Inizia".
struct TodayDayPickerSheet: View {

    /// Cosa ha scelto l'utente.
    enum Choice: Equatable {
        case day(UUID)
        case free
    }

    let days: [ProgramDay]
    let current: Choice?
    let onPick: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Scegli un altro giorno")
                    .sectionTitleStyle()
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Theme.Spacing.s)

                VStack(spacing: Theme.Spacing.s) {
                    ForEach(days) { day in
                        row(
                            title: day.name,
                            detail: detail(for: day),
                            isSelected: current == .day(day.id)
                        ) {
                            pick(.day(day.id))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Senza scheda")
                        .overlineStyle()
                    row(
                        title: "Allenamento libero",
                        detail: "aggiungi gli esercizi mentre ti alleni",
                        isSelected: current == .free
                    ) {
                        pick(.free)
                    }
                }
                .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .pageBackground()
    }

    private func pick(_ choice: Choice) {
        onPick(choice)
        dismiss()
    }

    private func detail(for day: ProgramDay) -> String {
        let count = day.items.count
        let word = count == 1 ? "esercizio" : "esercizi"
        let minutes = TodayModel.estimatedMinutes(of: day)
        guard minutes > 0 else { return "\(count) \(word)" }
        return "\(count) \(word) · circa \(minutes) min"
    }

    @ViewBuilder
    private func row(
        title: String,
        detail: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodyEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Theme.Spacing.s)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Theme.accent.deep)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: Theme.Size.minTapTarget + 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
