import SwiftUI
import GymUI

#if os(iOS)
import UIKit
#endif

// Unico punto di GymFeatures che tocca la barra sopra la tastiera.
// `ToolbarItemGroup(placement: .keyboard)` esiste solo su iOS: fuori da iOS il
// modificatore è un no-op, così la stessa schermata compila anche su macOS.

extension View {

    /// Aggiunge la barra "Fatto" sopra il tastierino numerico.
    ///
    /// Variante consigliata: si passa l'azione che chiude il campo, di norma
    /// azzerando il `@FocusState` della schermata.
    ///
    ///     .keyboardDoneToolbar { focusedField = nil }
    @ViewBuilder
    public func keyboardDoneToolbar(title: String = "Fatto", done: @escaping () -> Void) -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(title, action: done)
                    .font(.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
            }
        }
        #else
        self
        #endif
    }

    /// Variante senza argomenti: chiude la tastiera dimettendo il first responder.
    ///
    /// Comoda quando la schermata non ha un `@FocusState`; se ce l'ha, preferire
    /// ``keyboardDoneToolbar(title:done:)`` perché lo stato resta coerente.
    @ViewBuilder
    public func keyboardDoneToolbar(title: String = "Fatto") -> some View {
        #if os(iOS)
        self.keyboardDoneToolbar(title: title) { KeyboardDismisser.dismiss() }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Chiusura della tastiera senza `@FocusState`, isolata qui per tenere il ramo
/// solo-iOS in un punto unico e banale.
@MainActor
enum KeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
#endif
