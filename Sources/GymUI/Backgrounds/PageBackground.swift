import SwiftUI

/// Sfondo di pagina: colore piatto, bianco puro in chiaro e nero puro in scuro.
/// Niente gradiente, niente tinte: il rumore lo fa il contenuto, non lo sfondo.
public struct PageBackground: View {

    public init() {}

    public var body: some View {
        Theme.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {

    /// Applica lo sfondo di pagina standard dietro il contenuto.
    public func pageBackground() -> some View {
        background(PageBackground())
    }
}
