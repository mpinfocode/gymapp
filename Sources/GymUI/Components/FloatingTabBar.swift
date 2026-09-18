import SwiftUI

/// Voce della tab bar flottante.
public struct TabItem<ID: Hashable & Sendable>: Identifiable, Sendable {
    public let id: ID
    /// Testo sotto l'icona.
    public let title: String
    /// SF Symbol della tab a riposo.
    public let systemImage: String
    /// SF Symbol della tab selezionata (default: uguale a `systemImage`).
    public let selectedSystemImage: String

    public init(id: ID, title: String, systemImage: String, selectedSystemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.selectedSystemImage = selectedSystemImage ?? systemImage
    }
}

/// Tab bar flottante a capsula traslucida: la tab selezionata è evidenziata da una
/// pillola più scura che scorre con `matchedGeometryEffect`.
public struct FloatingTabBar<ID: Hashable & Sendable>: View {

    private let items: [TabItem<ID>]
    @Binding private var selection: ID

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - items: le tab, nell'ordine di visualizzazione.
    ///   - selection: id della tab attiva.
    public init(items: [TabItem<ID>], selection: Binding<ID>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Theme.Size.hairline)
        )
        .haptic(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func tabButton(_ item: TabItem<ID>) -> some View {
        let isSelected = item.id == selection
        Button {
            guard !isSelected else { return }
            if reduceMotion {
                selection = item.id
            } else {
                withAnimation(Theme.Motion.spring) { selection = item.id }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? item.selectedSystemImage : item.systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(item.title)
                    .font(.system(.caption2, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.onInk : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.ink)
                        .matchedGeometryEffect(id: "selectedTab", in: namespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
