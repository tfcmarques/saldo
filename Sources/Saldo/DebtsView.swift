import SwiftUI

/// What deleting a debt does, shown before it happens.
func debtDeletionMessage(_ debt: Debt, store: LedgerStore) -> String {
    let count = store.payments(for: debt).count
    if count == 0 { return "Nothing has been paid on this debt yet." }
    return
        "The \(count) \(count == 1 ? "payment stays" : "payments stay") in the ledger. This only removes the debt."
}

/// A debt's details and payments, opened from the Accounts page.
struct DebtDetailSheet: View {
    let store: LedgerStore
    let debtID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let debt = store.debts.first(where: { $0.id == debtID }) {
                DebtDetail(store: store, debt: debt) { isConfirmingDelete = true }
                    .confirmationDialog(
                        "Delete \(debt.name)?", isPresented: $isConfirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            store.deleteDebt(debt)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(debtDeletionMessage(debt, store: store))
                    }
            } else {
                ContentUnavailableView("This debt was deleted", systemImage: "creditcard")
            }
        }
        .frame(width: 600, height: 560)
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .buttonStyle(.pill(.secondary))
            }
        }
    }
}

struct DebtRow: View {
    let store: LedgerStore
    let debt: Debt

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(DS.Palette.textMuted)
                .help("Drag to reorder")
            IconBubble(systemName: debt.icon.rawValue, tint: debt.color.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.name).font(DS.Typeface.bodyStrong)
                DetailLine([debt.direction.rawValue, debt.note])
            }
            Spacer()
            Text(store.remaining(for: debt), format: .currency(code: store.currencyCode(for: debt)))
                .font(DS.Typeface.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(
                    store.remaining(for: debt) > 0.004 ? DS.Palette.textPrimary : DS.Palette.success)
        }
        .padding(.vertical, 4)
    }

}

struct DebtDetail: View {
    let store: LedgerStore
    let debt: Debt
    let delete: () -> Void
    @Environment(AppRouter.self) private var router
    @Environment(\.undoManager) private var undoManager

    private var code: String { store.currencyCode(for: debt) }
    private var remaining: Double { store.remaining(for: debt) }
    private var paid: Double { store.paid(for: debt) }
    private var payments: [LedgerEntry] { store.payments(for: debt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                progress
                paymentsSection
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            IconBubble(systemName: debt.icon.rawValue, tint: debt.color.color, size: 48)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(debt.name).font(DS.Typeface.title1)
                DetailLine([
                    debt.direction.rawValue, debt.note,
                    "Since \(store.formattedDate(debt.startedAt))",
                ])
                .font(DS.Typeface.small)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(remaining > 0.004 ? "Left" : "Paid off")
                    .formHint()
                Text(remaining, format: .currency(code: code))
                    .font(DS.Typeface.figure)
                    .monospacedDigit()
                    .foregroundStyle(remaining > 0.004 ? DS.Palette.textPrimary : DS.Palette.success)
            }
        }
    }


    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: min(paid, debt.principal), total: max(debt.principal, 0.01))
                .tint(remaining > 0.004 ? debt.color.color : .green)
            Text(
                "\(paid.formatted(.currency(code: code))) paid of \(debt.principal.formatted(.currency(code: code)))"
            )
            .font(DS.Typeface.caption)
            .foregroundStyle(DS.Palette.textSecondary)
            HStack(spacing: DS.Space.xs) {
                Button(debt.direction == .iOwe ? "Record payment" : "Record payment received") {
                    router.sheet = .payDebt(debt)
                }
                .buttonStyle(.pill(.primary))
                .disabled(store.openAccounts.isEmpty || remaining <= 0.004)
                .help("Record money paid on this debt from one of your accounts")
                Button("Edit", systemImage: "pencil") { router.sheet = .editDebt(debt) }
                    .buttonStyle(.pill(.secondary))
                    .help("Edit \(debt.name)")
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    .buttonStyle(.pill(.tertiary))
                    .help("Delete \(debt.name). Payments stay in the ledger.")
            }
            if store.openAccounts.isEmpty {
                Text(
                    store.accounts.isEmpty
                        ? "Add an account before recording a payment."
                        : "Reopen an account before recording a payment."
                )
                .formHint()
            } else {
                Text(paymentHint)
                    .formHint()
            }
        }
    }

    private var paymentHint: String {
        switch debt.direction {
        case .iOwe:
            "A payment is an expense from the account you choose, and it lowers what you still owe."
        case .owedToMe:
            "A payment you receive is income into the account you choose, and it lowers what is still owed to you."
        }
    }

    private var paymentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payments").font(DS.Typeface.title3)
            if payments.isEmpty {
                Text("No payments yet.")
                    .foregroundStyle(DS.Palette.textSecondary)
            } else {
                ForEach(payments) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(accountName(entry)).font(DS.Typeface.bodyStrong)
                            DetailLine([paymentNote(entry), store.formattedDate(entry.date)])
                        }
                        Spacer()
                        MoneyText(amount: applied(entry), currencyCode: code)
                        Button {
                            store.deleteEntry(entry, undoManager: undoManager)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.icon)
                        .help("Delete payment")
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func accountName(_ entry: LedgerEntry) -> String {
        store.accounts.first { $0.id == entry.accountID }?.name ?? "Account"
    }

    private func paymentNote(_ entry: LedgerEntry) -> String {
        entry.note == debt.name ? "" : entry.displayNote
    }

    private func applied(_ entry: LedgerEntry) -> Double {
        entry.debtAmount > 0 ? entry.debtAmount : entry.amount
    }
}

