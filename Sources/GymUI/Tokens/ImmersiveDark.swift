import SwiftUI

/// Forza `colorScheme = .dark` sul sottoalbero quando attivo, altrimenti propaga quello ereditato.
private struct ImmersiveDarkModifier: ViewModifier {
    @Environment(\.colorScheme) private var inherited
    let isActive: Bool

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, isActive ? .dark : inherited)
    }
}

extension View {

    /// Forza lo stile scuro "immersivo" su un sottoalbero, a prescindere dal tema di sistema.
    ///
    /// Usato dalla sessione attiva e dal riepilogo (vedi DESIGN.md → "Sistema").
    /// Tutti i token di `Theme` sono adattivi e seguono questo override.
    public func immersiveDark() -> some View {
        environment(\.colorScheme, .dark)
    }

    /// Applica lo stile scuro immersivo solo quando `isActive` è vero.
    public func immersiveDark(_ isActive: Bool) -> some View {
        modifier(ImmersiveDarkModifier(isActive: isActive))
    }
}
