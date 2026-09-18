import SwiftUI

/// Valori numerici accettati da `NumberCapsuleField`.
public protocol NumberCapsuleValue: Equatable, Sendable {
    /// Converte il testo digitato nel valore, o `nil` se non valido.
    static func parseFieldText(_ text: String) -> Self?
    /// Rappresentazione testuale mostrata nel campo.
    var fieldText: String { get }
    /// Se `true` il campo apre il tastierino decimale, altrimenti quello intero.
    static var prefersDecimalKeyboard: Bool { get }
}

extension Double: NumberCapsuleValue {

    public static func parseFieldText(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    public var fieldText: String {
        guard isFinite else { return "" }
        if self == rounded(), magnitude < 1_000_000 {
            return String(Int(self))
        }
        var text = String(format: "%.2f", self)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    public static var prefersDecimalKeyboard: Bool { true }
}

extension Int: NumberCapsuleValue {

    public static func parseFieldText(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    public var fieldText: String { String(self) }

    public static var prefersDecimalKeyboard: Bool { false }
}

/// Cella di input numerica a capsula per KG / REPS nella tabella serie.
///
/// Il valore è opzionale: vuoto significa "non inserito". Il campo mostra come
/// placeholder il valore della serie precedente, quando fornito.
public struct NumberCapsuleField<Value: NumberCapsuleValue>: View {

    @Binding private var value: Value?
    private let placeholder: String
    private let isCompleted: Bool
    private let accessibilityTitle: String
    private let externalFocus: FocusState<Bool>.Binding?

    @State private var text: String = ""
    @FocusState private var internalFocus: Bool

    /// - Parameters:
    ///   - value: valore numerico, `nil` se la cella è vuota.
    ///   - placeholder: testo grigio mostrato quando la cella è vuota (es. il "precedente").
    ///   - isCompleted: la serie è stata completata: la cella si tinge di accento.
    ///   - accessibilityTitle: etichetta VoiceOver ("Chilogrammi, serie 2").
    ///   - focus: focus gestito dal chiamante, per spostarsi da una cella all'altra.
    public init(
        value: Binding<Value?>,
        placeholder: String = "·",
        isCompleted: Bool = false,
        accessibilityTitle: String,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self._value = value
        self.placeholder = placeholder
        self.isCompleted = isCompleted
        self.accessibilityTitle = accessibilityTitle
        self.externalFocus = focus
    }

    private var isFocused: Bool {
        externalFocus?.wrappedValue ?? internalFocus
    }

    public var body: some View {
        focusableField
            .font(.cellNumber)
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
            .numericKeyboard(decimal: Value.prefersDecimalKeyboard)
            .submitLabel(.done)
            .frame(minWidth: 56)
            .frame(height: Theme.Size.minTapTarget)
            .background(background)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
            )
            .animation(Theme.Motion.smooth, value: isFocused)
            .animation(Theme.Motion.smooth, value: isCompleted)
            .onAppear { text = value?.fieldText ?? "" }
            .onChange(of: text) { _, newValue in
                let parsed = Value.parseFieldText(newValue)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                let expected = newValue?.fieldText ?? ""
                if !isFocused, expected != text { text = expected }
            }
            .accessibilityLabel(Text(accessibilityTitle))
            .accessibilityValue(Text(value?.fieldText ?? "vuoto"))
    }

    @ViewBuilder
    private var focusableField: some View {
        if let externalFocus {
            TextField(placeholder, text: $text).focused(externalFocus)
        } else {
            TextField(placeholder, text: $text).focused($internalFocus)
        }
    }

    private var background: some View {
        Capsule(style: .continuous)
            .fill(isCompleted ? Theme.accent.fill : Theme.surface)
    }

    /// Sopra un riempimento pastello il testo è sempre scuro: mai bianco su pastello.
    private var textColor: Color {
        isCompleted ? Theme.accent.onFill : Theme.textPrimary
    }

    private var borderColor: Color {
        isFocused ? Theme.textPrimary : .clear
    }
}
