import Foundation
import Observation
import SQLite3

@Observable
final class LedgerStore {
    var database: OpaquePointer?
    var accounts: [Account] = []
    var entries: [LedgerEntry] = []
    var categories: [LedgerCategory] = []
    var budgets: [Budget] = []
    var recurringRules: [RecurringRule] = []
    /// Base-currency value of one unit of each foreign currency.
    var exchangeRates: [String: Double] = [:]
    private(set) var settings: AppSettings = .default
    let databaseURL: URL

    init(databaseURL: URL = LedgerStore.defaultDatabaseURL) {
        self.databaseURL = databaseURL
        openDatabase()
        createTables()
        reload()
        accrueInterest()
        generateRecurringEntries()
    }

    deinit {
        sqlite3_close(database)
    }

    func addAccount(
        name: String,
        type: AccountType,
        icon: AccountIcon = .wallet,
        color: AccountColor? = nil,
        openingBalance: Double,
        interestRate: Double = 0,
        interestTaxRate: Double = 0,
        interestStartDate: Date = .now,
        currencyCode: String = ""
    ) {
        var account = Account(
            name: name,
            type: type,
            icon: icon,
            color: color ?? nextAvailableAccountColor,
            openingBalance: openingBalance
        )
        account.interestRate = max(interestRate, 0)
        account.interestTaxRate = min(max(interestTaxRate, 0), 100)
        account.interestAccruedThrough =
            account.interestRate > 0 ? dayBefore(interestStartDate) : nil
        account.currencyCode = normalizedCurrency(currencyCode)
        execute(
            "INSERT INTO accounts (id, name, type, icon, color, opening_balance, created_at, interest_rate, interest_tax_rate, interest_accrued_through, currency) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(account.id.uuidString), .text(account.name), .text(account.type.rawValue),
                .text(account.icon.rawValue), .text(account.color.rawValue),
                .double(account.openingBalance),
                .double(account.createdAt.timeIntervalSince1970),
                .double(account.interestRate), .double(account.interestTaxRate),
                .double(account.interestAccruedThrough?.timeIntervalSince1970 ?? 0),
                .text(account.currencyCode),
            ]
        )
        reload()
        accrueInterest()
    }

    func updateAccount(
        _ account: Account,
        name: String,
        type: AccountType,
        icon: AccountIcon? = nil,
        color: AccountColor? = nil,
        openingBalance: Double,
        interestRate: Double? = nil,
        interestTaxRate: Double? = nil,
        interestStartDate: Date? = nil,
        currencyCode: String? = nil
    ) {
        let normalizedName = normalized(name)
        guard !normalizedName.isEmpty else { return }
        let rate = max(interestRate ?? account.interestRate, 0)
        let taxRate = min(max(interestTaxRate ?? account.interestTaxRate, 0), 100)
        // Keep the accrual cursor while interest stays on so past days aren't re-credited.
        let accruedThrough: Date? =
            rate > 0
            ? (account.interestAccruedThrough ?? dayBefore(interestStartDate ?? .now)) : nil
        execute(
            "UPDATE accounts SET name = ?, type = ?, icon = ?, color = ?, opening_balance = ?, interest_rate = ?, interest_tax_rate = ?, interest_accrued_through = ?, currency = ? WHERE id = ?",
            bindings: [
                .text(normalizedName), .text(type.rawValue), .text((icon ?? account.icon).rawValue),
                .text((color ?? account.color).rawValue), .double(openingBalance),
                .double(rate), .double(taxRate),
                .double(accruedThrough?.timeIntervalSince1970 ?? 0),
                .text(currencyCode.map(normalizedCurrency) ?? account.currencyCode),
                .text(account.id.uuidString),
            ]
        )
        reload()
        accrueInterest()
    }

    /// Credits one interest entry per elapsed day for every account that earns interest.
    func accrueInterest(through endDate: Date = .now) {
        let calendar = Calendar.current
        let today = startOfDay(endDate)
        let due = accounts.filter { account in
            guard account.interestRate > 0, let through = account.interestAccruedThrough else {
                return false
            }
            return (calendar.date(byAdding: .day, value: 1, to: startOfDay(through)) ?? today)
                <= today
        }
        guard !due.isEmpty else { return }

        var ensuredCategory = false
        execute("BEGIN IMMEDIATE TRANSACTION")
        for account in due {
            guard let through = account.interestAccruedThrough,
                var day = calendar.date(byAdding: .day, value: 1, to: startOfDay(through))
            else { continue }

            let history = entries.filter { $0.accountID == account.id }.sorted { $0.date < $1.date }
            let dailyFactor =
                account.interestRate / 100 / 365 * (1 - account.interestTaxRate / 100)
            let note = "Daily interest (\(String(format: "%.2f", account.interestRate))% p.a.)"
            var balance = account.openingBalance
            var next = 0

            while day <= today {
                while next < history.count, history[next].date < day {
                    balance +=
                        history[next].kind == .income ? history[next].amount : -history[next].amount
                    next += 1
                }
                // Four decimals: rounding daily to cents would skew small balances.
                let interest = (balance * dailyFactor * 10_000).rounded() / 10_000
                if interest > 0 {
                    if !ensuredCategory {
                        _ = insertCategoryIfNeeded("Interest", icon: .interest, color: .green)
                        ensuredCategory = true
                    }
                    let entry = LedgerEntry(
                        kind: .income, category: "Interest", note: note, amount: interest,
                        date: day, accountID: account.id, source: .interest)
                    insertEntry(entry)
                    balance += interest
                }
                guard let following = calendar.date(byAdding: .day, value: 1, to: day) else {
                    break
                }
                day = following
            }
            execute(
                "UPDATE accounts SET interest_accrued_through = ? WHERE id = ?",
                bindings: [.double(today.timeIntervalSince1970), .text(account.id.uuidString)]
            )
        }
        execute("COMMIT")
        reload()
    }

    func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            deleteAccount(accounts[index], reloadAfter: false)
        }
        reload()
    }

    func deleteAccount(_ account: Account) {
        deleteAccount(account, reloadAfter: true)
    }

    func addEntry(
        kind: EntryKind, category: String, note: String, amount: Double, date: Date, accountID: UUID
    ) {
        let category = normalized(category)
        guard !category.isEmpty else { return }
        _ = insertCategoryIfNeeded(category, icon: .tag, color: .blue)
        let entry = LedgerEntry(
            kind: kind,
            category: category,
            note: normalized(note),
            amount: amount,
            date: startOfDay(date),
            accountID: accountID
        )
        insertEntry(entry)
        reload()
    }

    func deleteEntries(at offsets: IndexSet, from matching: [LedgerEntry]) {
        for index in offsets {
            deleteEntry(matching[index], reloadAfter: false)
        }
        reload()
    }

    func deleteEntry(_ entry: LedgerEntry) {
        deleteEntry(entry, reloadAfter: true)
    }

    func addCategory(name: String, icon: CategoryIcon, color: CategoryColor) {
        guard insertCategoryIfNeeded(normalized(name), icon: icon, color: color) else { return }
        reload()
    }

    func updateCategory(
        _ category: LedgerCategory, name: String, icon: CategoryIcon, color: CategoryColor
    ) {
        let updatedName = normalized(name)
        guard !updatedName.isEmpty else { return }
        let hasNameConflict = categories.contains {
            $0.name.caseInsensitiveCompare(updatedName) == .orderedSame
                && $0.name.caseInsensitiveCompare(category.name) != .orderedSame
        }
        guard !hasNameConflict else { return }

        execute("BEGIN IMMEDIATE TRANSACTION")
        execute(
            "UPDATE entries SET category = ? WHERE lower(category) = lower(?)",
            bindings: [.text(updatedName), .text(category.name)]
        )
        execute(
            "UPDATE budgets SET category = ? WHERE lower(category) = lower(?)",
            bindings: [.text(updatedName), .text(category.name)]
        )
        execute(
            "UPDATE recurring SET category = ? WHERE lower(category) = lower(?)",
            bindings: [.text(updatedName), .text(category.name)]
        )
        execute(
            "UPDATE categories SET name = ?, icon = ?, color = ? WHERE lower(name) = lower(?)",
            bindings: [
                .text(updatedName), .text(icon.rawValue), .text(color.rawValue),
                .text(category.name),
            ]
        )
        execute("COMMIT")
        reload()
    }

    func deleteCategory(_ category: LedgerCategory) {
        guard category.name.caseInsensitiveCompare("Uncategorized") != .orderedSame else { return }
        _ = insertCategoryIfNeeded("Uncategorized", icon: .tag, color: .blue)
        execute(
            "UPDATE entries SET category = 'Uncategorized' WHERE lower(category) = lower(?)",
            bindings: [.text(category.name)]
        )
        execute(
            "DELETE FROM budgets WHERE lower(category) = lower(?)",
            bindings: [.text(category.name)])
        execute(
            "UPDATE recurring SET category = 'Uncategorized' WHERE lower(category) = lower(?)",
            bindings: [.text(category.name)])
        execute(
            "DELETE FROM categories WHERE lower(name) = lower(?)", bindings: [.text(category.name)])
        reload()
    }

    func deleteAllData() {
        execute("BEGIN IMMEDIATE TRANSACTION")
        execute("DELETE FROM entries")
        execute("DELETE FROM accounts")
        execute("DELETE FROM categories")
        execute("DELETE FROM settings")
        execute("DELETE FROM budgets")
        execute("DELETE FROM recurring")
        execute("DELETE FROM exchange_rates")
        execute("COMMIT")
        reload()
        registerCurrentUser()
    }

    func updateCurrency(_ currencyCode: String) {
        settings.currencyCode = currencyCode
        saveSettings()
    }

    func updateDateFormat(_ dateFormat: LedgerDateFormat) {
        settings.dateFormat = dateFormat
        saveSettings()
    }

    func updateTheme(_ theme: AppTheme) {
        settings.theme = theme
        saveSettings()
    }

    func updateFontSize(_ fontSize: AppFontSize) {
        settings.fontSize = fontSize
        saveSettings()
    }

    func updateDefaultImportedCategoryIcon(_ icon: CategoryIcon) {
        settings.defaultImportedCategoryIcon = icon
        saveSettings()
    }

    func updateDefaultImportedCategoryColor(_ color: CategoryColor) {
        settings.defaultImportedCategoryColor = color
        saveSettings()
    }

    func updateAutoLockMinutes(_ minutes: Int) {
        settings.autoLockMinutes = max(minutes, 0)
        saveSettings()
    }

    /// Registers the signed-in Mac user as the owner; call only after they verified their identity.
    func registerCurrentUser() {
        let username = NSUserName()
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        settings.ownerUsername = username
        settings.ownerName = fullName.isEmpty ? username : fullName
        saveSettings()
    }

    func balance(for account: Account) -> Double {
        account.openingBalance
            + entries
            .filter { $0.accountID == account.id }
            .reduce(0) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
    }

    var nextAvailableAccountColor: AccountColor {
        let usedColors = Set(accounts.map(\.color))
        return AccountColor.allCases.first(where: { !usedColors.contains($0) })
            ?? AccountColor.allCases[accounts.count % AccountColor.allCases.count]
    }

    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = settings.dateFormat.rawValue
        return formatter.string(from: date)
    }

    func importCSV(from url: URL) throws -> CSVImportSummary {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        let rows = CSVParser.rows(from: try String(contentsOf: url, encoding: .utf8))
        guard let headers = rows.first else { throw CSVImportError.emptyFile }
        let headerIndexes = Dictionary(
            uniqueKeysWithValues: headers.enumerated().map {
                ($1.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0)
            }
        )
        let requiredHeaders = ["flow", "account", "category", "amount", "description", "date"]
        guard requiredHeaders.allSatisfy({ headerIndexes[$0] != nil }) else {
            throw CSVImportError.invalidHeader
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        var accountLookup = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.name.lowercased(), $0) })
        var categoryNames = Set(categories.map { $0.name.lowercased() })
        var summary = CSVImportSummary(
            importedEntries: 0, createdAccounts: 0, createdCategories: 0, skippedRows: 0)
        // Multiset of existing entries, so re-importing a file adds nothing but genuine repeats still import.
        var existingKeys: [String: Int] = [:]
        for entry in entries {
            let key = entryKey(
                account: entry.accountID, kind: entry.kind, category: entry.category,
                amount: entry.amount, date: entry.date, note: entry.note)
            existingKeys[key, default: 0] += 1
        }
        var transferIDs: [String: UUID] = [:]

        for row in rows.dropFirst() {
            guard
                let flow = csvValue("flow", in: row, indexes: headerIndexes),
                let accountName = csvValue("account", in: row, indexes: headerIndexes),
                let categoryName = csvValue("category", in: row, indexes: headerIndexes),
                let rawAmount = csvValue("amount", in: row, indexes: headerIndexes),
                let note = csvValue("description", in: row, indexes: headerIndexes),
                let rawDate = csvValue("date", in: row, indexes: headerIndexes),
                let kind = entryKind(from: flow),
                let amount = number(from: rawAmount),
                let date = formatter.date(from: rawDate),
                !accountName.isEmpty,
                !categoryName.isEmpty
            else {
                summary.skippedRows += 1
                continue
            }

            let normalizedAccount = normalized(accountName)
            let normalizedCategory = normalized(categoryName)
            let account: Account
            if let existing = accountLookup[normalizedAccount.lowercased()] {
                account = existing
            } else {
                var newAccount = Account(
                    name: normalizedAccount,
                    type: .checking,
                    icon: .wallet,
                    color: nextAvailableAccountColor,
                    openingBalance: 0,
                    createdAt: date
                )
                newAccount.currencyCode = normalizedCurrency(
                    csvValue("currency", in: row, indexes: headerIndexes) ?? "")
                account = newAccount
                execute(
                    "INSERT INTO accounts (id, name, type, icon, color, opening_balance, created_at, currency) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    bindings: [
                        .text(account.id.uuidString), .text(account.name),
                        .text(account.type.rawValue),
                        .text(account.icon.rawValue), .text(account.color.rawValue), .double(0),
                        .double(account.createdAt.timeIntervalSince1970),
                        .text(account.currencyCode),
                    ]
                )
                accounts.append(account)
                accountLookup[normalizedAccount.lowercased()] = account
                summary.createdAccounts += 1
            }

            let key = entryKey(
                account: account.id, kind: kind, category: normalizedCategory, amount: amount,
                date: startOfDay(date), note: note)
            if let remaining = existingKeys[key], remaining > 0 {
                existingKeys[key] = remaining - 1
                summary.duplicateRows += 1
                continue
            }

            if !categoryNames.contains(normalizedCategory.lowercased()) {
                _ = insertCategoryIfNeeded(
                    normalizedCategory,
                    icon: settings.defaultImportedCategoryIcon,
                    color: settings.defaultImportedCategoryColor
                )
                categoryNames.insert(normalizedCategory.lowercased())
                summary.createdCategories += 1
            }

            var transferID: UUID?
            if let rawTransfer = csvValue("transferid", in: row, indexes: headerIndexes),
                !rawTransfer.isEmpty
            {
                transferID =
                    transferIDs[rawTransfer]
                    ?? {
                        let id = UUID(uuidString: rawTransfer) ?? UUID()
                        transferIDs[rawTransfer] = id
                        return id
                    }()
            }

            let entry = LedgerEntry(
                kind: kind,
                category: normalizedCategory,
                note: note,
                amount: amount,
                date: startOfDay(date),
                accountID: account.id,
                transferID: transferID
            )
            insertEntry(entry)
            summary.importedEntries += 1
        }

        reload()
        return summary
    }

    func openDatabase() {
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = databaseURL.path
        guard
            sqlite3_open_v2(
                path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil) == SQLITE_OK
        else {
            fatalError("Unable to open the local Saldo database.")
        }
    }

    func createTables() {
        execute(
            "CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, icon TEXT NOT NULL DEFAULT 'wallet.pass.fill', color TEXT NOT NULL DEFAULT 'blue', opening_balance REAL NOT NULL, created_at REAL NOT NULL)"
        )
        execute("ALTER TABLE accounts ADD COLUMN icon TEXT NOT NULL DEFAULT 'wallet.pass.fill'")
        execute("ALTER TABLE accounts ADD COLUMN color TEXT NOT NULL DEFAULT 'blue'")
        execute("ALTER TABLE accounts ADD COLUMN interest_rate REAL NOT NULL DEFAULT 0")
        execute("ALTER TABLE accounts ADD COLUMN interest_tax_rate REAL NOT NULL DEFAULT 0")
        execute("ALTER TABLE accounts ADD COLUMN interest_accrued_through REAL NOT NULL DEFAULT 0")
        execute(
            "CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL, category TEXT NOT NULL, note TEXT NOT NULL, amount REAL NOT NULL, date REAL NOT NULL, account_id TEXT NOT NULL)"
        )
        execute(
            "CREATE TABLE IF NOT EXISTS categories (name TEXT PRIMARY KEY, icon TEXT NOT NULL DEFAULT 'tag.fill', color TEXT NOT NULL DEFAULT 'blue')"
        )
        execute("ALTER TABLE categories ADD COLUMN icon TEXT NOT NULL DEFAULT 'tag.fill'")
        execute("ALTER TABLE categories ADD COLUMN color TEXT NOT NULL DEFAULT 'blue'")
        execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        execute("ALTER TABLE accounts ADD COLUMN currency TEXT NOT NULL DEFAULT ''")
        execute("ALTER TABLE entries ADD COLUMN transfer_id TEXT NOT NULL DEFAULT ''")
        execute("ALTER TABLE entries ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'")
        execute(
            "UPDATE entries SET source = 'interest' WHERE source = 'manual' AND category = 'Interest' AND note LIKE 'Daily interest (%'"
        )
        execute(
            "CREATE TABLE IF NOT EXISTS budgets (category TEXT PRIMARY KEY, monthly_limit REAL NOT NULL)"
        )
        execute(
            "CREATE TABLE IF NOT EXISTS recurring (id TEXT PRIMARY KEY, kind TEXT NOT NULL, category TEXT NOT NULL, note TEXT NOT NULL, amount REAL NOT NULL, account_id TEXT NOT NULL, to_account_id TEXT NOT NULL DEFAULT '', frequency TEXT NOT NULL, start_date REAL NOT NULL, end_date REAL NOT NULL DEFAULT 0, generated_count REAL NOT NULL DEFAULT 0, is_active REAL NOT NULL DEFAULT 1)"
        )
        execute(
            "CREATE TABLE IF NOT EXISTS exchange_rates (code TEXT PRIMARY KEY, rate REAL NOT NULL)"
        )
        execute(
            "INSERT OR IGNORE INTO categories (name, icon, color) SELECT DISTINCT category, 'tag.fill', 'blue' FROM entries WHERE trim(category) <> ''"
        )
    }

    func reload() {
        accounts = loadAccounts()
        entries = loadEntries()
        categories = loadCategories()
        loadSettings()
        budgets = loadBudgets()
        recurringRules = loadRecurringRules()
        exchangeRates = loadExchangeRates()
    }

    private func loadAccounts() -> [Account] {
        query(
            "SELECT id, name, type, icon, color, opening_balance, created_at, interest_rate, interest_tax_rate, interest_accrued_through, currency FROM accounts ORDER BY name"
        ) { statement in
            let accruedThrough = sqlite3_column_double(statement, 9)
            return Account(
                id: uuid(at: 0, from: statement),
                name: text(at: 1, from: statement),
                type: AccountType(rawValue: text(at: 2, from: statement)) ?? .checking,
                icon: AccountIcon(rawValue: text(at: 3, from: statement)) ?? .wallet,
                color: AccountColor(rawValue: text(at: 4, from: statement)) ?? .blue,
                openingBalance: sqlite3_column_double(statement, 5),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                interestRate: sqlite3_column_double(statement, 7),
                interestTaxRate: sqlite3_column_double(statement, 8),
                interestAccruedThrough: accruedThrough > 0
                    ? Date(timeIntervalSince1970: accruedThrough) : nil,
                currencyCode: text(at: 10, from: statement)
            )
        }
    }

    private func loadEntries() -> [LedgerEntry] {
        query(
            "SELECT id, kind, category, note, amount, date, account_id, transfer_id, source FROM entries ORDER BY date DESC"
        ) { statement in
            LedgerEntry(
                id: uuid(at: 0, from: statement),
                kind: EntryKind(rawValue: text(at: 1, from: statement)) ?? .expense,
                category: text(at: 2, from: statement),
                note: text(at: 3, from: statement),
                amount: sqlite3_column_double(statement, 4),
                date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                accountID: uuid(at: 6, from: statement),
                transferID: UUID(uuidString: text(at: 7, from: statement)),
                source: EntrySource(rawValue: text(at: 8, from: statement)) ?? .manual
            )
        }
    }

    private func loadCategories() -> [LedgerCategory] {
        query("SELECT name, icon, color FROM categories ORDER BY name COLLATE NOCASE") {
            statement in
            LedgerCategory(
                name: text(at: 0, from: statement),
                icon: CategoryIcon(rawValue: text(at: 1, from: statement)) ?? .tag,
                color: CategoryColor(rawValue: text(at: 2, from: statement)) ?? .blue
            )
        }
    }

    private func loadSettings() {
        let values = Dictionary(
            uniqueKeysWithValues: query("SELECT key, value FROM settings") { statement in
                (text(at: 0, from: statement), text(at: 1, from: statement))
            })
        guard !values.isEmpty else {
            settings = .default
            saveSettings()
            return
        }
        settings = AppSettings(
            currencyCode: values["currencyCode"] ?? AppSettings.default.currencyCode,
            dateFormat: LedgerDateFormat(rawValue: values["dateFormat"] ?? "")
                ?? AppSettings.default.dateFormat,
            theme: AppTheme(rawValue: values["theme"] ?? "") ?? AppSettings.default.theme,
            fontSize: AppFontSize(rawValue: values["fontSize"] ?? "")
                ?? AppSettings.default.fontSize,
            defaultImportedCategoryIcon: CategoryIcon(
                rawValue: values["defaultImportedCategoryIcon"] ?? "")
                ?? AppSettings.default.defaultImportedCategoryIcon,
            defaultImportedCategoryColor: CategoryColor(
                rawValue: values["defaultImportedCategoryColor"] ?? "")
                ?? AppSettings.default.defaultImportedCategoryColor,
            autoLockMinutes: Int(values["autoLockMinutes"] ?? "")
                ?? AppSettings.default.autoLockMinutes,
            ownerUsername: values["ownerUsername"] ?? "",
            ownerName: values["ownerName"] ?? ""
        )
    }

    private func saveSettings() {
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [.text("currencyCode"), .text(settings.currencyCode)])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [.text("dateFormat"), .text(settings.dateFormat.rawValue)])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [.text("theme"), .text(settings.theme.rawValue)])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [.text("fontSize"), .text(settings.fontSize.rawValue)])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [
                .text("defaultImportedCategoryIcon"),
                .text(settings.defaultImportedCategoryIcon.rawValue),
            ])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [
                .text("defaultImportedCategoryColor"),
                .text(settings.defaultImportedCategoryColor.rawValue),
            ])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [.text("autoLockMinutes"), .text(String(settings.autoLockMinutes))])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [.text("ownerUsername"), .text(settings.ownerUsername)])
        execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            bindings: [.text("ownerName"), .text(settings.ownerName)])
    }

    private func deleteAccount(_ account: Account, reloadAfter: Bool) {
        execute(
            "DELETE FROM entries WHERE account_id = ?", bindings: [.text(account.id.uuidString)])
        execute("DELETE FROM accounts WHERE id = ?", bindings: [.text(account.id.uuidString)])
        execute(
            "DELETE FROM recurring WHERE account_id = ? OR to_account_id = ?",
            bindings: [.text(account.id.uuidString), .text(account.id.uuidString)])
        if reloadAfter { reload() }
    }

    private func deleteEntry(_ entry: LedgerEntry, reloadAfter: Bool) {
        if let transferID = entry.transferID {
            execute(
                "DELETE FROM entries WHERE transfer_id = ?",
                bindings: [.text(transferID.uuidString)])
        } else {
            execute("DELETE FROM entries WHERE id = ?", bindings: [.text(entry.id.uuidString)])
        }
        if reloadAfter { reload() }
    }

    func insertCategoryIfNeeded(
        _ name: String, icon: CategoryIcon, color: CategoryColor
    ) -> Bool {
        guard !name.isEmpty else { return false }
        execute(
            "INSERT OR IGNORE INTO categories (name, icon, color) VALUES (?, ?, ?)",
            bindings: [.text(name), .text(icon.rawValue), .text(color.rawValue)]
        )
        return sqlite3_changes(database) > 0
    }

    func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedCurrency(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func entryKey(
        account: UUID, kind: EntryKind, category: String, amount: Double, date: Date, note: String
    ) -> String {
        let cents = Int((amount * 100).rounded())
        return
            "\(account.uuidString)|\(kind.rawValue)|\(category.lowercased())|\(cents)|\(Int(date.timeIntervalSince1970))|\(note.lowercased())"
    }

    func insertEntry(_ entry: LedgerEntry) {
        execute(
            "INSERT INTO entries (id, kind, category, note, amount, date, account_id, transfer_id, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(entry.id.uuidString), .text(entry.kind.rawValue), .text(entry.category),
                .text(entry.note), .double(entry.amount), .double(entry.date.timeIntervalSince1970),
                .text(entry.accountID.uuidString), .text(entry.transferID?.uuidString ?? ""),
                .text(entry.source.rawValue),
            ]
        )
    }

    private func csvValue(_ name: String, in row: [String], indexes: [String: Int]) -> String? {
        guard let index = indexes[name], row.indices.contains(index) else { return nil }
        return normalized(row[index])
    }

    private func entryKind(from text: String) -> EntryKind? {
        EntryKind(rawValue: text.capitalized)
    }

    private func number(from text: String) -> Double? {
        Double(
            normalized(text).replacingOccurrences(of: " ", with: "").replacingOccurrences(
                of: ",", with: "."))
    }

    func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func dayBefore(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: startOfDay(date)) ?? date
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(bindings, to: statement)
        _ = sqlite3_step(statement)
    }

    func query<Value>(_ sql: String, transform: (OpaquePointer) -> Value) -> [Value] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [Value] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let statement { results.append(transform(statement)) }
        }
        return results
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) {
        for (offset, value) in values.enumerated() {
            switch value {
            case .text(let text):
                sqlite3_bind_text(statement, Int32(offset + 1), text, -1, sqliteTransient)
            case .double(let double):
                sqlite3_bind_double(statement, Int32(offset + 1), double)
            }
        }
    }

    func uuid(at index: Int32, from statement: OpaquePointer) -> UUID {
        UUID(uuidString: text(at: index, from: statement)) ?? UUID()
    }

    func text(at index: Int32, from statement: OpaquePointer) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
}

