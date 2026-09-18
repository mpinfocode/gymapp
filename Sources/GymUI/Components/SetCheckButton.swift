import SwiftUI

/// Spunta di completamento serie: "scatta" con una spring corta e un feedback aptico.
public struct SetCheckButton: View {

    @Binding private var isCompleted: Bool
    private let size: CGFloat
    private let tint: AccentPalette
    private let accessibilityTitle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - isCompleted: stato della serie.
    ///   - size: lato del quadrato toccabile (≥ 44).
    ///   - tint: colore dello stato completato.
    ///   - accessibilityTitle: etichetta VoiceOver ("Serie 3").
    public init(
        isCompleted: Binding<Bool>,
        size: CGFloat = Theme.Size.minTapTarget,
        tint: AccentPalette = Theme.accent,
        accessibilityTitle: String = "Completa la serie"
    ) {
        self._isCompleted = isCompleted
        self.size = max(size, Theme.Size.minTapTarget)
        self.tint = tint
        self.accessibilityTitle = accessibilityTitle
    }

    public var body: some View {
        Button {
            if reduceMotion {
                isCompleted.toggle()
            } else {
                withAnimation(Theme.Motion.snappy) { isCompleted.toggle() }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(isCompleted ? tint.fill : Color.clear)
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(isCompleted ? .clear : Theme.separator, lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(isCompleted ? tint.onFill : Theme.textTertiary)
                    .scaleEffect(isCompleted ? 1 : 0.7)
                    .opacity(isCompleted ? 1 : 0.35)
            }
            .frame(width: size, height: size)
            .scaleEffect(isCompleted && !reduceMotion ? 1.06 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .haptic(.firm, trigger: isCompleted) { old, new in !old && new }
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(Text(isCompleted ? "completata" : "da fare"))
        .accessibilityAddTraits(isCompleted ? [.isButton, .isSelected] : .isButton)
    }
}