/// Adds a debt, or edits one when `debt` is given.
struct DebtSheet: View {
    let store: LedgerStore
    let debt: Debt?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var direction: DebtDirection
    @State private var note: String
    @State private var principal: Double
    @State private var isAmountValid = true
    @State private var currency: String
    @State private var icon: DebtIcon
    @State private var color: AccountColor
    @State private var startedAt: Date

    init(store: LedgerStore, debt: Debt? = nil) {
        self.store = store
        self.debt = debt
        _name = State(initialValue: debt?.name ?? "")
        _direction = State(initialValue: debt?.direction ?? .iOwe)
        _note = State(initialValue: debt?.note ?? "")
        _principal = State(initialValue: debt?.principal ?? 0)
        _currency = State(initialValue: debt?.currencyCode ?? "")
        _icon = State(initialValue: debt?.icon ?? .person)
        _color = State(initialValue: debt?.color ?? AccountColor(preset: "orange"))
        _startedAt = State(initialValue: debt?.startedAt ?? Date())
    }

    /// Once payments exist, flipping the direction would turn them inside out.
    private var hasPayments: Bool { debt.map { !store.payments(for: $0).isEmpty } ?? false }

    private var amountCurrency: String {
        currency.isEmpty ? store.settings.currencyCode : currency
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isAmountValid
            && principal > 0
    }

    var body: some View {
        Form {
            Section {
                TextField("Who", text: $name, prompt: Text("Mom"))
                    .focused($isNameFocused)
                if hasPayments, let debt {
                    LabeledContent("Direction", value: debt.direction.rawValue)
                } else {
                    Picker("Direction", selection: $direction) {
                        ForEach(DebtDirection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                CurrencyPicker(currency: $currency, store: store)
                AmountField(
                    "Original amount (\(amountCurrency))", value: $principal,
                    currencyCode: amountCurrency, isValid: $isAmountValid)
                if hasPayments {
                    Text("Payments already recorded stay applied against this amount.")
                        .formHint()
                }
                TextField("Description", text: $note, prompt: Text("Car loan"))
                DatePicker("Started", selection: $startedAt, displayedComponents: .date)
            }
            Section("Appearance") {
                Picker("Icon", selection: $icon) {
                    ForEach(DebtIcon.allCases) { icon in
                        Label(icon.title, systemImage: Symbol.outline(icon.rawValue)).tag(icon)
                    }
                }
                PaletteColorPicker(label: "Color", color: $color)
            }
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 440)
        .navigationTitle(debt == nil ? "New debt" : "Edit debt")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(debt == nil ? "Add" : "Save", action: save)
                    .disabled(!canSave)
                    .buttonStyle(.pill(.primary))
            }
        }
        .onAppear { isNameFocused = true }
    }

    private func save() {
        if let debt {
            store.updateDebt(
                debt, name: name, direction: direction, note: note, principal: principal,
                currencyCode: currency, icon: icon, color: color, startedAt: startedAt)
        } else {
            _ = store.addDebt(
                name: name, direction: direction, note: note, principal: principal,
                currencyCode: currency, icon: icon, color: color, startedAt: startedAt)
        }
        dismiss()
    }
}

struct PayDebtSheet: View {
    let store: LedgerStore
    let debt: Debt
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 0.0
    @State private var isAmountValid = true
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var note = ""

    private var code: String { store.currencyCode(for: debt) }
    private var remaining: Double { store.remaining(for: debt) }

    private var accountAmount: Double? {
        guard let accountID, amount > 0 else { return nil }
        return store.accountAmount(forDebtAmount: amount, debt: debt, accountID: accountID)
    }

    private var exceedsRemaining: Bool { amount > remaining + 0.000_001 }

    var body: some View {
        Form {
            LabeledContent("Still left") {
                MoneyText(amount: remaining, currencyCode: code)
            }
            Picker("Account", selection: $accountID) {
                Text("Choose an account").tag(UUID?.none)
                ForEach(store.accountsByUsage) { account in
                    Label(account.name, systemImage: Symbol.outline(account.icon.rawValue)).tag(Optional(account.id))
                }
            }
            AmountField(
                "Amount (\(code))", value: $amount, currencyCode: code, isValid: $isAmountValid)
            if exceedsRemaining {
                Text("That's more than the \(remaining.formatted(.currency(code: code))) still left.")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.warning)
            }
            if let accountID, let accountAmount,
                store.currencyCode(forAccountID: accountID) != code
            {
                let account = store.accounts.first { $0.id == accountID }
                Text(
                    "\(amount.formatted(.currency(code: code))) is \(accountAmount.formatted(.currency(code: store.currencyCode(forAccountID: accountID)))) in \(account?.name ?? "that account")."
                )
                .formHint()
            }
            TextField("Description", text: $note, prompt: Text(debt.name))
            DatePicker(
                "Date", selection: $date, in: ...Date(), displayedComponents: .date)
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 440)
        .navigationTitle(debt.direction == .iOwe ? "Pay \(debt.name)" : "Payment from \(debt.name)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(debt.direction == .iOwe ? "Pay" : "Receive") {
                    guard let accountID else { return }
                    store.addDebtPayment(
                        debt, amount: amount, date: date, accountID: accountID, note: note)
                    dismiss()
                }
                .disabled(
                    accountID == nil || !isAmountValid || amount <= 0 || exceedsRemaining)
                .buttonStyle(.pill(.primary))
            }
        }
        .onAppear { accountID = store.accountsByUsage.first?.id }
    }
}
