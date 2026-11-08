import SwiftUI

struct TransferSheet: View {
    let store: LedgerStore
    let entry: LedgerEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var amount = 0.0
    @State private var received = 0.0
    @State private var receivedWasEdited = false
    @State private var date = Date()
    @State private var note = ""

    init(store: LedgerStore, entry: LedgerEntry? = nil) {
        self.store = store
        self.entry = entry
        if let entry, let legs = store.transferLegs(of: entry) {
            _fromID = State(initialValue: legs.source.accountID)
            _toID = State(initialValue: legs.destination.accountID)
            _amount = State(initialValue: legs.source.amount)
            _received = State(initialValue: legs.destination.amount)
            _receivedWasEdited = State(initialValue: true)
            _date = State(initialValue: legs.source.date)
            _note = State(initialValue: legs.source.note)
        } else {
            _fromID = State(initialValue: store.accounts.first?.id)
            _toID = State(initialValue: store.accounts.dropFirst().first?.id)
        }
    }

    private var fromCurrency: String { fromID.map(store.currencyCode(forAccountID:)) ?? "" }
    private var toCurrency: String { toID.map(store.currencyCode(forAccountID:)) ?? "" }
    private var needsConversion: Bool { fromCurrency != toCurrency }

    private var receivedBinding: Binding<Double> {
        Binding(
            get: { received },
            set: {
                received = $0
                receivedWasEdited = true
            })
    }

    private var isValid: Bool {
        guard let fromID, let toID, fromID != toID, amount > 0 else { return false }
        return !needsConversion || received > 0
    }

    var body: some View {
        Form {
            Picker("From", selection: $fromID) {
                ForEach(store.accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            Picker("To", selection: $toID) {
                ForEach(store.accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            TextField(
                "Amount (\(fromCurrency))", value: $amount,
                format: .number.precision(.fractionLength(2)))
            if needsConversion {
                TextField(
                    "Amount received (\(toCurrency))", value: receivedBinding,
                    format: .number.precision(.fractionLength(2)))
            }
            TextField("Description", text: $note)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            if fromID == toID {
                Text("Choose two different accounts.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .navigationTitle(entry == nil ? "New transfer" : "Edit transfer")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(entry == nil ? "Transfer" : "Save") { save() }
                    .disabled(!isValid)
            }
        }
        .onChange(of: amount) { refreshReceived() }
        .onChange(of: fromID) { refreshReceived() }
        .onChange(of: toID) { refreshReceived() }
    }

    private func refreshReceived() {
        guard !receivedWasEdited, let fromID, let toID else { return }
        received = store.convertedTransferAmount(amount, from: fromID, to: toID)
    }

    private func save() {
        guard let fromID, let toID else { return }
        let receivedAmount = needsConversion ? received : amount
        if let entry {
            store.updateTransfer(
                entry, from: fromID, to: toID, amount: amount, receivedAmount: receivedAmount,
                date: date, note: note)
        } else {
            store.addTransfer(
                from: fromID, to: toID, amount: amount, receivedAmount: receivedAmount, date: date,
                note: note)
        }
        dismiss()
    }
}
