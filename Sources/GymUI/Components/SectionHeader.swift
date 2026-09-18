import SwiftUI

/// Intestazione di sezione: titolo 22 semibold + "Vedi tutto" sottolineato a destra.
public struct SectionHeader: View {

    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - title: titolo della sezione.
    ///   - actionTitle: testo del link a destra (default "Vedi tutto" se `action` è presente).
    ///   - action: azione del link; se nil il link non compare.
    public init(
        _ title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: Theme.Spacing.m)

            if let action {
                Button(action: action) {
                    Text(actionTitle ?? "Vedi tutto")
                        .font(.system(.subheadline, weight: .medium))
                        .underline()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: Theme.Size.minTapTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}
