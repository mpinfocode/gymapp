import SwiftUI

/// Segmented control a capsula nero/bianco con pillola scorrevole dietro il segmento attivo.
public struct CapsuleSegmentedControl<Value: Hashable>: View {

    private let values: [Value]
    private let titleForValue: (Value) -> String
    @Binding private var selection: Value

    @Namespace private var namespace

    /// - Parameters:
    ///   - values: i segmenti, nell'ordine di visualizzazione.
    ///   - selection: valore selezionato.
    ///   - title: titolo visibile per ciascun valore.
    public init(
        values: [Value],
        selection: Binding<Value>,
        title: @escaping (Value) -> String
    ) {
        self.values = values
        self._selection = selection
        self.titleForValue = title
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                let isSelected = value == selection
                Button {
                    withAnimation(Theme.Motion.quick) { selection = value }
                } label: {
                    Text(titleForValue(value))
                        .font(.system(.subheadline, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Theme.onInk : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Size.minTapTarget - 6)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(Theme.ink)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule(style: .continuous))
        .haptic(.selection, trigger: selection)
    }
}

extension CapsuleSegmentedControl where Value: RawRepresentable, Value.RawValue == String {

    /// Variante per enum con `rawValue` testuale.
    public init(values: [Value], selection: Binding<Value>) {
        self.init(values: values, selection: selection, title: \.rawValue)
    }
}
