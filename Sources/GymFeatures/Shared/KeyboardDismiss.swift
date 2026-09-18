import SwiftUI
import GymUI

// Regola dell'utente: "quando si apre la tastiera devo poter fare swipe in giù per
// chiuderla, sempre". Non deve mai esistere un campo con la tastiera aperta e
// nessuna via d'uscita.
//
// Tre vie, sempre presenti insieme:
// 1. swipe verso il basso su un contenitore scrollabile → `keyboardDismissable()`;
// 2. tocco fuori dal campo → `keyboardDismissOnTap()`;
// 3. barra "Fatto" sopra il tastierino numerico → `keyboardDoneToolbar()`.

extension View {

    /// Lo swipe verso il basso su questo contenitore scrollabile chiude la tastiera.
    ///
    /// Va su **ogni** `ScrollView`, `List` o `Form` dell'app e delle sheet. Il
    /// modificatore è cross-platform (iOS 16+, macOS 13+): niente rami `#if`.
    func keyboardDismissable() -> some View {
        scrollDismissesKeyboard(.interactively)
    }

    /// Un tocco qualsiasi dentro questa vista chiude la tastiera.
    ///
    /// È un `simultaneousGesture`: non ruba il tocco a bottoni e righe, che
    /// continuano a funzionare. Si mette sulle schermate che hanno campi di testo,
    /// non ovunque: altrove sarebbe un gesto inutile su ogni tocco.
    func keyboardDismissOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded { KeyboardDismisser.dismiss() }
        )
    }
}
