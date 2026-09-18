import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Tipi di feedback aptico usati dall'app, indipendenti dalla piattaforma.
public enum Haptic: Equatable, Hashable, Sendable {
    /// Cambio di selezione (chip, segmented control).
    case selection
    /// Tocco leggero (incremento, apertura).
    case light
    /// Tocco deciso (serie completata).
    case firm
    /// Esito positivo (sessione salvata, PR).
    case success
    /// Attenzione (limite raggiunto).
    case warning
    /// Errore.
    case error

    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .light: .impact(weight: .light, intensity: 0.6)
        case .firm: .impact(weight: .medium, intensity: 1.0)
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }
}

extension View {

    /// Emette il feedback aptico quando `trigger` cambia valore.
    ///
    /// Usa `sensoryFeedback` (iOS 17 / macOS 14): su macOS è di fatto un no-op.
    public func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        sensoryFeedback(haptic.sensoryFeedback, trigger: trigger)
    }

    /// Emette il feedback solo quando `condition` è soddisfatta al cambio di `trigger`.
    public func haptic<T: Equatable>(
        _ haptic: Haptic,
        trigger: T,
        condition: @escaping (T, T) -> Bool
    ) -> some View {
        sensoryFeedback(trigger: trigger) { old, new in
            condition(old, new) ? haptic.sensoryFeedback : nil
        }
    }
}

/// Helper imperativo per i contesti senza view (es. callback di un timer).
///
/// Su macOS non fa nulla.
@MainActor
public enum Haptics {

    /// Abilitazione globale: la si allinea a `UserSettings.hapticsEnabled`.
    public static var isEnabled: Bool = true

    /// Riproduce il feedback indicato, se abilitato.
    public static func play(_ haptic: Haptic) {
        guard isEnabled else { return }
        #if os(iOS)
        switch haptic {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .firm:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}
