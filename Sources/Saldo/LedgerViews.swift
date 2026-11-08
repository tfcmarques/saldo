import SwiftUI

struct LedgerView: View {
    enum DateScope: String, CaseIterable, Identifiable {
        case all = "All time"
        case lastYear = "Last year"
        case last30Days = "Last 30 days"
        case last7Days = "Last 7 days"
        case lastDay = "Today"

        var id: String { rawValue }
    }

    let store: LedgerStore
    @State private var dateScope: DateScope = .last30Days
    @State private var accountID: UUID?
    @State private var kind: EntryKind?
    @State private var categoryName: String?
    @State private var searchText = ""
    @AppStorage("ledger.showsCategoryTotals", store: TestDataMode.defaults) private var showsCategoryTotals = false
    @Environment(AppRouter.self) private var router
    @Environment(\.undoManager) private var undoManager
    @FocusState private var isSearchFocused: Bool

    private var dateRange: ClosedRange<Date>? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start: Date?
        switch dateScope {
        case .all:
            start = nil
        case .lastYear:
            start = calendar.date(byAdding: .year, value: -1, to: today)
        case .last30Days:
            start = calendar.date(byAdding: .day, value: -29, to: today)
        case .last7Days:
            start = calendar.date(byAdding: .day, value: -6, to: today)
        case .lastDay:
            start = today
        }
        guard let start else { return nil }
        return start...today
    }

    /// `store.entries` is already newest first, so filtering keeps the order.
    private var filteredEntries: [LedgerEntry] {
        let range = dateRange
        return store.entries.filter { entry in
            !store.isPending(entry)
                && (range.map { $0.contains(entry.date) } ?? true)
                && (accountID == nil || entry.accountID == accountID)
                && (kind == nil || entry.kind == kind)
                && (categoryName == nil || entry.category == categoryName)
                && matchesSearch(entry)
        }
    }

    private func categoryTotals(of entries: [LedgerEntry]) -> [CategoryTotal] {
        Dictionary(
            grouping: entries.filter {
                $0.kind == .expense && !$0.isTransfer && $0.source != .reconciliation
            },
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

    private func netTotal(of entries: [LedgerEntry]) -> Double {
        entries.reduce(0) {
            $0 + store.toBase(store.signedAmount($1), accountID: $1.accountID)
        }
    }

    var body: some View {
        let filtered = filteredEntries
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "Add your first entry",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Record an income or expense to start your ledger.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if !store.scheduledEntries.isEmpty {
                        ScheduledPaymentsCard(store: store)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                    List {
                        Section {
                            filters(net: netTotal(of: filtered), count: filtered.count)
                        }

                        let totals = categoryTotals(of: filtered)
                        if !totals.isEmpty {
                            Section {
                                DisclosureGroup(isExpanded: $showsCategoryTotals) {
                                    ForEach(totals) { total in
                                        CategoryRow(
                                            total: total,
                                            maximum: totals.first?.amount ?? total.amount,
                                            currencyCode: store.settings.currencyCode)
                                    }
                                } label: {
                                    SectionLabel("Spending by category")
                                }
                            }
                        }

                        if filtered.isEmpty {
                            ContentUnavailableView(
                                "No matching entries",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text(
                                    "Change the filters or add an income or expense.")
                            )
                        } else {
                            ForEach(dayGroups(of: filtered), id: \.day) { group in
                                Section {
                                    ForEach(group.entries) { entry in
                                        EntryRow(
                                            entry: entry,
                                            accountName: accountName(for: entry),
                                            categoryIcon: categoryIcon(for: entry.category),
                                            categoryColor: categoryColor(for: entry.category),
                                            store: store
                                        )
                                    }
                                    .onDelete { offsets in
                                        store.deleteEntries(
                                            offsets.map { group.entries[$0] },
                                            undoManager: undoManager)
                                    }
                                } header: {
                                    HStack {
                                        SectionLabel(dayTitle(group.day))
                                        Spacer()
                                        MoneyText(
                                            amount: netTotal(of: group.entries),
                                            currencyCode: store.settings.currencyCode,
                                            font: DS.Typeface.caption, signed: true)
                                    }
                                    .textCase(.none)
                                }
                            }
                        }
                    }
                }
            }
        }
        .pageList()
        .navigationTitle("Ledger")
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Ledger") {
                SearchField(prompt: "Search", text: $searchText, focus: $isSearchFocused)
                    .help("Search descriptions, categories and accounts (⌘F)")
                Menu {
                    Button("New transfer", systemImage: "arrow.left.arrow.right") {
                        router.sheet = .newTransfer
                    }
                    .disabled(store.openAccounts.count < 2)
                    Button("Schedule payment", systemImage: "calendar.badge.clock") {
                        router.sheet = .newScheduledPayment
                    }
                    .disabled(store.openAccounts.isEmpty)
                    Button("Schedule refund", systemImage: "calendar.badge.plus") {
                        router.sheet = .newScheduledRefund
                    }
                    .disabled(store.openAccounts.isEmpty)
                    Divider()
                    Button("Categories\u{2026}", systemImage: "tag") {
                        router.sheet = .categories
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.pill(.secondary))
                .fixedSize()
                .help("Transfers, scheduled items and categories")
                Button("New entry", systemImage: "plus") { router.sheet = .newEntry(.expense) }
                    .buttonStyle(.pill(.primary))
                    .disabled(store.openAccounts.isEmpty)
                    .help("Record income or an expense (⌘N)")
            }
            .background(DS.Palette.background)
        }
        .onChange(of: router.searchRequest) { isSearchFocused = true }
    }

    private func dayGroups(of entries: [LedgerEntry]) -> [(day: Date, entries: [LedgerEntry])] {
        var groups: [(day: Date, entries: [LedgerEntry])] = []
        for entry in entries {
            let day = Calendar.current.startOfDay(for: entry.date)
            if groups.last?.day == day {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((day, [entry]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(
            sameYear
                ? .dateTime.weekday(.wide).day().month(.wide)
                : .dateTime.day().month(.wide).year())
    }

    private func filters(net: Double, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    MoneyText(
                        amount: net, currencyCode: store.settings.currencyCode,
                        font: DS.Typeface.figure, signed: true)
                    Text("Net across \(count == 1 ? "1 entry" : "\(count) entries")")
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer()
                PillPicker(
                    title: "Range", selection: $dateScope,
                    options: DateScope.allCases.map { PillOption(value: $0, label: $0.rawValue) },
                    help: "Show entries from this period")
            }
            HStack(spacing: DS.Space.xs) {
                PillPicker(
                    title: "Account", selection: $accountID,
                    allOption: PillOption(value: nil, label: "All accounts"),
                    options: store.accounts.map {
                        PillOption(
                            value: Optional($0.id),
                            label: $0.isClosed ? "\($0.name) (closed)" : $0.name,
                            systemImage: $0.icon.rawValue)
                    },
                    help: "Show entries from one account")
                PillPicker(
                    title: "Type", selection: $kind,
                    allOption: PillOption(value: nil, label: "All activity"),
                    options: EntryKind.allCases.map {
                        PillOption(
                            value: Optional($0), label: $0.rawValue,
                            systemImage: $0 == .income ? "arrow.down.left" : "arrow.up.right")
                    },
                    help: "Show only income or only expenses")
                PillPicker(
                    title: "Category", selection: $categoryName,
                    allOption: PillOption(value: nil, label: "All categories"),
                    options: store.categories.map {
                        PillOption(
                            value: Optional($0.name), label: $0.name,
                            systemImage: $0.icon.rawValue)
                    },
                    help: "Show entries in one category")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, DS.Space.xs)
    }

    private func accountName(for entry: LedgerEntry) -> String {
        store.accounts.first { $0.id == entry.accountID }?.name ?? "Deleted account"
    }

    private func matchesSearch(_ entry: LedgerEntry) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return searchFields(for: entry).contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func searchFields(for entry: LedgerEntry) -> [String] {
        var fields = [entry.note, entry.category]
        if let name = store.accounts.first(where: { $0.id == entry.accountID })?.name {
            fields.append(name)
        }
        if let debtID = entry.debtID,
            let name = store.debts.first(where: { $0.id == debtID })?.name
        {
            fields.append(name)
        }
        if entry.isTransfer, let legs = store.transferLegs(of: entry) {
            let otherID = (entry.kind == .expense ? legs.destination : legs.source).accountID
            if let name = store.accounts.first(where: { $0.id == otherID })?.name {
                fields.append(name)
            }
        }
        return fields
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
        HStack(spacing: DS.Space.s) {
            IconBubble(systemName: total.icon.rawValue, tint: total.color.color, size: 28)
            Text(total.name)
                .font(DS.Typeface.bodyStrong)
                .frame(minWidth: 110, alignment: .leading)
            ProgressView(value: total.amount, total: maximum)
                .tint(total.color.color)
            MoneyText(amount: total.amount, currencyCode: currencyCode)
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, DS.Space.xxs)
    }
}

private struct EntryRow: View {
    let entry: LedgerEntry
    let accountName: String
    let categoryIcon: CategoryIcon
    let categoryColor: CategoryColor
    let store: LedgerStore
    @Environment(AppRouter.self) private var router
    @Environment(\.undoManager) private var undoManager

    private var title: String {
        if let debtID = entry.debtID, let debt = store.debts.first(where: { $0.id == debtID }) {
            return debt.direction == .iOwe ? "Payment to \(debt.name)" : "Payment from \(debt.name)"
        }
        guard entry.isTransfer else { return entry.category }
        let legs = store.transferLegs(of: entry)
        let other = entry.kind == .expense ? legs?.destination : legs?.source
        let name = other.flatMap { leg in store.accounts.first { $0.id == leg.accountID }?.name }
        guard let name else { return "Transfer" }
        return entry.kind == .expense ? "Transfer to \(name)" : "Transfer from \(name)"
    }

    private var details: [String] {
        var parts = [entry.displayNote, accountName]
        if entry.source == .interest || entry.source == .recurring { parts.append("Automatic") }
        return parts
    }

    private var canEdit: Bool { !entry.isTransfer || store.transferLegs(of: entry) != nil }

    var body: some View {
        TransactionRow(
            symbol: entry.isTransfer ? "arrow.left.arrow.right" : categoryIcon.rawValue,
            tint: entry.isTransfer ? DS.Palette.textSecondary : categoryColor.color,
            title: title,
            details: details,
            amount: store.signedAmount(entry),
            currencyCode: store.currencyCode(forAccountID: entry.accountID),
            badge: store.isPending(entry)
                ? StatusBadge(text: "Scheduled", systemImage: "clock", tone: .warning) : nil)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if canEdit { edit() } }
        .accessibilityAction(named: "Edit entry") { if canEdit { edit() } }
        .contextMenu {
            Button("Edit entry", systemImage: "pencil") { edit() }
                .disabled(!canEdit)
            if store.isPending(entry) {
                Button(
                    entry.kind == .income ? "Mark as received" : "Mark as paid",
                    systemImage: "checkmark.circle"
                ) {
                    store.markScheduledPaid(entry)
                }
            }
            Button(
                entry.isTransfer ? "Delete transfer" : "Delete entry", systemImage: "trash",
                role: .destructive
            ) {
                store.deleteEntry(entry, undoManager: undoManager)
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
    @State private var accountPendingClose: Account?
    @State private var debtPendingDeletion: Debt?

    private var closedAccounts: [Account] { store.accounts.filter(\.isClosed) }

    private func accountDetails(_ account: Account) -> [String] {
        [account.type.rawValue, account.currencyCode]
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
                        "Add a bank, cash, savings, or investment account.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !store.openAccounts.isEmpty {
                        if closedAccounts.isEmpty {
                            openAccountRows
                        } else {
                            Section("Open") { openAccountRows }
                        }
                    }
                    if !closedAccounts.isEmpty {
                        Section("Closed") { closedAccountRows }
                    }
                    if !store.debts.isEmpty {
                        Section("Debts") { debtRows }
                    }
                }
            }
        }
        .pageList()
        .navigationTitle("Accounts")
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Accounts") {
                Button("Update value", systemImage: "plusminus") {
                    router.sheet = .reconcileAccount(store.openAccounts.first)
                }
                .buttonStyle(.pill(.secondary))
                .disabled(store.openAccounts.isEmpty)
                .help("Set an account to the balance it has right now")
                Button("Add debt", systemImage: "creditcard") { router.sheet = .newDebt }
                    .buttonStyle(.pill(.secondary))
                    .help("Track money you owe, or money someone owes you")
                Button("Add account", systemImage: "plus") { router.sheet = .newAccount }
                    .buttonStyle(.pill(.primary))
                    .help("Add a bank, cash, savings, or investment account")
            }
                .background(DS.Palette.background)
        }
        .confirmationDialog(
            debtPendingDeletion.map { "Delete \($0.name)?" } ?? "Delete this debt?",
            isPresented: Binding(
                get: { debtPendingDeletion != nil },
                set: { if !$0 { debtPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let debtPendingDeletion { store.deleteDebt(debtPendingDeletion) }
                debtPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { debtPendingDeletion = nil }
        } message: {
            Text(debtPendingDeletion.map { debtDeletionMessage($0, store: store) } ?? "")
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
        .alert(
            "Close \(accountPendingClose?.name ?? "this account")?",
            isPresented: Binding(
                get: { accountPendingClose != nil },
                set: { if !$0 { accountPendingClose = nil } }
            )
        ) {
            Button("Close") {
                if let accountPendingClose {
                    store.setAccountClosed(accountPendingClose, true)
                }
                accountPendingClose = nil
            }
            Button("Cancel", role: .cancel) { accountPendingClose = nil }
        } message: {
            Text(
                "Entries stay. It leaves pickers for new entries and transfers. Its balance still counts. You can reopen it."
            )
        }
    }

    private var debtRows: some View {
        ForEach(store.debts) { debt in
            Button {
                router.sheet = .debtDetail(debt.id)
            } label: {
                DebtRow(store: store, debt: debt)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show payments and details for \(debt.name)")
            .contextMenu {
                Button(
                    debt.direction == .iOwe ? "Record payment" : "Record payment received",
                    systemImage: "checkmark.circle"
                ) { router.sheet = .payDebt(debt) }
                Button("Edit", systemImage: "pencil") { router.sheet = .editDebt(debt) }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    debtPendingDeletion = debt
                }
            }
        }
        .onMove(perform: store.moveDebts)
    }

    private var openAccountRows: some View {
        ForEach(store.openAccounts) { account in
            accountRow(account)
        }
        .onMove(perform: store.moveAccounts)
        .onDelete { offsets in
            accountsPendingDeletion = offsets.map { store.openAccounts[$0] }
        }
    }

    private var closedAccountRows: some View {
        ForEach(closedAccounts) { account in
            accountRow(account)
        }
        .onDelete { offsets in
            accountsPendingDeletion = offsets.map { closedAccounts[$0] }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            if !account.isClosed {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(DS.Palette.textMuted)
                    .help("Drag to reorder")
            }
            IconBubble(systemName: account.icon.rawValue, tint: account.color.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(DS.Typeface.bodyStrong)
                    .foregroundStyle(DS.Palette.textPrimary)
                DetailLine(accountDetails(account))
            }
            Spacer()
            MoneyText(
                amount: store.balance(for: account),
                currencyCode: store.currencyCode(for: account))
            Button {
                router.sheet = .reconcileAccount(account)
            } label: {
                Image(systemName: "plusminus")
            }
            .buttonStyle(.icon)
            .help("Update \(account.name) to its current value")
            Button {
                router.sheet = .editAccount(account)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.icon)
            .help("Edit \(account.name)")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Update value", systemImage: "plusminus") {
                router.sheet = .reconcileAccount(account)
            }
            if account.isClosed {
                Button("Reopen account", systemImage: "arrow.uturn.backward") {
                    store.setAccountClosed(account, false)
                }
            } else {
                Button("Close account", systemImage: "archivebox") {
                    accountPendingClose = account
                }
            }
            Button("Delete account", systemImage: "trash", role: .destructive) {
                accountsPendingDeletion = [account]
            }
        }
    }
}

struct AddEntrySheet: View {
    let store: LedgerStore
    let entry: LedgerEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var kind: EntryKind
    @State private var category: String
    @State private var note: String
    @State private var amount: Double
    @State private var isAmountValid = true
    @State private var date: Date
    @State private var accountID: UUID?
    @State private var spareChangeEnabled = false
    @State private var spareChangeAccountID: UUID?
    @State private var isAddingCategory = false
    @State private var countsInAvailable: Bool

    init(
        store: LedgerStore, entry: LedgerEntry? = nil, initialKind: EntryKind = .expense,
        schedulePayment: Bool = false
    ) {
        self.store = store
        self.entry = entry
        _kind = State(initialValue: entry?.kind ?? initialKind)
        _category = State(initialValue: entry?.category ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _amount = State(initialValue: entry?.amount ?? 0)
        let initialDate =
            entry?.date
            ?? (schedulePayment
                ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() : Date())
        _date = State(initialValue: initialDate)
        _accountID = State(initialValue: entry?.accountID)
        let existingSpareChange = entry.flatMap { store.spareChangeLegs(for: $0) }
        _spareChangeEnabled = State(initialValue: existingSpareChange != nil)
        _spareChangeAccountID = State(initialValue: existingSpareChange?.destination.accountID)
        _countsInAvailable = State(initialValue: entry?.countsInAvailable ?? true)
    }

    private var amountCurrency: String {
        accountID.map(store.currencyCode(forAccountID:)) ?? store.settings.currencyCode
    }

    private var savingsAccounts: [Account] {
        store.includingSelection(
            spareChangeAccountID,
            in: store.openAccounts.filter { $0.type == .savings && $0.id != accountID })
    }

    private var spareChange: Double { store.spareChange(for: amount) }

    private var showsSpareChange: Bool { kind == .expense }

    private var isFutureDate: Bool {
        store.startOfDay(date) > store.startOfDay(.now)
    }

    private var schedulesPayment: Bool { kind == .expense && isFutureDate }

    private var schedulesRefund: Bool { kind == .income && isFutureDate }

    private var spareChangeIsReady: Bool {
        !spareChangeEnabled || (spareChange > 0 && spareChangeAccountID != nil)
    }

    var body: some View {
        Form {
            Picker("Type", selection: $kind) {
                ForEach(EntryKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            AmountField(
                "Amount (\(amountCurrency))", value: $amount, currencyCode: amountCurrency,
                isValid: $isAmountValid, focusesOnAppear: true)
            Picker("Account", selection: $accountID) {
                Text("Choose an account").tag(UUID?.none)
                ForEach(store.includingSelection(accountID, in: store.accountsByUsage)) { account in
                    Label(account.name, systemImage: Symbol.outline(account.icon.rawValue)).tag(Optional(account.id))
                }
            }
            Picker("Category", selection: $category) {
                Text("Choose a category").tag("")
                ForEach(store.categories) { storedCategory in
                    Label(storedCategory.name, systemImage: Symbol.outline(storedCategory.icon.rawValue))
                        .tag(storedCategory.name)
                }
            }
            Button("New category", systemImage: "plus") { isAddingCategory = true }
                .buttonStyle(.pill(.secondary, compact: true))
                .help("Create a category you can use on entries")
            TextField("Description", text: $note)
            if showsSpareChange {
                spareChangeSection
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
            if schedulesPayment {
                Toggle("Count in available cash", isOn: $countsInAvailable)
                Text(
                    countsInAvailable
                        ? "Scheduled for \(store.formattedDate(date)). This amount is set aside now and posts on that date."
                        : "Scheduled for \(store.formattedDate(date)). Available cash stays the same until it posts."
                )
                .formHint()
            }
            if schedulesRefund {
                Text(
                    "Scheduled for \(store.formattedDate(date)). Counted in your balance now. It posts on that date."
                )
                .formHint()
            }
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 440)
        .navigationTitle(sheetTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) {
                    guard let accountID else { return }
                    if let entry {
                        store.updateEntry(
                            entry, kind: kind, category: category, note: note, amount: amount,
                            date: date, accountID: accountID,
                            spareChangeAccountID: spareChangeEnabled ? spareChangeAccountID : nil,
                            countsInAvailable: countsInAvailable)
                    } else {
                        store.addEntry(
                            kind: kind, category: category, note: note, amount: amount,
                            date: date, accountID: accountID,
                            spareChangeAccountID: spareChangeEnabled ? spareChangeAccountID : nil,
                            countsInAvailable: countsInAvailable)
                    }
                    dismiss()
                }
                .disabled(
                    accountID == nil
                        || category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !isAmountValid
                        || amount <= 0
                        || !spareChangeIsReady)
                .buttonStyle(.pill(.primary))
            }
        }
        .onAppear {
            if entry == nil {
                accountID = store.accountsByUsage.first?.id
                category = lastUsedCategory(for: kind)
            }
            if spareChangeAccountID == nil {
                spareChangeAccountID = savingsAccounts.first?.id
            }
        }
        .onChange(of: accountID) { _, _ in alignSpareChangeAccount() }
        .onChange(of: amount) { _, _ in
            if spareChange == 0 { spareChangeEnabled = false }
        }
        .onChange(of: kind) { oldKind, _ in
            if kind != .expense { spareChangeEnabled = false }
            if entry == nil, category.isEmpty || category == lastUsedCategory(for: oldKind) {
                category = lastUsedCategory(for: kind)
            }
        }
        .sheet(isPresented: $isAddingCategory) {
            NavigationStack {
                AddCategorySheet(store: store)
            }
        }
    }

    /// Empty when nothing of this kind was entered yet, so a category is never picked silently.
    private func lastUsedCategory(for kind: EntryKind) -> String {
        let name = store.entries.first {
            $0.kind == kind && !$0.isTransfer && $0.debtID == nil && $0.source == .manual
        }?.category ?? ""
        return store.categories.contains { $0.name == name } ? name : ""
    }

    private var sheetTitle: String {
        if entry != nil { return "Edit entry" }
        if schedulesPayment { return "Schedule payment" }
        if schedulesRefund { return "Schedule refund" }
        return "New entry"
    }

    private var confirmTitle: String {
        if entry != nil { return "Save" }
        return schedulesPayment || schedulesRefund ? "Schedule" : "Add"
    }

    private var spareChangeSection: some View {
        Section {
            Toggle("Spare change", isOn: $spareChangeEnabled)
                .disabled(savingsAccounts.isEmpty || spareChange == 0)
            if spareChangeEnabled, spareChange > 0 {
                Picker("Save into", selection: $spareChangeAccountID) {
                    Text("Choose a savings account").tag(UUID?.none)
                    ForEach(savingsAccounts) { account in
                        Label(account.name, systemImage: Symbol.outline(account.icon.rawValue)).tag(Optional(account.id))
                    }
                }
                Text(spareChangeSummary)
                    .formHint()
            } else if savingsAccounts.isEmpty {
                Text("Add a savings account to set spare change aside.")
                    .formHint()
            }
        }
    }

    private var spareChangeSummary: String {
        let spare = spareChange.formatted(.currency(code: amountCurrency))
        guard let destination = savingsAccounts.first(where: { $0.id == spareChangeAccountID })
        else { return "\(spare) will leave this account." }
        let destinationCode = store.currencyCode(for: destination)
        let when = "on \(store.formattedDate(date))"
        guard let accountID, destinationCode != amountCurrency else {
            return "\(spare) leaves this account and is saved in \(destination.name) \(when)."
        }
        let received = store.convertedTransferAmount(spareChange, from: accountID, to: destination.id)
        let saved = received.formatted(.currency(code: destinationCode))
        return "\(spare) leaves this account \(when). \(saved) is saved in \(destination.name)."
    }

    private func alignSpareChangeAccount() {
        if savingsAccounts.contains(where: { $0.id == spareChangeAccountID }) { return }
        spareChangeAccountID = savingsAccounts.first?.id
        if savingsAccounts.isEmpty { spareChangeEnabled = false }
    }
}

/// Adds an account, or edits one when `account` is given.
struct AccountSheet: View {
    let store: LedgerStore
    let account: Account?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var type: AccountType
    @State private var icon: AccountIcon
    @State private var color: AccountColor
    @State private var openingBalance: Double
    @State private var isBalanceValid = true
    @State private var currency: String
    @State private var countsInNetWorth: Bool
    @State private var isClosed: Bool

    init(store: LedgerStore, account: Account? = nil) {
        self.store = store
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .checking)
        _icon = State(initialValue: account?.icon ?? .wallet)
        _color = State(initialValue: account?.color ?? store.nextAvailableAccountColor)
        _openingBalance = State(initialValue: account?.openingBalance ?? 0)
        _currency = State(initialValue: account?.currencyCode ?? "")
        _countsInNetWorth = State(initialValue: account?.countsInNetWorth ?? true)
        _isClosed = State(initialValue: account?.isClosed ?? false)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var balanceCurrency: String {
        currency.isEmpty ? store.settings.currencyCode : currency
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("Everyday"))
                    .focused($isNameFocused)
                Picker("Type", selection: $type) {
                    ForEach(AccountType.allCases) { Text($0.rawValue).tag($0) }
                }
                CurrencyPicker(currency: $currency, store: store)
                AmountField(
                    "Opening balance (\(balanceCurrency))", value: $openingBalance,
                    currencyCode: balanceCurrency, isValid: $isBalanceValid)
                if account != nil {
                    Text("Entries are applied on top of the opening balance.")
                        .formHint()
                }
            }
            Section("Appearance") {
                Picker("Icon", selection: $icon) {
                    ForEach(AccountIcon.allCases) { icon in
                        Label(icon.title, systemImage: Symbol.outline(icon.rawValue)).tag(icon)
                    }
                }
                PaletteColorPicker(label: "Color", color: $color)
            }
            Section("Options") {
                Toggle("Count in net worth", isOn: $countsInNetWorth)
                Text("Turn this off for money set aside, such as tax savings.")
                    .formHint()
                if account != nil {
                    Toggle("Closed", isOn: $isClosed)
                    Text("A closed account leaves pickers and charts. Its entries and balance stay.")
                        .formHint()
                }
            }
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 440)
        .navigationTitle(account == nil ? "New account" : "Edit account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(account == nil ? "Add" : "Save", action: save)
                    .disabled(trimmedName.isEmpty || !isBalanceValid)
                    .buttonStyle(.pill(.primary))
            }
        }
        .onAppear { isNameFocused = true }
    }

    private func save() {
        if let account {
            store.updateAccount(
                account, name: trimmedName, type: type, icon: icon, color: color,
                openingBalance: openingBalance, currencyCode: currency,
                countsInNetWorth: countsInNetWorth, isClosed: isClosed)
        } else {
            store.addAccount(
                name: trimmedName, type: type, icon: icon, color: color,
                openingBalance: openingBalance, currencyCode: currency,
                countsInNetWorth: countsInNetWorth)
        }
        dismiss()
    }
}

