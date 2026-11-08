import SwiftUI

struct ExchangeRateSheet: View {
    let store: LedgerStore
    let code: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var rate: Double

    init(store: LedgerStore, code: String) {
        self.store = store
        self.code = code
        _rate = State(initialValue: store.exchangeRates[code] ?? 0)
    }

    var body: some View {
        Form {
            TextField(
                "1 \(code) in \(store.settings.currencyCode)", value: $rate,
                format: .number.precision(.fractionLength(0...6))
            )
            .focused($isFocused)
            Text("Rates are entered by hand and applied to every account in \(code).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .navigationTitle("\(code) exchange rate")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.setExchangeRate(code: code, rate: rate)
                    dismiss()
                }
                .disabled(rate <= 0)
            }
        }
        .onAppear { isFocused = true }
    }
}
