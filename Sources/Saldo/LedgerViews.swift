import SwiftUI

struct LedgerView: View {
    enum DateScope: String, CaseIterable, Identifiable {
        case last30Days = "Last 30 days"
        case thisMonth = "This month"
        case custom = "Custom"

        var id: String { rawValue }
    }

    let store: LedgerStore
    @State private var dateScope: DateScope = .last30Days
    @State private var customStart =
        Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    @State private var customEnd = Date()
    @State private var accountID: UUID?
    @State private var kind: EntryKind?
    @State private var categoryName: String?
    @Environment(AppRouter.self) private var router

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        switch dateScope {
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return start...today
        case .thisMonth:
            let start =
                calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            return start...today
        case .custom:
            return min(customStart, customEnd)...max(customStart, customEnd)
        }
    }

    private var filteredEntries: [LedgerEntry] {
        store.entries.filter { entry in
            dateRange.contains(entry.date)
                && (accountID == nil || entry.accountID == accountID)
                && (kind == nil || entry.kind == kind)
                && (categoryName == nil || entry.category == categoryName)
        }
    }

    private var categoryTotals: [CategoryTotal] {
        Dictionary(
            grouping: filteredEntries.filter { $0.kind == .expense && !$0.isTransfer },
            by: \.category
        )
        .map {
            CategoryTotal(
                name: $0.key,
                icon: categoryIcon(for: $0.key),
                color: categoryColor(for: $0.key),
                amount: $0.value.reduce(0) {
                    $0 + store.toBase($1.amount, accountID: $1.accountID)
                }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var netTotal: Double {
        filteredEntries.reduce(0) {
            $0 + store.toBase(store.signedAmount($1), accountID: $1.accountID)
        }
    }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "Add your first entry",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Record an income or expense to start your ledger.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        filters
                    }

                    if !categoryTotals.isEmpty {
                        Section("Spending by category") {
                            ForEach(categoryTotals) { total in
                                CategoryRow(
                                    total: total,
                                    maximum: categoryTotals.first?.amount ?? total.amount,
                                    currencyCode: store.settings.currencyCode)
                            }
                        }
                    }

                    Section("Entries") {
                        if filteredEntries.isEmpty {
                            ContentUnavailableView(
                                "No matching entries",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Change the filters or add an income or expense.")
                            )
                        } else {
                            ForEach(filteredEntries) { entry in
                                EntryRow(
                                    entry: entry,
                                    accountName: accountName(for: entry),
                                    categoryIcon: categoryIcon(for: entry.category),
                                    categoryColor: categoryColor(for: entry.category),
                                    store: store
                                )
                            }
                            .onDelete { store.deleteEntries(at: $0, from: filteredEntries) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ledger")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add transfer", systemImage: "arrow.left.arrow.right") {
                    router.sheet = .newTransfer
                }
                .disabled(store.accounts.count < 2)
                Button("Add entry", systemImage: "plus") { router.sheet = .newEntry(.expense) }
                    .disabled(store.accounts.isEmpty)
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateScope.rawValue).font(.title3.weight(.semibold))
                    Text("Net \(netTotal, format: .currency(code: store.settings.currencyCode))")
                        .font(.caption)
                        .foregroundStyle(netTotal < 0 ? .red : .secondary)
                }
                Spacer()
                Picker("Range", selection: $dateScope) {
                    ForEach(DateScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if dateScope == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                }
            }
            HStack {
                Picker("Account", selection: $accountID) {
                    Text("All accounts").tag(UUID?.none)
                    ForEach(store.accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker("Type", selection: $kind) {
                    Text("All activity").tag(EntryKind?.none)
                    ForEach(EntryKind.allCases) { type in
                        Text(type.rawValue).tag(Optional(type))
                    }
                }
                Picker("Category", selection: $categoryName) {
                    Text("All categories").tag(String?.none)
                    ForEach(store.categories) { category in
                        Label(category.name, systemImage: category.icon.rawValue)
                            .tag(Optional(category.name))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func accountName(for entry: LedgerEntry) -> String {
        store.accounts.first { $0.id == entry.accountID }?.name ?? "Deleted account"
    }

    private func categoryIcon(for name: String) -> CategoryIcon {
        store.categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.icon
            ?? .tag
    }

    private func categoryColor(for name: String) -> CategoryColor {
        store.categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.color
            ?? .blue
    }
}

private struct CategoryTotal: Identifiable {
    let name: String
    let icon: CategoryIcon
    let color: CategoryColor
    let amount: Double
    var id: String { name }
}

private struct CategoryRow: View {
    let total: CategoryTotal
    let maximum: Double
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: total.icon.rawValue)
                .frame(width: 18)
                .foregroundStyle(total.color.color)
            Text(total.name).frame(minWidth: 110, alignment: .leading)
            ProgressView(value: total.amount, total: maximum)
                .tint(.orange)
            Text(total.amount, format: .currency(code: currencyCode))
                .fontWeight(.medium)
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

private struct EntryRow: View {
    let entry: LedgerEntry
    let accountName: String
    let categoryIcon: CategoryIcon
    let categoryColor: CategoryColor
    let store: LedgerStore
    @Environment(AppRouter.self) private var router

    private var title: String {
        guard entry.isTransfer else { return entry.category }
        let legs = store.transferLegs(of: entry)
        let other = entry.kind == .expense ? legs?.destination : legs?.source
        let name = other.flatMap { leg in store.accounts.first { $0.id == leg.accountID }?.name }
        guard let name else { return "Transfer" }
        return entry.kind == .expense ? "Transfer to \(name)" : "Transfer from \(name)"
    }

    private var subtitle: String {
        let base = entry.note.isEmpty ? accountName : entry.note
        return entry.source == .manual ? base : "\(base) \u{00B7} Automatic"
    }

    private var canEdit: Bool { !entry.isTransfer || store.transferLegs(of: entry) != nil }

    var body: some View {
        HStack(spacing: 12) {
            Image(
                systemName: entry.kind == .income
                    ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill"
            )
            .foregroundStyle(entry.kind == .income ? .green : .red)
            .font(.title3)
            Image(systemName: entry.isTransfer ? "arrow.left.arrow.right" : categoryIcon.rawValue)
                .foregroundStyle(entry.isTransfer ? Color.teal : categoryColor.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(
                    store.signedAmount(entry),
                    format: .currency(code: store.currencyCode(forAccountID: entry.accountID))
                )
                .fontWeight(.semibold)
                .foregroundStyle(entry.kind == .income ? .green : .primary)
                Text(store.formattedDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                edit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .disabled(!canEdit)
            .help("Edit entry")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Edit entry", systemImage: "pencil") { edit() }
                .disabled(!canEdit)
            Button(
                entry.isTransfer ? "Delete transfer" : "Delete entry", systemImage: "trash",
                role: .destructive
            ) {
                store.deleteEntry(entry)
            }
        }
    }

    private func edit() {
        router.sheet = entry.isTransfer ? .editTransfer(entry) : .editEntry(entry)
    }
}

struct AccountsView: View {
    let store: LedgerStore
    @Environment(AppRouter.self) private var router
    @State private var accountsPendingDeletion: [Account] = []

    private func accountSubtitle(_ account: Account) -> String {
        var parts = [account.type.rawValue]
        if !account.currencyCode.isEmpty { parts.append(account.currencyCode) }
        if account.interestRate > 0 {
            let rate = account.interestRate.formatted(.number.precision(.fractionLength(0...3)))
            parts.append("\(rate)% p.a.")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var deletionMessage: String {
        let ids = Set(accountsPendingDeletion.map(\.id))
        let count = store.entries.filter { ids.contains($0.accountID) }.count
        return
            "This also deletes \(count) \(count == 1 ? "entry" : "entries"). Transfers to or from other accounts keep their other side. This cannot be undone."
    }

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                ContentUnavailableView(
                    "No accounts yet",
                    systemImage: "building.columns",
                    description: Text(
                        "Add a bank, cash, savings, credit card, or investment account.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.accounts) { account in
                        HStack(spacing: 12) {
                            Image(systemName: account.icon.rawValue)
                                .frame(width: 28)
                                .foregroundStyle(account.color.color)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name).fontWeight(.medium)
                                Text(accountSubtitle(account)).font(.caption).foregroundStyle(
                                    .secondary)
                            }
                            Spacer()
                            Text(
                                store.balance(for: account),
                                format: .currency(code: store.currencyCode(for: account))
                            )
                            .fontWeight(.semibold)
                            Button {
                                router.sheet = .editAccount(account)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Edit \(account.name)")
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Delete account", systemImage: "trash", role: .destructive) {
                                accountsPendingDeletion = [account]
                            }
                        }
                    }
                    .onDelete { offsets in
                        accountsPendingDeletion = offsets.map { store.accounts[$0] }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add account", systemImage: "plus") { router.sheet = .newAccount }
            }
        }
        .confirmationDialog(
            accountsPendingDeletion.count == 1
                ? "Delete \(accountsPendingDeletion[0].name)?" : "Delete these accounts?",
            isPresented: Binding(
                get: { !accountsPendingDeletion.isEmpty },
                set: { if !$0 { accountsPendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                accountsPendingDeletion.forEach { store.deleteAccount($0) }
                accountsPendingDeletion = []
            }
            Button("Cancel", role: .cancel) { accountsPendingDeletion = [] }
        } message: {
            Text(deletionMessage)
        }
    }
}

struct AddEntrySheet: View {
    enum Field: Hashable { case description, amount }

    let store: LedgerStore
    let entry: LedgerEntry?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var kind: EntryKind
    @State private var category: String
    @State private var note: String
    @State private var amount: Double
    @State private var date: Date
    @State private var accountID: UUID?
    @State private var isAddingCategory = false

    init(store: LedgerStore, entry: LedgerEntry? = nil, initialKind: EntryKind = .expense) {
        self.store = store
        self.entry = entry
        _kind = State(initialValue: entry?.kind ?? initialKind)
        _category = State(initialValue: entry?.category ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _amount = State(initialValue: entry?.amount ?? 0)
        _date = State(initialValue: entry?.date ?? Date())
        _accountID = State(initialValue: entry?.accountID)
    }

    private var amountCurrency: String {
        accountID.map(store.currencyCode(forAccountID:)) ?? store.settings.currencyCode
    }

    var body: some View {
        Form {
            Picker("Type", selection: $kind) {
                ForEach(EntryKind.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Account", selection: $accountID) {
                Text("Choose an account").tag(UUID?.none)
                ForEach(store.accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            Picker("Category", selection: $category) {
                Text("Choose a category").tag("")
                ForEach(store.categories) { storedCategory in
                    Label(storedCategory.name, systemImage: storedCategory.icon.rawValue)
                        .tag(storedCategory.name)
                }
            }
            Button("Add category", systemImage: "plus") { isAddingCategory = true }
            TextField("Description", text: $note)
                .focused($focusedField, equals: .description)
            TextField(
                "Amount (\(amountCurrency))", value: $amount,
                format: .number.precision(.fractionLength(2)))
                .focused($focusedField, equals: .amount)
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .navigationTitle(entry == nil ? "New entry" : "Edit entry")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(entry == nil ? "Add" : "Save") {
                    guard let accountID else { return }
                    if let entry {
                        store.updateEntry(
                            entry, kind: kind, category: category, note: note, amount: amount,
                            date: date, accountID: accountID)
                    } else {
                        store.addEntry(
                            kind: kind, category: category, note: note, amount: amount,
                            date: date, accountID: accountID)
                    }
                    dismiss()
                }
                .disabled(
                    accountID == nil
                        || category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || amount <= 0)
            }
        }
        .onAppear {
            if entry == nil {
                accountID = store.accounts.first?.id
                category = store.categories.first?.name ?? ""
            }
            focusedField = .description
        }
        .sheet(isPresented: $isAddingCategory) {
            NavigationStack {
                AddCategorySheet(store: store)
            }
        }
    }
}

private struct InterestSection: View {
    @Binding var earnsInterest: Bool
    @Binding var rate: Double
    @Binding var taxRate: Double
    @Binding var startDate: Date
    let accruedThrough: Date?
    let store: LedgerStore

    var body: some View {
        Section("Interest") {
            Toggle("Earns interest", isOn: $earnsInterest)
            if earnsInterest {
                TextField(
                    "Annual rate (TANB, %)", value: $rate,
                    format: .number.precision(.fractionLength(0...3)))
                TextField(
                    "Tax withheld (%)", value: $taxRate,
                    format: .number.precision(.fractionLength(0...2)))
                if let accruedThrough {
                    Text("Interest is credited daily, up to \(store.formattedDate(accruedThrough)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker(
                        "Start accruing from", selection: $startDate, in: ...Date.now,
                        displayedComponents: .date)
                    Text(
                        "One interest entry is added per day on the running balance. Past days are filled in from the start date."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AddAccountSheet: View {
    let store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var icon: AccountIcon = .wallet
    @State private var color: AccountColor = .blue
    @State private var openingBalance = 0.0
    @State private var earnsInterest = false
    @State private var interestRate = 0.0
    @State private var interestTaxRate = 0.0
    @State private var interestStart = Date()
    @State private var currency = ""

    var body: some View {
        Form {
            TextField("Name", text: $name).focused($isNameFocused)
            Picker("Type", selection: $type) {
                ForEach(AccountType.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Icon", selection: $icon) {
                ForEach(AccountIcon.allCases) { icon in
                    Label(icon.title, systemImage: icon.rawValue).tag(icon)
                }
            }
            Picker("Color", selection: $color) {
                ForEach(AccountColor.allCases) { color in
                    AccountColorLabel(color: color).tag(color)
                }
            }
            CurrencyPicker(currency: $currency, store: store)
            TextField(
                "Opening balance", value: $openingBalance,
                format: .number.precision(.fractionLength(2)))
            InterestSection(
                earnsInterest: $earnsInterest, rate: $interestRate, taxRate: $interestTaxRate,
                startDate: $interestStart, accruedThrough: nil, store: store)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .navigationTitle("New account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    store.addAccount(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines), type: type,
                        icon: icon,
                        color: color,
                        openingBalance: openingBalance,
                        interestRate: earnsInterest ? interestRate : 0,
                        interestTaxRate: interestTaxRate,
                        interestStartDate: interestStart,
                        currencyCode: currency)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            color = store.nextAvailableAccountColor
            isNameFocused = true
        }
    }
}

private struct CurrencyPicker: View {
    @Binding var currency: String
    let store: LedgerStore

    var body: some View {
        Picker("Currency", selection: $currency) {
            Text("Same as app (\(store.settings.currencyCode))").tag("")
            ForEach(supportedCurrencies.filter { $0 != store.settings.currencyCode }, id: \.self) {
                Text($0).tag($0)
            }
        }
    }
}

struct EditAccountSheet: View {
    let store: LedgerStore
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var type: AccountType
    @State private var icon: AccountIcon
    @State private var color: AccountColor
    @State private var openingBalance: Double
    @State private var earnsInterest: Bool
    @State private var interestRate: Double
    @State private var interestTaxRate: Double
    @State private var interestStart = Date()
    @State private var currency: String

    init(store: LedgerStore, account: Account) {
        self.store = store
        self.account = account
        _name = State(initialValue: account.name)
        _type = State(initialValue: account.type)
        _icon = State(initialValue: account.icon)
        _color = State(initialValue: account.color)
        _openingBalance = State(initialValue: account.openingBalance)
        _earnsInterest = State(initialValue: account.interestRate > 0)
        _interestRate = State(initialValue: account.interestRate)
        _interestTaxRate = State(initialValue: account.interestTaxRate)
        _currency = State(initialValue: account.currencyCode)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name).focused($isNameFocused)
            Picker("Type", selection: $type) {
                ForEach(AccountType.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Icon", selection: $icon) {
                ForEach(AccountIcon.allCases) { icon in
                    Label(icon.title, systemImage: icon.rawValue).tag(icon)
                }
            }
            Picker("Color", selection: $color) {
                ForEach(AccountColor.allCases) { color in
                    AccountColorLabel(color: color).tag(color)
                }
            }
            CurrencyPicker(currency: $currency, store: store)
            TextField(
                "Opening balance", value: $openingBalance,
                format: .number.precision(.fractionLength(2)))
            Text("Existing entries are kept and applied on top of this opening balance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            InterestSection(
                earnsInterest: $earnsInterest, rate: $interestRate, taxRate: $interestTaxRate,
                startDate: $interestStart,
                accruedThrough: account.interestRate > 0 ? account.interestAccruedThrough : nil,
                store: store)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .navigationTitle("Edit account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.updateAccount(
                        account,
                        name: name,
                        type: type,
                        icon: icon,
                        color: color,
                        openingBalance: openingBalance,
                        interestRate: earnsInterest ? interestRate : 0,
                        interestTaxRate: interestTaxRate,
                        interestStartDate: interestStart,
                        currencyCode: currency
                    )
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { isNameFocused = true }
    }
}
