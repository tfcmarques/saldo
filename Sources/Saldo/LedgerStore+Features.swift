import Foundation
import SQLite3

enum StoreError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

// MARK: - Currency

extension LedgerStore {
    func currencyCode(for account: Account) -> String {
        account.currencyCode.isEmpty ? settings.currencyCode : account.currencyCode
    }

    func currencyCode(forAccountID id: UUID) -> String {
        accounts.first { $0.id == id }.map(currencyCode(for:)) ?? settings.currencyCode
    }

    func rate(for code: String) -> Double {
        code == settings.currencyCode ? 1 : (exchangeRates[code] ?? 1)
    }

    /// Foreign currencies in use that still have no exchange rate.
    var currenciesMissingRate: [String] {
        foreignCurrencies.filter { exchangeRates[$0] == nil }
    }

    var foreignCurrencies: [String] {
        Set(accounts.map(currencyCode(for:)).filter { $0 != settings.currencyCode }).sorted()
    }

    func toBase(_ amount: Double, in code: String) -> Double {
        amount * rate(for: code)
    }

    func toBase(_ amount: Double, accountID: UUID) -> Double {
        toBase(amount, in: currencyCode(forAccountID: accountID))
    }

    func baseBalance(for account: Account) -> Double {
        toBase(balance(for: account), in: currencyCode(for: account))
    }

    var totalBalance: Double {
        accounts.reduce(0) { $0 + baseBalance(for: $1) }
    }

    func signedAmount(_ entry: LedgerEntry) -> Double {
        entry.kind == .income ? entry.amount : -entry.amount
    }

    func setExchangeRate(code: String, rate: Double) {
        let code = normalizedCurrency(code)
        guard !code.isEmpty else { return }
        if rate > 0 {
            execute(
                "INSERT OR REPLACE INTO exchange_rates (code, rate) VALUES (?, ?)",
                bindings: [.text(code), .double(rate)])
        } else {
            execute("DELETE FROM exchange_rates WHERE code = ?", bindings: [.text(code)])
        }
        reload()
    }

    func loadExchangeRates() -> [String: Double] {
        Dictionary(
            query("SELECT code, rate FROM exchange_rates") { statement in
                (text(at: 0, from: statement), sqlite3_column_double(statement, 1))
            },
            uniquingKeysWith: { $1 })
    }
}

// MARK: - Entries and transfers

extension LedgerStore {
    func updateEntry(
        _ entry: LedgerEntry, kind: EntryKind, category: String, note: String, amount: Double,
        date: Date, accountID: UUID
    ) {
        let category = normalized(category)
        guard !category.isEmpty else { return }
        _ = insertCategoryIfNeeded(category, icon: .tag, color: .blue)
        execute(
            "UPDATE entries SET kind = ?, category = ?, note = ?, amount = ?, date = ?, account_id = ? WHERE id = ?",
            bindings: [
                .text(kind.rawValue), .text(category), .text(normalized(note)), .double(amount),
                .double(startOfDay(date).timeIntervalSince1970), .text(accountID.uuidString),
                .text(entry.id.uuidString),
            ]
        )
        reload()
    }

    func convertedTransferAmount(_ amount: Double, from: UUID, to: UUID) -> Double {
        let fromCode = currencyCode(forAccountID: from)
        let toCode = currencyCode(forAccountID: to)
        guard fromCode != toCode else { return amount }
        return amount * rate(for: fromCode) / rate(for: toCode)
    }

    func transferLegs(of entry: LedgerEntry) -> (source: LedgerEntry, destination: LedgerEntry)? {
        guard let id = entry.transferID else { return nil }
        let legs = entries.filter { $0.transferID == id }
        guard let source = legs.first(where: { $0.kind == .expense }),
            let destination = legs.first(where: { $0.kind == .income })
        else { return nil }
        return (source, destination)
    }

    func addTransfer(
        from sourceID: UUID, to destinationID: UUID, amount: Double, receivedAmount: Double,
        date: Date, note: String
    ) {
        guard sourceID != destinationID, amount > 0, receivedAmount > 0 else { return }
        _ = insertCategoryIfNeeded("Transfer", icon: .transfer, color: .teal)
        insertTransferLegs(
            from: sourceID, to: destinationID, amount: amount, receivedAmount: receivedAmount,
            date: startOfDay(date), note: normalized(note), source: .manual)
        reload()
    }

    func updateTransfer(
        _ entry: LedgerEntry, from sourceID: UUID, to destinationID: UUID, amount: Double,
        receivedAmount: Double, date: Date, note: String
    ) {
        guard sourceID != destinationID, amount > 0, receivedAmount > 0,
            let legs = transferLegs(of: entry)
        else { return }
        let day = startOfDay(date).timeIntervalSince1970
        execute(
            "UPDATE entries SET account_id = ?, amount = ?, date = ?, note = ? WHERE id = ?",
            bindings: [
                .text(sourceID.uuidString), .double(amount), .double(day),
                .text(normalized(note)), .text(legs.source.id.uuidString),
            ])
        execute(
            "UPDATE entries SET account_id = ?, amount = ?, date = ?, note = ? WHERE id = ?",
            bindings: [
                .text(destinationID.uuidString), .double(receivedAmount), .double(day),
                .text(normalized(note)), .text(legs.destination.id.uuidString),
            ])
        reload()
    }

