import GymUI

/// I quattro tab della shell.
public enum AppTab: String, Hashable, Sendable, CaseIterable, Identifiable {
    case today
    case exercises
    case program
    case progress

    public var id: String { rawValue }

    /// Etichetta italiana mostrata nella tab bar.
    public var title: String {
        switch self {
        case .today: "Oggi"
        case .exercises: "Esercizi"
        case .program: "Scheda"
        case .progress: "Progressi"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "house"
        case .exercises: "square.grid.2x2"
        case .program: "list.bullet.rectangle"
        case .progress: "chart.line.uptrend.xyaxis"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .today: "house.fill"
        case .exercises: "square.grid.2x2.fill"
        case .program: "list.bullet.rectangle.fill"
        case .progress: "chart.line.uptrend.xyaxis"
        }
    }

    /// Voci pronte per ``FloatingTabBar``, nell'ordine di visualizzazione.
    static var tabItems: [TabItem<AppTab>] {
        AppTab.allCases.map {
            TabItem(id: $0, title: $0.title, systemImage: $0.systemImage, selectedSystemImage: $0.selectedSystemImage)
        }
    }
}
