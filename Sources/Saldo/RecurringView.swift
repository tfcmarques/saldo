import SwiftUI

struct RecurringView: View {
    let store: LedgerStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if store.recurringRules.isEmpty {
                ContentUnavailableView(
                    "No recurring entries",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text(
                        "Salary, rent, subscriptions or a monthly transfer to savings are added automatically."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.recurringRules) { rule in
                        RecurringRow(store: store, rule: rule)
                    }
                }
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add recurring entry", systemImage: "plus") {
                    router.sheet = .newRecurring
                }
                .disabled(store.accounts.isEmpty)
            }
        }
    }
}

private struct RecurringRow: View {
    let store: LedgerStore
    let rule: RecurringRule
    @Environment(AppRouter.self) private var router

    private var accountName: String {
        store.accounts.first { $0.id == rule.accountID }?.name ?? "Deleted account"
    }

    private var title: String {
        if !rule.note.isEmpty { return rule.note }
        return rule.kind == .transfer ? "Transfer" : rule.category
    }

    private var subtitle: String {
        var parts = [rule.frequency.rawValue]
        if rule.kind == .transfer {
            let destination =
                store.accounts.first { $0.id == rule.toAccountID }?.name ?? "Deleted account"
            parts.append("\(accountName) \u{2192} \(destination)")
        } else {
            parts.append(accountName)
        }
        if !rule.isActive {
            parts.append("Paused")
        } else if let next = store.nextOccurrence(of: rule) {
            parts.append("Next \(store.formattedDate(next))")
        } else {
            parts.append("Finished")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var symbol: String {
        switch rule.kind {
        case .expense: "arrow.up.right.circle.fill"
        case .income: "arrow.down.left.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        }
    }

    private var tint: Color {
        switch rule.kind {
        case .expense: .red
        case .income: .green
        case .transfer: .teal
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(rule.isActive ? tint : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(
                rule.amount,
                format: .currency(code: store.currencyCode(forAccountID: rule.accountID))
            )
            .fontWeight(.semibold)
            Toggle(
                "Active",
                isOn: Binding(
                    get: { rule.isActive },
                    set: { active in
                        var updated = rule
                        updated.isActive = active
                        store.saveRecurringRule(updated)
                    })
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            Button {
                router.sheet = .editRecurring(rule)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { router.sheet = .editRecurring(rule) }
            Button("Delete rule", systemImage: "trash", role: .destructive) {
                store.deleteRecurringRule(rule)
            }
        }
    }
}

struct RecurringSheet: View {
    let store: LedgerStore
    let rule: RecurringRule?
    @Environment(\.dismiss) private var dismiss
    @State private var kind: RecurringKind
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var category: String
    @State private var note: String
    @State private var amount: Double
    @State private var frequency: RecurrenceFrequency
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var isAddingCategory = false

    init(store: LedgerStore, rule: RecurringRule?) {
        self.store = store
        self.rule = rule
        _kind = State(initialValue: rule?.kind ?? .expense)
        _accountID = State(initialValue: rule?.accountID ?? store.accounts.first?.id)
        _toAccountID = State(
            initialValue: rule?.toAccountID ?? store.accounts.dropFirst().first?.id)
        _category = State(initialValue: rule?.category ?? store.categories.first?.name ?? "")
        _note = State(initialValue: rule?.note ?? "")
        _amount = State(initialValue: rule?.amount ?? 0)
        _frequency = State(initialValue: rule?.frequency ?? .monthly)
        _startDate = State(initialValue: rule?.startDate ?? Date())
        _hasEndDate = State(initialValue: rule?.endDate != nil)
        _endDate = State(
            initialValue: rule?.endDate
                ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
    }

    private var scheduleLocked: Bool { (rule?.generatedCount ?? 0) > 0 }

    private var amountCurrency: String {
        accountID.map(store.currencyCode(forAccountID:)) ?? store.settings.currencyCode
    }

    private var isValid: Bool {
        guard accountID != nil, amount > 0 else { return false }
        if kind == .transfer { return toAccountID != nil && toAccountID != accountID }
        return !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Picker("Type", selection: $kind) {
                ForEach(RecurringKind.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker(kind == .transfer ? "From" : "Account", selection: $accountID) {
                ForEach(store.accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            if kind == .transfer {
                Picker("To", selection: $toAccountID) {
                    ForEach(store.accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
            } else {
                Picker("Category", selection: $category) {
                    Text("Choose a category").tag("")
                    ForEach(store.categories) { storedCategory in
                        Label(storedCategory.name, systemImage: storedCategory.icon.rawValue)
                            .tag(storedCategory.name)
                    }
                }
                Button("Add category", systemImage: "plus") { isAddingCategory = true }
            }
            TextField("Description", text: $note)
            TextField(
                "Amount (\(amountCurrency))", value: $amount,
                format: .number.precision(.fractionLength(2)))

            if scheduleLocked {
                LabeledContent("Repeats", value: frequency.rawValue)
                LabeledContent("Started", value: store.formattedDate(startDate))
                Text("The schedule can't change once entries exist. Delete the rule to start over.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Repeats", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases) { Text($0.rawValue).tag($0) }
                }
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                Text("Occurrences from the start date up to today are added when you save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Ends", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .navigationTitle(rule == nil ? "New recurring entry" : "Edit recurring entry")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(rule == nil ? "Add" : "Save") { save() }
                    .disabled(!isValid)
            }
        }
        .sheet(isPresented: $isAddingCategory) {
            NavigationStack {
                AddCategorySheet(store: store)
            }
        }
    }

    private func save() {
        guard let accountID else { return }
        var updated =
            rule
            ?? RecurringRule(
                kind: kind, category: category, note: note, amount: amount, accountID: accountID,
                toAccountID: nil, frequency: frequency, startDate: startDate)
        updated.kind = kind
        updated.category = category
        updated.note = note
        updated.amount = amount
        updated.accountID = accountID
        updated.toAccountID = kind == .transfer ? toAccountID : nil
        if !scheduleLocked {
            updated.frequency = frequency
            updated.startDate = startDate
        }
        updated.endDate = hasEndDate ? endDate : nil
        store.saveRecurringRule(updated)
        dismiss()
    }
}
