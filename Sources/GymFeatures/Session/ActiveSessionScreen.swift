import SwiftUI
import GymUI

/// Sessione attiva, presentata a schermo intero da `RootView` quando
/// `store.activeSession != nil` (SPEC §5.4). Tema **scuro immersivo** sempre,
/// a prescindere dal tema di sistema: usare `.immersiveDark()`.
///
/// `onMinimize` chiude la cover **senza** terminare la sessione: la shell mostra
/// allora la barra "Riprendi allenamento" sopra la tab bar. Terminare la sessione
/// è un'altra cosa e si fa con `store.finishSession()` / `store.discardSession()`.
///
/// Segnaposto di Fase 2: sostituire il `body`, non la firma.
public struct ActiveSessionScreen: View {

    private let onMinimize: () -> Void

    /// - Parameter onMinimize: chiude la cover lasciando la sessione in corso.
    public init(onMinimize: @escaping () -> Void) {
        self.onMinimize = onMinimize
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            PlaceholderScreen(
                title: "Sessione",
                systemImage: "figure.run",
                message: "Timer, tabella serie, recupero e note."
            )

            Button(action: onMinimize) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)
            .accessibilityLabel(Text("Riduci a icona"))
        }
        .immersiveDark()
    }
}
