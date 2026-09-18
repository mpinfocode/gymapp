import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Unico file, insieme a `Theme.swift`, in cui è lecito scrivere valori di colore
// letterali. Tutto il resto del design system e delle feature usa i token semantici.

extension Color {

    /// Colore adattivo light/dark risolto dal sistema (niente Asset catalog nel package).
    ///
    /// Su iOS usa un `UIColor` con dynamic provider, su macOS un `NSColor` con
    /// dynamic provider: entrambi rispettano l'override di `\.colorScheme`
    /// applicato da SwiftUI a un sottoalbero (vedi `View.immersiveDark()`).
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        let lightColor = UIColor(light)
        let darkColor = UIColor(dark)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        }))
        #elseif canImport(AppKit)
        let lightColor = NSColor(light)
        let darkColor = NSColor(dark)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }))
        #else
        return light
        #endif
    }

    /// Inizializza un colore da un intero esadecimale RGB (0xRRGGBB).
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