enum SQLiteValue {
    case text(String)
    case double(Double)
}

private enum CSVImportError: LocalizedError {
    case emptyFile
    case invalidHeader

    var errorDescription: String? {
        switch self {
        case .emptyFile: "The CSV file is empty."
        case .invalidHeader:
            "The CSV header must include Flow, Account, Category, Amount, Description, and Date."
        }
    }
}

private enum CSVParser {
    static func rows(from text: String) -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r", !isQuoted {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension Account {
    fileprivate init(
        id: UUID, name: String, type: AccountType, icon: AccountIcon, color: AccountColor,
        openingBalance: Double, createdAt: Date, interestRate: Double, interestTaxRate: Double,
        interestAccruedThrough: Date?, currencyCode: String
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.color = color
        self.openingBalance = openingBalance
        self.createdAt = createdAt
        self.interestRate = interestRate
        self.interestTaxRate = interestTaxRate
        self.interestAccruedThrough = interestAccruedThrough
        self.currencyCode = currencyCode
    }
}

extension LedgerEntry {
    fileprivate init(
        id: UUID, kind: EntryKind, category: String, note: String, amount: Double, date: Date,
        accountID: UUID, transferID: UUID?, source: EntrySource
    ) {
        self.id = id
        self.kind = kind
        self.category = category
        self.note = note
        self.amount = amount
        self.date = date
        self.accountID = accountID
        self.transferID = transferID
        self.source = source
    }
}