    func insertTransferLegs(
        from sourceID: UUID, to destinationID: UUID, amount: Double, receivedAmount: Double,
        date: Date, note: String, source: EntrySource
    ) {
        let id = UUID()
        insertEntry(
            LedgerEntry(
                kind: .expense, category: "Transfer", note: note, amount: amount, date: date,
                accountID: sourceID, transferID: id, source: source))
        insertEntry(
            LedgerEntry(
                kind: .income, category: "Transfer", note: note, amount: receivedAmount, date: date,
                accountID: destinationID, transferID: id, source: source))
    }
}

// MARK: - Budgets

extension LedgerStore {
    func loadBudgets() -> [Budget] {
        query("SELECT category, monthly_limit FROM budgets ORDER BY category COLLATE NOCASE") {
            statement in
            Budget(
                category: text(at: 0, from: statement),
                monthlyLimit: sqlite3_column_double(statement, 1))
        }
    }

    func setBudget(category: String, monthlyLimit: Double) {
        let category = normalized(category)
        guard !category.isEmpty else { return }
        if monthlyLimit > 0 {
            execute(
                "INSERT OR REPLACE INTO budgets (category, monthly_limit) VALUES (?, ?)",
                bindings: [.text(category), .double(monthlyLimit)])
        } else {
            execute("DELETE FROM budgets WHERE category = ?", bindings: [.text(category)])
        }
        reload()
    }

    func deleteBudget(_ budget: Budget) {
        execute("DELETE FROM budgets WHERE category = ?", bindings: [.text(budget.category)])
        reload()
    }

    /// Expenses in the base currency for the month containing `date`; transfers are excluded.
    func spent(in category: String, during date: Date = .now) -> Double {
        guard let month = Calendar.current.dateInterval(of: .month, for: date) else { return 0 }
        return
            entries
            .filter {
                $0.kind == .expense && !$0.isTransfer
                    && $0.category.caseInsensitiveCompare(category) == .orderedSame
                    && month.contains($0.date)
            }
            .reduce(0) { $0 + toBase($1.amount, accountID: $1.accountID) }
    }
}

// MARK: - Recurring entries

extension LedgerStore {
    func loadRecurringRules() -> [RecurringRule] {
        query(
            "SELECT id, kind, category, note, amount, account_id, to_account_id, frequency, start_date, end_date, generated_count, is_active FROM recurring ORDER BY start_date"
        ) { statement in
            let endDate = sqlite3_column_double(statement, 9)
            return RecurringRule(
                id: uuid(at: 0, from: statement),
                kind: RecurringKind(rawValue: text(at: 1, from: statement)) ?? .expense,
                category: text(at: 2, from: statement),
                note: text(at: 3, from: statement),
                amount: sqlite3_column_double(statement, 4),
                accountID: uuid(at: 5, from: statement),
                toAccountID: UUID(uuidString: text(at: 6, from: statement)),
                frequency: RecurrenceFrequency(rawValue: text(at: 7, from: statement)) ?? .monthly,
                startDate: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                endDate: endDate > 0 ? Date(timeIntervalSince1970: endDate) : nil,
                generatedCount: Int(sqlite3_column_double(statement, 10)),
                isActive: sqlite3_column_double(statement, 11) != 0
            )
        }
    }

