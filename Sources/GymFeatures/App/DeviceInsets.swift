import SwiftUI

/// Misure dei bordi "non disponibili" dello schermo: barra di stato in alto,
/// home indicator in basso.
///
/// Nell'app reale queste misure NON servono: la shell è la radice della finestra e
/// il sistema le applica già come safe area (vedi ``AppShell``). Servono invece a
/// chi simula un iPhone dentro una finestra macOS (``GymPreview``) **senza** passare
/// alcuna safe area al contenuto: è il caso che riproduce il telefono vero, dove la
/// propagazione della safe area ai `NavigationStack` e alle `ScrollView` interne non
/// è affidabile.
public struct DeviceInsets: Equatable, Sendable {

    /// Altezza della barra di stato.
    public var top: CGFloat
    /// Altezza dell'home indicator (0 dove c'è il tasto Home).
    public var bottom: CGFloat

    public init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }
}

private struct DeviceInsetsOverrideKey: EnvironmentKey {
    static let defaultValue: DeviceInsets? = nil
}

extension EnvironmentValues {

    /// Misure dei bordi imposte dall'esterno: quando è valorizzato, la shell le usa
    /// **al posto** della safe area di sistema per costruire le proprie fasce.
    ///
    /// `nil` (l'app reale) = si usa la safe area della finestra.
    public var deviceInsetsOverride: DeviceInsets? {
        get { self[DeviceInsetsOverrideKey.self] }
        set { self[DeviceInsetsOverrideKey.self] = newValue }
    }
}
