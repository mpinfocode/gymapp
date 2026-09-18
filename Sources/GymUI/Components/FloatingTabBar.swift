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

/// Ingombro della ``FloatingTabBar``, per riservarle lo spazio corretto.
///
/// La shell disegna la barra sopra il contenuto: i contenuti scrollabili devono
/// terminare almeno `scrollBottomInset` punti più in alto della safe area.
public enum FloatingTabBarMetrics {

    /// Altezza del contenuto di una tab (icona + etichetta), target di tap incluso.
    public static let itemHeight: CGFloat = 52
    /// Padding della capsula attorno alle tab.
    public static let padding: CGFloat = 6
    /// Altezza totale della capsula.
    public static let height: CGFloat = itemHeight + padding * 2
    /// Margine tra la capsula e il fondo della safe area.
    public static let bottomMargin: CGFloat = Theme.Spacing.s
    /// Spazio verticale complessivamente occupato dalla barra (capsula + margine).
    public static let reservedHeight: CGFloat = height + bottomMargin
    /// Padding in fondo da dare alle ScrollView, perché l'ultima riga non finisca
    /// sotto la capsula.
    public static let scrollBottomInset: CGFloat = reservedHeight + Theme.Spacing.xl
}

/// Tab bar flottante a capsula: la tab selezionata è evidenziata da una pillola
/// `ink` che scorre con `matchedGeometryEffect`.
///
/// Lo sfondo è **pieno** (`surface`) con hairline `separator`, non un materiale
/// traslucido: su iPhone il materiale rendeva una capsula grigio scuro sfumata e
/// le tab non selezionate diventavano grigio su grigio. In più il backdrop blur di
/// un materiale si ricalcola a ogni fotogramma mentre il contenuto scorre dietro,
/// ed è uno dei costi GPU più alti di una schermata.
public struct FloatingTabBar<ID: Hashable & Sendable>: View {

    private let items: [TabItem<ID>]
    @Binding private var selection: ID
    private let onReselect: ((ID) -> Void)?

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - items: le tab, nell'ordine di visualizzazione.
    ///   - selection: id della tab attiva.
    ///   - onReselect: tocco su una tab **già** selezionata (la shell la usa per
    ///     tornare alla radice della sezione e scorrere in cima). Anche senza questa
    ///     chiusura il `set` del binding viene comunque invocato con lo stesso valore,
    ///     così chi passa un `Binding(get:set:)` può intercettare il ritocco. Con un
    ///     normale `@State` riassegnare lo stesso valore non cambia nulla: niente
    ///     animazione, niente feedback aptico, nessun ridisegno.
    public init(
        items: [TabItem<ID>],
        selection: Binding<ID>,
        onReselect: ((ID) -> Void)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.onReselect = onReselect
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(FloatingTabBarMetrics.padding)
        .background(Theme.surface, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Theme.Size.hairline)
        )
        .frame(height: FloatingTabBarMetrics.height)
        .haptic(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func tabButton(_ item: TabItem<ID>) -> some View {
        let isSelected = item.id == selection
        Button {
            guard !isSelected else {
                // Ritocco sulla tab attiva: la pillola non si muove, quindi niente
                // animazione. Si riassegna comunque lo stesso valore perché il `set`
                // del binding arrivi alla shell.
                selection = item.id
                onReselect?(item.id)
                return
            }
            if reduceMotion {
                selection = item.id
            } else {
                withAnimation(Theme.Motion.quick) { selection = item.id }
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
            .frame(height: FloatingTabBarMetrics.itemHeight)
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
