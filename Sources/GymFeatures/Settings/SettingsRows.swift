import SwiftUI
import GymUI

/// Gruppo di righe in stile lista iOS, con i token dell'app: una sola superficie
/// grigia, raggio 28, niente ombra né bordo.
struct SettingsGroup<Content: View>: View {

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// Linea sottile fra due righe dello stesso gruppo.
struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.Size.hairline)
            .padding(.leading, Theme.Spacing.l)
            .accessibilityHidden(true)
    }
}

/// Riga con etichetta a sinistra e contenuto libero a destra.
struct SettingsRow<Trailing: View>: View {

    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyText)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            trailing()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frame(minHeight: Theme.Size.minTapTarget + 8)
    }
}

/// Valore grigio allineato a destra in una riga informativa.
struct SettingsValue: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.trailing)
    }
}

extension SettingsRow where Trailing == SettingsValue {

    /// Riga informativa: etichetta a sinistra, valore grigio a destra.
    init(title: String, value: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { SettingsValue(text: value) }
    }
}

/// Riga che è un'azione: testo colorato, tutta la riga tocca.
struct SettingsActionRow: View {

    let title: String
    var subtitle: String?
    var tint: Color = Theme.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodyEmphasis)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .frame(minHeight: Theme.Size.minTapTarget + 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Stepper compatto a passi fissi: due cerchi e il valore in mezzo.
struct SettingsStepper: View {

    let value: String
    let canDecrease: Bool
    let canIncrease: Bool
    let decreaseLabel: String
    let increaseLabel: String
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            button("minus", label: decreaseLabel, enabled: canDecrease, action: onDecrease)

            Text(value)
                .font(.cellNumber)
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 48)

            button("plus", label: increaseLabel, enabled: canIncrease, action: onIncrease)
        }
        .accessibilityElement(children: .contain)
    }

    private func button(
        _ systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Theme.surfaceElevated, in: Circle())
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
    }
}
