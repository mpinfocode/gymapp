import SwiftUI

/// Stato di un giorno nella striscia settimanale.
public enum DayState: Sendable, Hashable {
    /// Allenamento completato.
    case completed
    /// Allenamento pianificato, non ancora fatto.
    case planned
    /// Giorno di riposo.
    case rest
}

/// Un giorno della striscia settimanale.
public struct WeekDayItem: Identifiable, Sendable, Hashable {
    /// Indice 0 = lunedì ... 6 = domenica.
    public let id: Int
    /// Iniziale mostrata ("L", "M", …).
    public let initial: String
    /// Nome esteso per VoiceOver ("lunedì").
    public let fullName: String
    /// Numero del giorno del mese, opzionale.
    public let dayNumber: Int?
    /// Stato del giorno.
    public let state: DayState
    /// Vero solo per il giorno corrente.
    public let isToday: Bool

    public init(
        id: Int,
        initial: String,
        fullName: String,
        dayNumber: Int? = nil,
        state: DayState,
        isToday: Bool
    ) {
        self.id = id
        self.initial = initial
        self.fullName = fullName
        self.dayNumber = dayNumber
        self.state = state
        self.isToday = isToday
    }
}

/// Striscia dei sette giorni da lunedì a domenica: giorno corrente con cerchio pieno accento,
/// completati con riempimento pastello, pianificati in grigio, riposo con solo contorno.
public struct WeekStrip: View {

    private let days: [WeekDayItem]
    private let onSelect: ((WeekDayItem) -> Void)?

    /// - Parameters:
    ///   - days: sette giorni in ordine lunedì → domenica.
    ///   - onSelect: azione opzionale al tocco di un giorno.
    public init(days: [WeekDayItem], onSelect: ((WeekDayItem) -> Void)? = nil) {
        self.days = days
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(days) { day in
                dayView(day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayView(_ day: WeekDayItem) -> some View {
        let content = VStack(spacing: Theme.Spacing.s) {
            Text(day.initial)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(day.isToday ? Theme.textPrimary : Theme.textTertiary)

            ZStack {
                Circle()
                    .fill(fill(for: day))
                Circle()
                    .strokeBorder(stroke(for: day), lineWidth: 1.5)

                if day.state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(day.isToday ? Theme.onInk : Theme.accent.onFill)
                } else if let number = day.dayNumber {
                    Text("\(number)")
                        .font(.system(.footnote, weight: day.isToday ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(day.isToday ? Theme.onInk : Theme.textSecondary)
                }
            }
            .frame(width: 36, height: 36)
        }
        .frame(minHeight: Theme.Size.minTapTarget + 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.fullName))
        .accessibilityValue(Text(accessibilityValue(for: day)))

        if let onSelect {
            Button { onSelect(day) } label: { content }
                .buttonStyle(PressableButtonStyle())
        } else {
            content
        }
    }

    private func fill(for day: WeekDayItem) -> Color {
        if day.isToday { return Theme.ink }
        switch day.state {
        case .completed: return Theme.accent.fill
        case .planned: return Theme.surface
        case .rest: return .clear
        }
    }

    private func stroke(for day: WeekDayItem) -> Color {
        if day.isToday { return .clear }
        switch day.state {
        case .completed, .planned: return .clear
        case .rest: return Theme.separator
        }
    }

    private func accessibilityValue(for day: WeekDayItem) -> String {
        let stateText = switch day.state {
        case .completed: "allenamento completato"
        case .planned: "allenamento pianificato"
        case .rest: "riposo"
        }
        return day.isToday ? "oggi, \(stateText)" : stateText
    }
}