struct CurrencyPicker: View {
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

struct ReconcileAccountSheet: View {
    let store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var accountID: UUID?
    @State private var statedValue: Double
    @State private var isValueValid = true
    @State private var date = Date()
    @State private var note = ""

    init(store: LedgerStore, account: Account?) {
        self.store = store
        let initial = account ?? store.openAccounts.first
        _accountID = State(initialValue: initial?.id)
        _statedValue = State(initialValue: initial.map { store.balance(for: $0) } ?? 0)
    }

    private var selectedAccount: Account? {
        store.accounts.first { $0.id == accountID }
    }

    private var currencyCode: String {
        selectedAccount.map(store.currencyCode(for:)) ?? store.settings.currencyCode
    }

    private var bookBalance: Double {
        selectedAccount.map { store.balance(for: $0) } ?? 0
    }

    private var adjustment: Double {
        let current = AmountExpression.rounded(bookBalance, fractionDigits: 2)
        let stated = AmountExpression.rounded(statedValue, fractionDigits: 2)
        return AmountExpression.rounded(stated - current, fractionDigits: 2)
    }

    private var accountSelection: Binding<UUID?> {
        Binding(
            get: { accountID },
            set: { newValue in
                accountID = newValue
                if let account = store.accounts.first(where: { $0.id == newValue }) {
                    statedValue = store.balance(for: account)
                }
            }
        )
    }

