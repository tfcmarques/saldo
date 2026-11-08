import SwiftUI

/// A money field that accepts arithmetic. A finished calculation shows its result
/// at the trailing edge of the same row.
struct AmountField: View {
    let title: String
    @Binding var value: Double
    var currencyCode: String
    var isValid: Binding<Bool>
    var fractionDigits: Int = 2
    var focusesOnAppear = false

    @State private var text: String
    @State private var isApplyingExternalValue = false
    @FocusState private var isFocused: Bool

    init(
        _ title: String, value: Binding<Double>, currencyCode: String, isValid: Binding<Bool>,
        fractionDigits: Int = 2, focusesOnAppear: Bool = false
    ) {
        self.title = title
        _value = value
        self.currencyCode = currencyCode
        self.isValid = isValid
        self.fractionDigits = fractionDigits
        self.focusesOnAppear = focusesOnAppear
        let initial = value.wrappedValue
        _text = State(
            initialValue: initial == 0
                ? ""
                : AmountExpression.formattedNumber(initial, fractionDigits: fractionDigits))
    }

    var body: some View {
        TextField(title, text: $text, prompt: Text("0"))
            .monospacedDigit()
            .focused($isFocused)
            .help("You can type a calculation, like 12.50 + 3 or 100 - 10%.")
            .safeAreaInset(edge: .trailing, spacing: resultText == nil ? 0 : 10) {
                if let resultText {
                    Text("= \(resultText)")
                        .font(DS.Typeface.small.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize()
                        .accessibilityLabel("Result \(resultText)")
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                syncFromText()
                if focusesOnAppear { isFocused = true }
            }
            .onChange(of: text) { syncFromText() }
            .onChange(of: isFocused) { finishPlainNumber() }
            .onChange(of: value) { applyExternalValue() }
    }

    /// Shown only once the expression has a result, so the row stays a normal field until then.
    private var resultText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AmountExpression.isCalculation(trimmed),
            case .value(let raw) = AmountExpression.evaluate(trimmed)
        else { return nil }
        return formattedAmount(raw)
    }

    private func syncFromText() {
        if isApplyingExternalValue {
            isApplyingExternalValue = false
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isValid.wrappedValue = true
            if value != 0 { value = 0 }
            return
        }
        switch AmountExpression.evaluate(trimmed) {
        case .value(let raw):
            let rounded = AmountExpression.rounded(raw, fractionDigits: fractionDigits)
            isValid.wrappedValue = true
            if value != rounded { value = rounded }
        case .incomplete, .invalid:
            isValid.wrappedValue = false
        }
    }

    /// Tidies a plain number when editing ends. Calculations stay put so the result remains visible.
    private func finishPlainNumber() {
        guard !isFocused else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !AmountExpression.isCalculation(trimmed),
            case .value(let raw) = AmountExpression.evaluate(trimmed)
        else { return }
        let rendered = display(
            AmountExpression.rounded(raw, fractionDigits: fractionDigits))
        if text != rendered { text = rendered }
    }

    private func applyExternalValue() {
        guard !isFocused else { return }
        let rendered = display(value)
        guard rendered != text else { return }
        isApplyingExternalValue = true
        text = rendered
        isValid.wrappedValue = true
    }

    private func display(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return AmountExpression.formattedNumber(value, fractionDigits: fractionDigits)
    }

    private func formattedAmount(_ raw: Double) -> String {
        let rounded = AmountExpression.rounded(raw, fractionDigits: fractionDigits)
        guard currencyCode.count == 3 else {
            return AmountExpression.formattedNumber(rounded, fractionDigits: fractionDigits)
        }
        return rounded.formatted(
            .currency(code: currencyCode).precision(.fractionLength(fractionDigits)))
    }
}