    func saveRecurringRule(_ rule: RecurringRule) {
        var rule = rule
        rule.category = rule.kind == .transfer ? "Transfer" : normalized(rule.category)
        rule.startDate = startOfDay(rule.startDate)
        guard rule.amount > 0, rule.kind == .transfer || !rule.category.isEmpty else { return }
        execute(
            "INSERT OR REPLACE INTO recurring (id, kind, category, note, amount, account_id, to_account_id, frequency, start_date, end_date, generated_count, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(rule.id.uuidString), .text(rule.kind.rawValue), .text(rule.category),
                .text(normalized(rule.note)), .double(rule.amount),
                .text(rule.accountID.uuidString),
                .text(rule.toAccountID?.uuidString ?? ""), .text(rule.frequency.rawValue),
                .double(rule.startDate.timeIntervalSince1970),
                .double(rule.endDate.map { startOfDay($0).timeIntervalSince1970 } ?? 0),
                .double(Double(rule.generatedCount)), .double(rule.isActive ? 1 : 0),
            ]
        )
        reload()
        generateRecurringEntries()
    }

    func deleteRecurringRule(_ rule: RecurringRule) {
        execute("DELETE FROM recurring WHERE id = ?", bindings: [.text(rule.id.uuidString)])
        reload()
    }

    func occurrence(_ index: Int, of rule: RecurringRule) -> Date? {
        let calendar = Calendar.current
        switch rule.frequency {
        case .daily: return calendar.date(byAdding: .day, value: index, to: rule.startDate)
        case .weekly: return calendar.date(byAdding: .day, value: index * 7, to: rule.startDate)
        case .monthly: return calendar.date(byAdding: .month, value: index, to: rule.startDate)
        case .yearly: return calendar.date(byAdding: .year, value: index, to: rule.startDate)
        }
    }

    func nextOccurrence(of rule: RecurringRule) -> Date? {
        guard let date = occurrence(rule.generatedCount, of: rule) else { return nil }
        if let endDate = rule.endDate, date > endDate { return nil }
        return date
    }

    /// Creates every missed occurrence up to today for active rules.
    func generateRecurringEntries(through endDate: Date = .now) {
        let today = startOfDay(endDate)
        let due = recurringRules.filter { rule in
            guard rule.isActive, let next = nextOccurrence(of: rule) else { return false }
            return next <= today
        }
        guard !due.isEmpty else { return }

        execute("BEGIN IMMEDIATE TRANSACTION")
        for var rule in due {
            guard accounts.contains(where: { $0.id == rule.accountID }) else { continue }
            var created = 0
            while let date = nextOccurrence(of: rule), date <= today, created < 5000 {
                createEntries(for: rule, on: date)
                rule.generatedCount += 1
                created += 1
            }
            execute(
                "UPDATE recurring SET generated_count = ? WHERE id = ?",
                bindings: [.double(Double(rule.generatedCount)), .text(rule.id.uuidString)])
        }
        execute("COMMIT")
        reload()
    }

    private func createEntries(for rule: RecurringRule, on date: Date) {
        switch rule.kind {
        case .transfer:
            guard let destination = rule.toAccountID,
                accounts.contains(where: { $0.id == destination })
            else { return }
            _ = insertCategoryIfNeeded("Transfer", icon: .transfer, color: .teal)
            insertTransferLegs(
                from: rule.accountID, to: destination, amount: rule.amount,
                receivedAmount: convertedTransferAmount(
                    rule.amount, from: rule.accountID, to: destination),
                date: date, note: rule.note, source: .recurring)
        case .expense, .income:
            _ = insertCategoryIfNeeded(rule.category, icon: .tag, color: .blue)
            insertEntry(
                LedgerEntry(
                    kind: rule.kind == .income ? .income : .expense, category: rule.category,
                    note: rule.note, amount: rule.amount, date: date, accountID: rule.accountID,
                    source: .recurring))
        }
    }
}

// MARK: - Export, backup and restore

extension LedgerStore {
    static var defaultDatabaseURL: URL {
        resolveDatabaseURL(
            applicationSupport: FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    /// Moves data from the pre-rename Ledger folder; the old file is copied, never deleted.
    static func resolveDatabaseURL(applicationSupport: URL) -> URL {
        let manager = FileManager.default
        let current = applicationSupport.appendingPathComponent("Saldo", isDirectory: true)
            .appendingPathComponent("saldo.sqlite")
        let legacy = applicationSupport.appendingPathComponent("Ledger", isDirectory: true)
            .appendingPathComponent("ledger.sqlite")
        guard !manager.fileExists(atPath: current.path), manager.fileExists(atPath: legacy.path)
        else { return current }
        do {
            try manager.createDirectory(
                at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: legacy, to: current)
            return current
        } catch {
            // Never start on an empty database when the old data could not be copied.
            return legacy
        }
    }

    func exportCSV() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        var lines = ["Flow,Account,Category,Amount,Description,Date,Currency,TransferID"]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let account = accountsByID[entry.accountID]
            let amount = String(format: "%.4f", entry.amount)
                .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
            let fields = [
                entry.kind.rawValue, account?.name ?? "", entry.category, amount, entry.note,
                formatter.string(from: entry.date), account?.currencyCode ?? "",
                entry.transferID?.uuidString ?? "",
            ]
            lines.append(fields.map(csvEscaped).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func exportCSV(to url: URL) throws {
        try exportCSV().write(to: url, atomically: true, encoding: .utf8)
    }

    func backupDatabase(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let escaped = url.path.replacingOccurrences(of: "'", with: "''")
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard
            sqlite3_exec(database, "VACUUM INTO '\(escaped)'", nil, nil, &errorMessage) == SQLITE_OK
        else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw StoreError.message("Backup failed: \(message)")
        }
    }

    func restoreDatabase(from url: URL) throws {
        var probe: OpaquePointer?
        guard sqlite3_open_v2(url.path, &probe, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(probe)
            throw StoreError.message("The selected file is not a readable database.")
        }
        var statement: OpaquePointer?
        let isLedger =
            sqlite3_prepare_v2(
                probe,
                "SELECT count(*) FROM sqlite_master WHERE name IN ('accounts', 'entries')", -1,
                &statement, nil) == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW
            && sqlite3_column_int(statement, 0) == 2
        sqlite3_finalize(statement)
        sqlite3_close(probe)
        guard isLedger else {
            throw StoreError.message("The selected file is not a Saldo backup.")
        }

        // Keep the current data recoverable in case the restore was a mistake.
        let safety = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("saldo-before-restore.sqlite")
        try backupDatabase(to: safety)

        sqlite3_close(database)
        database = nil
        let destination = databaseURL
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        openDatabase()
        createTables()
        reload()
        registerCurrentUser()
    }

    private func csvEscaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
