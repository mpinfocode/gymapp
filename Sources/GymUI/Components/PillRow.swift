import SwiftUI

/// Riga-pillola: icona + titolo (+ sottotitolo) + dettaglio a destra + chevron.
public struct PillRow: View {

    private let title: String
    private let subtitle: String?
    private let detail: String?
    private let systemImage: String?
    private let tint: Color
    private let showsChevron: Bool
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - title: titolo della riga.
    ///   - subtitle: seconda riga grigia opzionale.
    ///   - detail: valore allineato a destra, prima del chevron.
    ///   - systemImage: SF Symbol a sinistra.
    ///   - tint: colore dell'icona.
    ///   - showsChevron: mostra il chevron di navigazione.
    ///   - action: se nil la riga è solo informativa (non toccabile).
    public init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String? = nil,
        tint: Color = Theme.textSecondary,
        showsChevron: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.showsChevron = showsChevron
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(PressableButtonStyle())
                .accessibilityElement(children: .combine)
        } else {
            rowContent.accessibilityElement(children: .combine)
        }
    }

    private var rowContent: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            if let detail {
                Text(detail)
                    .font(.system(.subheadline, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(minHeight: Theme.Size.minTapTarget + 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}
