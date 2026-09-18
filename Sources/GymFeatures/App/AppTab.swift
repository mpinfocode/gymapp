import GymUI

/// I quattro tab della shell, nell'ordine in cui compaiono:
/// **Home · Scheda · Esercizi · Misure** (SPEC §0).
///
/// `Home` è la schermata da palestra e la tab iniziale all'avvio.
public enum AppTab: String, Hashable, Sendable, CaseIterable, Identifiable {
    case home
    case program
    case exercises
    case measures

    public var id: String { rawValue }

    /// Etichetta italiana mostrata nella tab bar.
    public var title: String {
        switch self {
        case .home: "Home"
        case .program: "Scheda"
        case .exercises: "Esercizi"
        case .measures: "Misure"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .program: "list.bullet.rectangle"
        case .exercises: "square.grid.2x2"
        case .measures: "ruler"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .program: "list.bullet.rectangle.fill"
        case .exercises: "square.grid.2x2.fill"
        case .measures: "ruler.fill"
        }
    }

    /// Voci pronte per ``FloatingTabBar``, nell'ordine di visualizzazione.
    static var tabItems: [TabItem<AppTab>] {
        AppTab.allCases.map {
            TabItem(id: $0, title: $0.title, systemImage: $0.systemImage, selectedSystemImage: $0.selectedSystemImage)
        }
    }
}
