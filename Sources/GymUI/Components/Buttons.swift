import SwiftUI

// MARK: - Bottone primario

/// Varianti del bottone primario.
public enum PrimaryButtonVariant: Sendable {
    /// Capsula `ink` (quasi nera su chiaro, quasi bianca su scuro).
    case ink
    /// Capsula bianca piena: da usare sopra i fondi scuri immersivi.
    case light
    /// Capsula accento: azione "fatto / attivo".
    case accent
}

/// Bottone primario: capsula alta 56, larghezza piena.
public struct PrimaryButton: View {

    private let title: String
    private let systemImage: String?
    private let variant: PrimaryButtonVariant
    private let isEnabled: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var environmentEnabled

    /// - Parameters:
    ///   - title: testo del bottone.
    ///   - systemImage: SF Symbol opzionale a sinistra del testo.
    ///   - variant: stile di riempimento.
    ///   - isEnabled: disattiva il bottone mantenendone l'ingombro.
    ///   - action: azione eseguita al tocco.
    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: PrimaryButtonVariant = .ink,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.body, weight: .semibold))
                }
                Text(title)
                    .font(.system(.body, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.primaryButtonHeight)
            .background(fill, in: Capsule(style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled && environmentEnabled ? 1 : 0.45)
        .accessibilityLabel(Text(title))
    }

    private var fill: Color {
        switch variant {
        case .ink: Theme.ink
        case .light: Theme.mediaTile
        case .accent: Theme.accent.fill
        }
    }

    private var foreground: Color {
        switch variant {
        case .ink: Theme.onInk
        case .light: Theme.onPastel
        case .accent: Theme.accent.onFill
        }
    }
}

// MARK: - Bottone pillola secondario

/// Bottone secondario a pillola, da usare in coppia ("Modifica piano" / "Vedi storico").
public struct PillButton: View {

    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    /// - Parameters:
    ///   - title: testo del bottone.
    ///   - systemImage: SF Symbol opzionale.
    ///   - action: azione eseguita al tocco.
    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.subheadline, weight: .medium))
                }
                Text(title)
                    .font(.system(.subheadline, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.minTapTarget)
            .background(Theme.surface, in: Capsule(style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Azione circolare

/// Cerchio traslucido con label minuscola sotto: il tris di azioni della sessione
/// ("-15s · salta · +15s", "note · storico · sostituisci").
public struct CircleActionButton: View {

    private let title: String
    private let systemImage: String
    private let text: String?
    private let diameter: CGFloat
    private let foreground: Color
    private let action: () -> Void

    /// - Parameters:
    ///   - title: label minuscola sotto al cerchio (anche label VoiceOver).
    ///   - systemImage: SF Symbol dentro al cerchio.
    ///   - text: testo alternativo all'icona (es. "-15"); se presente ha la precedenza.
    ///   - diameter: diametro del cerchio (≥ 44).
    ///   - foreground: colore di icona e label.
    ///   - action: azione eseguita al tocco.
    public init(
        _ title: String,
        systemImage: String = "circle",
        text: String? = nil,
        diameter: CGFloat = 60,
        foreground: Color = Theme.textPrimary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.text = text
        self.diameter = max(diameter, Theme.Size.minTapTarget)
        self.foreground = foreground
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    if let text {
                        Text(text)
                            .font(.system(.subheadline, weight: .semibold))
                            .monospacedDigit()
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: diameter * 0.34, weight: .medium))
                    }
                }
                .frame(width: diameter, height: diameter)

                Text(title)
                    .font(.system(.caption, weight: .regular))
                    .textCase(.lowercase)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

// MARK: - "+" flottante

/// Bottone "+" circolare flottante.
public struct FloatingPlusButton: View {

    private let accessibilityTitle: String
    private let systemImage: String
    private let action: () -> Void

    /// - Parameters:
    ///   - accessibilityTitle: label VoiceOver (il bottone non ha testo visibile).
    ///   - systemImage: SF Symbol, default "plus".
    ///   - action: azione eseguita al tocco.
    public init(
        accessibilityTitle: String,
        systemImage: String = "plus",
        action: @escaping () -> Void
    ) {
        self.accessibilityTitle = accessibilityTitle
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.onInk)
                .frame(width: 56, height: 56)
                .background(Theme.ink, in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

// MARK: - Stile condiviso

/// Riduzione morbida alla pressione, condivisa da tutti i bottoni del design system.
public struct PressableButtonStyle: ButtonStyle {

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
