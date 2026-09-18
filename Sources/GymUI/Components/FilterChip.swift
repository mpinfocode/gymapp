import SwiftUI

/// Chip di filtro selezionabile, con conteggio opzionale.
public struct FilterChip: View {

    private let title: String
    private let systemImage: String?
    private let count: Int?
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: testo del filtro.
    ///   - systemImage: SF Symbol opzionale.
    ///   - count: conteggio dei risultati, mostrato a destra.
    ///   - isSelected: stato selezionato.
    ///   - action: toggle del filtro.
    public init(
        _ title: String,
        systemImage: String? = nil,
        count: Int? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.footnote, weight: .medium))
                }
                Text(title)
                    .font(.system(.subheadline, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.system(.caption, weight: .semibold))
                        .monospacedDigit()
                        .opacity(0.65)
                }
            }
            .foregroundStyle(isSelected ? Theme.accent.onFill : Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: Theme.Size.minTapTarget)
            .background(isSelected ? Theme.accent.fill : Theme.surface, in: Capsule(style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .animation(Theme.Motion.snappy, value: isSelected)
        .haptic(.selection, trigger: isSelected)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(count.map { "\($0) risultati" } ?? ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
