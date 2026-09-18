import SwiftUI

/// Radice dell'interfaccia dell'app.
///
/// Segnaposto della Fase 1: serve solo a dare al target iOS qualcosa da mostrare
/// e a validare la catena `App/GymApp.swift` → `GymFeatures`.
/// Verrà sostituita in Fase 2 dalla vera shell a tab (Oggi · Esercizi · Schede · Progressi).
///
/// Nota: qui non si importano volutamente `GymCore` / `GymUI` — in Fase 1 sono
/// in costruzione in parallelo e questa vista deve restare compilabile da sola.
/// Nessun `#Preview`: il plugin macro non è disponibile sul toolchain locale (SPEC §1.2).
public struct RootView: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.94, blue: 0.97),
                    Color(red: 0.98, green: 0.96, blue: 0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Text("GymApp")
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
