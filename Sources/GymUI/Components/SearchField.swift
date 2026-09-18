import SwiftUI

/// Campo di ricerca a capsula con lente e bottone "cancella".
public struct SearchField: View {

    private let placeholder: String
    @Binding private var text: String
    private let onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    /// - Parameters:
    ///   - placeholder: testo guida.
    ///   - text: testo cercato.
    ///   - onSubmit: chiamata alla conferma da tastiera.
    public init(
        placeholder: String = "Cerca",
        text: Binding<String>,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            TextField(placeholder, text: $text)
                .font(.bodyText)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
                .autocorrectionDisabled()
                .noAutocapitalization()

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.body, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Cancella la ricerca"))
                .transition(.opacity)
            }
        }
        .padding(.leading, Theme.Spacing.l)
        .padding(.trailing, text.isEmpty ? Theme.Spacing.l : Theme.Spacing.xs)
        .frame(height: Theme.Size.primaryButtonHeight - 8)
        .background(Theme.surface, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isFocused ? Theme.textPrimary : .clear, lineWidth: 1.5)
        )
        .animation(Theme.Motion.smooth, value: text.isEmpty)
        .animation(Theme.Motion.smooth, value: isFocused)
    }
}
