import SwiftUI
import GymFeatures

/// Entry point del target iOS.
///
/// Tutta la logica e l'interfaccia vivono nel package locale `GymKit`
/// (GymCore / GymUI / GymFeatures): questo file resta volutamente minimale
/// così che l'unica parte non verificabile in locale (il target Xcode) sia banale.
@main
struct GymApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
