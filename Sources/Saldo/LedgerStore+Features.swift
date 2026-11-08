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
        Set(
            (accounts.map(currencyCode(for:)) + debts.map(currencyCode(for:))).filter {
                $0 != settings.currencyCode
            }
        ).sorted()
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

    /// Cash and checking, in the app currency. Bills do not change this.
    var availableCash: Double {
        accounts
            .filter { $0.type == .cash || $0.type == .checking }
            .reduce(0) { $0 + baseBalance(for: $1) }
    }

    var totalBalance: Double {
        accounts.reduce(0) { $0 + baseBalance(for: $1) }
    }

    /// Account balances, minus what you still owe, plus what is still owed to you.
    var netWorth: Double {
        netWorth(before: .distantFuture)
    }

    func netWorth(before date: Date) -> Double {
        let cash = accounts.filter(\.countsInNetWorth).reduce(0) {
            $0 + toBase(balance(for: $1, before: date), in: currencyCode(for: $1))
        }
        return cash + debts.reduce(0) { $0 + signedRemaining(for: $1, before: date) }
    }

    func balance(for account: Account, before date: Date) -> Double {
        account.openingBalance
            + entries
            .filter { $0.accountID == account.id && $0.date < date && countsTowardBalance($0) }
            .reduce(0) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
    }

    var openAccounts: [Account] {
        accounts.filter { !$0.isClosed }
    }

    /// Keeps a closed account in a picker when an existing record already uses it.
    func includingSelection(_ id: UUID?, in preferred: [Account]) -> [Account] {
        guard let id,
            !preferred.contains(where: { $0.id == id }),
            let account = accounts.first(where: { $0.id == id }),
            account.isClosed
        else { return preferred }
        return [account] + preferred
    }

    /// Manual entries only, so automatic rows do not crowd out the accounts you actually pick.
    var accountsByUsage: [Account] {
        var counts: [UUID: Int] = [:]
        for entry in entries where entry.source == .manual {
            counts[entry.accountID, default: 0] += 1
        }
        return accounts.enumerated()
            .filter { !$0.element.isClosed }
            .sorted { lhs, rhs in
                let left = counts[lhs.element.id] ?? 0
                let right = counts[rhs.element.id] ?? 0
                if left != right { return left > right }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
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
        date: Date, accountID: UUID, spareChangeAccountID: UUID? = nil,
        countsInAvailable: Bool = true
    ) {
        let category = normalized(category)
        guard !category.isEmpty else { return }
        let day = startOfDay(date)
        let normalizedNote = normalized(note)
        let spare = kind == .expense ? spareChange(for: amount) : 0
        let received =
            spareChangeAccountID.map { convertedTransferAmount(spare, from: accountID, to: $0) } ?? 0
        let wantsSpareChange =
            spare > 0 && received > 0 && spareChangeAccountID != accountID
            && accounts.contains { $0.id == spareChangeAccountID && $0.type == .savings }
        let existingTransferID = spareChangeLegs(for: entry)?.source.transferID

        execute("BEGIN IMMEDIATE TRANSACTION")
        _ = insertCategoryIfNeeded(category, icon: .tag, color: .blue)
        let linkedTransferID: UUID?
        if wantsSpareChange, let spareChangeAccountID {
            let spareNote =
                normalizedNote.isEmpty ? "Spare change" : "Spare change for \(normalizedNote)"
            if let existingTransferID {
                updateSpareChangeTransfer(
                    existingTransferID, from: accountID, to: spareChangeAccountID, amount: spare,
                    receivedAmount: received, date: day, note: spareNote)
                linkedTransferID = existingTransferID
            } else {
                linkedTransferID = insertTransferLegs(
                    from: accountID, to: spareChangeAccountID, amount: spare,
                    receivedAmount: received, date: day, note: spareNote, source: .manual)
            }
        } else {
            if let existingTransferID {
                execute(
                    "DELETE FROM entries WHERE transfer_id = ?",
                    bindings: [.text(existingTransferID.uuidString)])
            }
            linkedTransferID = nil
        }
        let nextDebtAmount = refreshedDebtAmount(for: entry, amount: amount, accountID: accountID)
        execute(
            "UPDATE entries SET kind = ?, category = ?, note = ?, amount = ?, date = ?, account_id = ?, spare_change_id = ?, debt_amount = ?, counts_in_available = ? WHERE id = ?",
            bindings: [
                .text(kind.rawValue), .text(category), .text(normalizedNote), .double(amount),
                .double(day.timeIntervalSince1970), .text(accountID.uuidString),
                .text(linkedTransferID?.uuidString ?? ""), .double(nextDebtAmount),
                .double(countsInAvailable ? 1 : 0), .text(entry.id.uuidString),
            ]
        )
        execute("COMMIT")
        reload()
    }

    /// The spare-change transfer for an expense, including ones saved before they were linked.
    func spareChangeLegs(
        for entry: LedgerEntry
    ) -> (source: LedgerEntry, destination: LedgerEntry)? {
        guard entry.kind == .expense, !entry.isTransfer else { return nil }
        if let id = entry.spareChangeTransferID {
            let legs = entries.filter { $0.transferID == id }
            if let source = legs.first(where: { $0.kind == .expense }),
                let destination = legs.first(where: { $0.kind == .income })
            {
                return (source, destination)
            }
        }
        let spare = spareChange(for: entry.amount)
        guard spare > 0 else { return nil }
        let day = startOfDay(entry.date)
        let claimed = Set(entries.compactMap(\.spareChangeTransferID))
        guard
            let source = entries.first(where: { candidate in
                guard candidate.kind == .expense, let transferID = candidate.transferID else {
                    return false
                }
                guard !claimed.contains(transferID), candidate.accountID == entry.accountID else {
                    return false
                }
                guard startOfDay(candidate.date) == day, abs(candidate.amount - spare) < 0.001 else {
                    return false
                }
                // Older notes used "Spare change · Note"; newer ones "Spare change for Note".
                return candidate.note == "Spare change"
                    || candidate.note.hasPrefix("Spare change for ")
                    || candidate.note.hasPrefix("Spare change \u{00B7} ")
            }),
            let transferID = source.transferID,
            let destination = entries.first(where: {
                $0.transferID == transferID && $0.kind == .income
            })
        else { return nil }
        return (source, destination)
    }

    private func updateSpareChangeTransfer(
        _ transferID: UUID, from sourceID: UUID, to destinationID: UUID, amount: Double,
        receivedAmount: Double, date: Date, note: String
    ) {
        let day = date.timeIntervalSince1970
        execute(
            "UPDATE entries SET account_id = ?, amount = ?, date = ?, note = ? WHERE transfer_id = ? AND kind = ?",
            bindings: [
                .text(sourceID.uuidString), .double(amount), .double(day), .text(note),
                .text(transferID.uuidString), .text(EntryKind.expense.rawValue),
            ])
        execute(
            "UPDATE entries SET account_id = ?, amount = ?, date = ?, note = ? WHERE transfer_id = ? AND kind = ?",
            bindings: [
                .text(destinationID.uuidString), .double(receivedAmount), .double(day), .text(note),
                .text(transferID.uuidString), .text(EntryKind.income.rawValue),
            ])
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

    @discardableResult
    func insertTransferLegs(
        from sourceID: UUID, to destinationID: UUID, amount: Double, receivedAmount: Double,
        date: Date, note: String, source: EntrySource
    ) -> UUID {
        let id = UUID()
        insertEntry(
            LedgerEntry(
                kind: .expense, category: "Transfer", note: note, amount: amount, date: date,
                accountID: sourceID, transferID: id, source: source))
        insertEntry(
            LedgerEntry(
                kind: .income, category: "Transfer", note: note, amount: receivedAmount, date: date,
                accountID: destinationID, transferID: id, source: source))
        return id
    }
}

// MARK: - Export, backup and restore

extension LedgerStore {
    /// Finds a plaintext database left by an older version. An encrypted file is never replaced by it.
    static func resolveDatabaseURL(applicationSupport: URL) -> URL {
        let manager = FileManager.default
        let folder = supportFolder(applicationSupport: applicationSupport)
        let current = folder.appendingPathComponent("saldo.sqlite")
        let sealed = folder.appendingPathComponent("saldo.sealed")
        let legacy = applicationSupport.appendingPathComponent("Ledger", isDirectory: true)
            .appendingPathComponent("ledger.sqlite")
        if manager.fileExists(atPath: current.path) || manager.fileExists(atPath: sealed.path) {
            return current
        }
        guard manager.fileExists(atPath: legacy.path) else { return current }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
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
        try persist()
        let data = try Data(contentsOf: sealedURL)
        try data.write(to: url, options: .atomic)
    }

    func restoreDatabase(from url: URL) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        if DatabaseSeal.isSealed(data) {
            guard databaseKey != nil else {
                throw StoreError.message("Unlock Saldo before restoring a backup.")
            }
            _ = try DatabaseSeal.open(data, using: databaseKey!)
            try swapInSnapshot {
                try self.installSnapshot(try DatabaseSeal.open(data, using: self.databaseKey!))
            }
            return
        }
        let plain = try plaintextSnapshot(from: url)
        try swapInSnapshot {
            try self.installSnapshot(plain)
        }
    }

    private func swapInSnapshot(_ install: () throws -> Void) throws {
        try persist()
        try? FileManager.default.removeItem(at: safetyBackupURL)
        try FileManager.default.copyItem(at: sealedURL, to: safetyBackupURL)
        let wasSuspended = writesSuspended
        writesSuspended = true
        defer { writesSuspended = wasSuspended }
        sqlite3_close(database)
        database = nil
        do {
            try openMemoryDatabase()
            try install()
            createTables()
            reload()
            try persist()
        } catch {
            sqlite3_close(database)
            database = nil
            try? openMemoryDatabase()
            if FileManager.default.fileExists(atPath: safetyBackupURL.path), let databaseKey {
                let safety = try Data(contentsOf: safetyBackupURL)
                try? installSnapshot(try DatabaseSeal.open(safety, using: databaseKey))
                createTables()
                reload()
                try? persist()
            }
            throw error
        }
    }

    private func plaintextSnapshot(from url: URL) throws -> Data {
        var probe: OpaquePointer?
        guard sqlite3_open_v2(url.path, &probe, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(probe)
            throw StoreError.message("The selected file is not a readable database.")
        }
        defer { sqlite3_close(probe) }
        var statement: OpaquePointer?
        let isLedger =
            sqlite3_prepare_v2(
                probe,
                "SELECT count(*) FROM sqlite_master WHERE name IN ('accounts', 'entries')", -1,
                &statement, nil) == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW
            && sqlite3_column_int(statement, 0) == 2
        sqlite3_finalize(statement)
        guard isLedger else {
            throw StoreError.message("The selected file is not a Saldo backup.")
        }
        var size: sqlite3_int64 = 0
        guard let pointer = sqlite3_serialize(probe, "main", &size, 0) else {
            throw StoreError.message("The selected file is not a Saldo backup.")
        }
        defer { sqlite3_free(pointer) }
        return Data(bytes: pointer, count: Int(size))
    }

    private func csvEscaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
