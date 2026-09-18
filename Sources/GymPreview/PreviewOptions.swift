#if os(macOS)
import CoreGraphics
import Foundation

/// Un formato di iPhone simulato dalla finestra.
///
/// Le safe area sono i valori reali di iOS 17 in punti: la barra di stato del
/// dispositivo (20pt sui modelli senza notch, 59/62pt su quelli con Dynamic
/// Island) e l'home indicator (34pt, assente dove c'è il tasto Home).
struct PreviewDevice: Sendable, Equatable {

    /// Chiave usata da `--dispositivo=`.
    let key: String
    /// Nome mostrato nel menu.
    let name: String
    /// Dimensione dello schermo in punti.
    let size: CGSize
    /// Inset superiore della safe area (barra di stato).
    let topInset: CGFloat
    /// Inset inferiore della safe area (home indicator); 0 dove c'è il tasto Home.
    let bottomInset: CGFloat
    /// Raggio degli angoli dello schermo.
    let cornerRadius: CGFloat

    static let se = PreviewDevice(
        key: "se",
        name: "iPhone SE  375 × 667",
        size: CGSize(width: 375, height: 667),
        topInset: 20,
        bottomInset: 0,
        cornerRadius: 4
    )

    static let iPhone17 = PreviewDevice(
        key: "17",
        name: "iPhone 17  393 × 852",
        size: CGSize(width: 393, height: 852),
        topInset: 59,
        bottomInset: 34,
        cornerRadius: 47
    )

    static let iPhone17ProMax = PreviewDevice(
        key: "max",
        name: "iPhone 17 Pro Max  440 × 956",
        size: CGSize(width: 440, height: 956),
        topInset: 62,
        bottomInset: 34,
        cornerRadius: 55
    )

    static let all: [PreviewDevice] = [.se, .iPhone17, .iPhone17ProMax]

    static func named(_ key: String) -> PreviewDevice? {
        all.first { $0.key == key.lowercased() }
    }
}

/// Lo scenario di dati caricato nell'ambiente.
enum PreviewScenario: String, Sendable, CaseIterable {

    /// Scheda attiva, rilevazioni corporee, preferiti.
    case sample
    /// Primo avvio: nessun dato.
    case empty

    var menuTitle: String {
        switch self {
        case .sample: "Dati di esempio"
        case .empty: "Primo avvio (vuoto)"
        }
    }
}

/// Opzioni passate da riga di comando.
///
///     swift run GymPreview --vuoto --scuro --dispositivo=max
struct PreviewOptions: Sendable {

    var device: PreviewDevice = .iPhone17
    var scenario: PreviewScenario = .sample
    var dark = false

    /// Se valorizzato: niente finestra, si scrive un PNG della schermata e si esce
    /// (verifica della cornice senza permessi di registrazione dello schermo).
    var pngPath: String?

    /// Argomenti non riconosciuti, riportati sullo standard output.
    var unknown: [String] = []

    static func parse(_ arguments: [String]) -> PreviewOptions {
        var options = PreviewOptions()
        for argument in arguments {
            switch argument {
            case "--vuoto":
                options.scenario = .empty
            case "--scuro":
                options.dark = true
            default:
                if argument.hasPrefix("--dispositivo="),
                   let device = PreviewDevice.named(String(argument.dropFirst("--dispositivo=".count))) {
                    options.device = device
                } else if argument.hasPrefix("--png=") {
                    options.pngPath = String(argument.dropFirst("--png=".count))
                } else {
                    options.unknown.append(argument)
                }
            }
        }
        return options
    }

    static let usage = """
    Uso: swift run GymPreview [--vuoto] [--scuro] [--dispositivo=se|17|max]
         swift run GymPreview --png=<percorso>   # solo un PNG, senza aprire la finestra
    """
}
#endif
