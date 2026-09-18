import SwiftUI
import GymUI

/// Corpo comune dei segnaposto di Fase 2.
///
/// Ogni schermata di `GymFeatures` esiste già con la sua firma pubblica definitiva
/// ma mostra solo il proprio titolo: chi la implementa sostituisce il `body` e basta,
/// senza toccare la shell né le altre feature.
struct PlaceholderScreen: View {

    let title: String
    let systemImage: String
    /// Una riga che dice cosa ci andrà. Sparisce con la prima implementazione.
    let message: String
    /// Parametri ricevuti dalla schermata, utili a verificare il passaggio dati.
    var parameters: String?

    var body: some View {
        ZStack {
            PageBackground()

            VStack(spacing: Theme.Spacing.s) {
                Spacer(minLength: 0)

                EmptyStateView(
                    systemImage: systemImage,
                    title: title,
                    message: message
                )

                if let parameters, !parameters.isEmpty {
                    Text(parameters)
                        .font(.captionText)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.page)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
