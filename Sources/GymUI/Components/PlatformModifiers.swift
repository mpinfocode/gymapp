import SwiftUI

#if os(iOS)
import UIKit
#endif

// Unico punto in cui il design system tocca API solo-iOS legate all'input testuale.
// Tenendole qui, i rami `#if` restano due e banali invece di essere sparsi nei componenti.

extension View {

    /// Disattiva la capitalizzazione automatica (no-op fuori da iOS).
    public func noAutocapitalization() -> some View {
        #if os(iOS)
        return self.textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }

    /// Mostra il tastierino numerico, decimale o intero (no-op fuori da iOS).
    public func numericKeyboard(decimal: Bool) -> some View {
        #if os(iOS)
        return self.keyboardType(decimal ? .decimalPad : .numberPad)
        #else
        return self
        #endif
    }
}