    var body: some View {
        Form {
            Picker("Account", selection: accountSelection) {
                ForEach(store.includingSelection(accountID, in: store.openAccounts)) { account in
                    Label(account.name, systemImage: Symbol.outline(account.icon.rawValue)).tag(Optional(account.id))
                }
            }
            LabeledContent("Balance in Saldo") {
                Text(bookBalance, format: .currency(code: currencyCode))
            }
            AmountField(
                "Current value (\(currencyCode))", value: $statedValue,
                currencyCode: currencyCode, isValid: $isValueValid
            )
            .id(accountID)
            if selectedAccount != nil, abs(adjustment) >= 0.01 {
                LabeledContent(adjustment > 0 ? "Gain" : "Loss") {
                    MoneyText(amount: adjustment, currencyCode: currencyCode, signed: true)
                }
            }
            Text(adjustmentSummary)
                .formHint()
            TextField("Description", text: $note, prompt: Text("Optional"))
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 440)
        .navigationTitle("Update value")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Update") {
                    guard let selectedAccount else { return }
                    store.reconcileAccount(
                        selectedAccount, to: statedValue, note: note, date: date)
                    dismiss()
                }
                .disabled(selectedAccount == nil || !isValueValid || abs(adjustment) < 0.01)
                .buttonStyle(.pill(.primary))
            }
        }
    }

    private var adjustmentSummary: String {
        guard let selectedAccount else { return "Choose an account." }
        let amount = abs(adjustment).formatted(.currency(code: currencyCode))
        if adjustment > 0 {
            return "\(amount) is added to the ledger as a gain, so \(selectedAccount.name) matches."
        }
        if adjustment < 0 {
            return "\(amount) is added to the ledger as a loss, so \(selectedAccount.name) matches."
        }
        return "\(selectedAccount.name) is already at this value."
    }
}
