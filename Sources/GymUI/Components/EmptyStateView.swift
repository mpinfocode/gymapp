import SwiftUI

/// Stato vuoto: icona, titolo, messaggio e, sempre, un'azione.
public struct EmptyStateView: View {

    private let systemImage: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - systemImage: SF Symbol grande in alto.
    ///   - title: titolo breve.
    ///   - message: una o due righe di spiegazione.
    ///   - actionTitle: testo del bottone primario.
    ///   - action: azione del bottone; se nil il bottone non compare.
    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
                    .frame(maxWidth: 260)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .accessibilityElement(children: .contain)
    }
}
