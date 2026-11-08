import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import SQLite3

@Observable
final class LedgerStore {
    var database: OpaquePointer?
    var accounts: [Account] = []
    var debts: [Debt] = []
    var bills: [Bill] = []
    var entries: [LedgerEntry] = []
    var categories: [LedgerCategory] = []
    /// Base-currency value of one unit of each foreign currency.
    var exchangeRates: [String: Double] = [:]
    private(set) var settings: AppSettings = .default
    var saveError: String?
    let sealedURL: URL
    let plaintextURL: URL
    var databaseKey: SymmetricKey?
    var writesSuspended = false
    private var suppressBackup = false
    private var transactionDepth = 0
    private var transactionFailed = false
    @ObservationIgnored private let dateFormatter = DateFormatter()
    private var pendingRecoveryNote: String?

    var hasExistingDatabase: Bool {
        let files = FileManager.default
        return files.fileExists(atPath: sealedURL.path) || files.fileExists(atPath: plaintextURL.path)
    }

    var latestAutomaticBackupLabel: String? {
        let folder = backupFolder
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        let newest = files.filter { $0.pathExtension == "sealed" }.max { lhs, rhs in
            modificationDate(of: lhs) < modificationDate(of: rhs)
        }
        guard let newest else { return nil }
        return modificationDate(of: newest).formatted(date: .abbreviated, time: .omitted)
    }

    init() {
        let support = TestDataMode.applicationSupport
        sealedURL = Self.supportFolder(applicationSupport: support).appendingPathComponent(
            "saldo.sealed")
        plaintextURL = Self.resolveDatabaseURL(applicationSupport: support)
        if let cached = Self.loadCachedSettings() {
            settings = cached
        }
        if settings.ownerUsername.isEmpty, let peeked = Self.readSettings(at: plaintextURL) {
            settings = peeked
            cacheSettings()
        }
    }

    deinit {
        if database != nil {
            try? persist()
            sqlite3_close(database)
        }
    }

    /// Decrypts the database into memory. Nothing is loaded until unlock succeeds.
    func open(using context: LAContext?) -> String? {
        guard database == nil else { return nil }
        guard context != nil else { return "Unlock Saldo to open the database." }
        writesSuspended = true
        defer { writesSuspended = false }
        do {
            let sealedFileExists = FileManager.default.fileExists(atPath: sealedURL.path)
            databaseKey = try DatabaseKeystore.loadOrCreate(
                createIfMissing: !sealedFileExists,
                directory: sealedURL.deletingLastPathComponent())
            try openMemoryDatabase()
            if FileManager.default.fileExists(atPath: sealedURL.path)
                || FileManager.default.fileExists(atPath: backupFolder.path)
            {
                try loadNewestReadableSnapshot()
            } else if FileManager.default.fileExists(atPath: plaintextURL.path) {
                try loadPlaintextSnapshot()
            }
            createTables()
            reload()
            seedSampleDataIfEmpty()
            try persist()
            if let pendingRecoveryNote {
                saveError = pendingRecoveryNote
                self.pendingRecoveryNote = nil
            }
            return nil
        } catch {
            tearDownMemory()
            return error.localizedDescription
        }
    }

    /// Writes the encrypted file, then drops the in-memory database and its key.
    func close() -> String? {
        guard database != nil else { return nil }
        do {
            try persist()
        } catch {
            return error.localizedDescription
        }
        tearDownMemory()
        return nil
    }

    func addAccount(
        name: String,
        type: AccountType,
        icon: AccountIcon = .wallet,
        color: AccountColor? = nil,
        openingBalance: Double,
        currencyCode: String = "",
        countsInNetWorth: Bool = true
    ) {
        var account = Account(
            name: name,
            type: type,
            icon: icon,
            color: color ?? nextAvailableAccountColor,
            openingBalance: openingBalance
        )
        account.currencyCode = normalizedCurrency(currencyCode)
        account.countsInNetWorth = countsInNetWorth
        execute(
            "INSERT INTO accounts (id, name, type, icon, color, opening_balance, created_at, currency, sort_order, counts_in_net_worth) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(account.id.uuidString), .text(account.name), .text(account.type.rawValue),
                .text(account.icon.rawValue), .text(account.color.rawValue),
                .double(account.openingBalance),
                .double(account.createdAt.timeIntervalSince1970),
                .text(account.currencyCode),
                .double(nextAccountSortOrder()),
                .double(account.countsInNetWorth ? 1 : 0),
            ]
        )
        reload()
    }

    func updateAccount(
        _ account: Account,
        name: String,
        type: AccountType,
        icon: AccountIcon? = nil,
        color: AccountColor? = nil,
        openingBalance: Double,
        currencyCode: String? = nil,
        countsInNetWorth: Bool,
        isClosed: Bool
    ) {
        let normalizedName = normalized(name)
        guard !normalizedName.isEmpty else { return }
        execute(
            "UPDATE accounts SET name = ?, type = ?, icon = ?, color = ?, opening_balance = ?, currency = ?, counts_in_net_worth = ?, closed = ? WHERE id = ?",
            bindings: [
                .text(normalizedName), .text(type.rawValue), .text((icon ?? account.icon).rawValue),
                .text((color ?? account.color).rawValue), .double(openingBalance),
                .text(currencyCode.map(normalizedCurrency) ?? account.currencyCode),
                .double(countsInNetWorth ? 1 : 0),
                .double(isClosed ? 1 : 0),
                .text(account.id.uuidString),
            ]
        )
        reload()
    }

    func setAccountClosed(_ account: Account, _ isClosed: Bool) {
        execute(
            "UPDATE accounts SET closed = ? WHERE id = ?",
            bindings: [.double(isClosed ? 1 : 0), .text(account.id.uuidString)]
        )
        reload()
    }

    func moveAccounts(from source: IndexSet, to destination: Int) {
        var ordered = accounts.filter { !$0.isClosed }
        ordered.move(fromOffsets: source, toOffset: destination)
        ordered.append(contentsOf: accounts.filter(\.isClosed))
        execute("BEGIN IMMEDIATE TRANSACTION")
        for (index, account) in ordered.enumerated() {
            execute(
                "UPDATE accounts SET sort_order = ? WHERE id = ?",
                bindings: [.double(Double(index)), .text(account.id.uuidString)]
            )
        }
        execute("COMMIT")
        accounts = ordered
    }

    func deleteAccount(_ account: Account) {
        execute("BEGIN IMMEDIATE TRANSACTION")
        execute(
            "DELETE FROM entries WHERE account_id = ?", bindings: [.text(account.id.uuidString)])
        execute("DELETE FROM accounts WHERE id = ?", bindings: [.text(account.id.uuidString)])
        execute("COMMIT")
        reload()
    }

    /// Amount set aside with an expense. Cents round up to the next euro (13.20 → 0.80).
    /// A whole-euro amount sets aside 1.00.
    func spareChange(for amount: Double) -> Double {
        guard amount > 0 else { return 0 }
        let cents = Int((amount * 100).rounded())
        guard cents > 0 else { return 0 }
        let remainder = cents % 100
        if remainder == 0 { return 1 }
        return Double(100 - remainder) / 100
    }

    func addEntry(
        kind: EntryKind, category: String, note: String, amount: Double, date: Date, accountID: UUID,
        spareChangeAccountID: UUID? = nil, countsInAvailable: Bool = true
    ) {
        let category = normalized(category)
        guard !category.isEmpty else { return }
        let day = startOfDay(date)
        let normalizedNote = normalized(note)
        let spare = kind == .expense ? spareChange(for: amount) : 0
        let received =
            spareChangeAccountID.map { convertedTransferAmount(spare, from: accountID, to: $0) } ?? 0
        let canSaveSpareChange =
            spare > 0 && received > 0 && spareChangeAccountID != accountID
            && accounts.contains { $0.id == spareChangeAccountID && $0.type == .savings }
        if canSaveSpareChange {
            execute("BEGIN IMMEDIATE TRANSACTION")
        }
        _ = insertCategoryIfNeeded(category, icon: .tag, color: .blue)
        let spareChangeTransferID: UUID?
        if canSaveSpareChange, let spareChangeAccountID {
            let spareNote =
                normalizedNote.isEmpty ? "Spare change" : "Spare change for \(normalizedNote)"
            spareChangeTransferID = insertTransferLegs(
                from: accountID, to: spareChangeAccountID, amount: spare, receivedAmount: received,
                date: day, note: spareNote, source: .manual)
        } else {
            spareChangeTransferID = nil
        }
        insertEntry(
            LedgerEntry(
                kind: kind, category: category, note: normalizedNote, amount: amount, date: day,
                accountID: accountID, spareChangeTransferID: spareChangeTransferID,
                countsInAvailable: countsInAvailable))
        if canSaveSpareChange {
            execute("COMMIT")
        }
        reload()
    }

    /// Posts the gap between the book balance and the value the account actually has.
    /// A higher value is a Gain; a lower value is a Loss. Matching values add nothing.
    func reconcileAccount(_ account: Account, to statedValue: Double, note: String, date: Date) {
        let current = AmountExpression.rounded(balance(for: account), fractionDigits: 2)
        let stated = AmountExpression.rounded(statedValue, fractionDigits: 2)
        let adjustment = AmountExpression.rounded(stated - current, fractionDigits: 2)
        guard abs(adjustment) >= 0.01 else { return }
        let gained = adjustment > 0
        let category = gained ? "Gain" : "Loss"
        let writtenNote = normalized(note).isEmpty
            ? "Updated to \(stated.formatted(.currency(code: currencyCode(for: account))))"
            : normalized(note)
        _ = insertCategoryIfNeeded(
            category, icon: .investment, color: gained ? .green : AccountColor(preset: "red"))
        insertEntry(
            LedgerEntry(
                kind: gained ? .income : .expense, category: category, note: writtenNote,
                amount: abs(adjustment), date: startOfDay(date), accountID: account.id,
                source: .reconciliation))
        reload()
    }

    @MainActor func deleteEntry(_ entry: LedgerEntry, undoManager: UndoManager? = nil) {
        deleteEntries([entry], undoManager: undoManager)
    }

    /// Deletes the entries with their transfer and spare-change legs. Undo puts the same rows back.
    @MainActor func deleteEntries(_ targets: [LedgerEntry], undoManager: UndoManager? = nil) {
        var seen = Set<UUID>()
        let rows = targets.flatMap(rowsRemoved(with:)).filter { seen.insert($0.id).inserted }
        deleteRows(rows, undoManager: undoManager)
    }

    private func rowsRemoved(with entry: LedgerEntry) -> [LedgerEntry] {
        if let transferID = entry.transferID {
            return entries.filter { $0.transferID == transferID }
        }
        var rows = [entry]
        if let spareChangeTransferID = spareChangeLegs(for: entry)?.source.transferID {
            rows += entries.filter { $0.transferID == spareChangeTransferID }
        }
        return rows
    }

    @MainActor private func deleteRows(_ rows: [LedgerEntry], undoManager: UndoManager?) {
        guard !rows.isEmpty else { return }
        execute("BEGIN IMMEDIATE TRANSACTION")
        for row in rows {
            execute("DELETE FROM entries WHERE id = ?", bindings: [.text(row.id.uuidString)])
        }
        execute("COMMIT")
        reload()
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.insertRows(rows, undoManager: undoManager)
        }
        undoManager?.setActionName(rows.count == 1 ? "Delete Entry" : "Delete Entries")
    }

    @MainActor private func insertRows(_ rows: [LedgerEntry], undoManager: UndoManager?) {
        execute("BEGIN IMMEDIATE TRANSACTION")
        rows.forEach(insertEntry)
        execute("COMMIT")
        reload()
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.deleteRows(rows, undoManager: undoManager)
        }
        undoManager?.setActionName(rows.count == 1 ? "Delete Entry" : "Delete Entries")
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
        execute("BEGIN IMMEDIATE TRANSACTION")
        _ = insertCategoryIfNeeded("Uncategorized", icon: .tag, color: .blue)
        execute(
            "UPDATE entries SET category = 'Uncategorized' WHERE lower(category) = lower(?)",
            bindings: [.text(category.name)]
        )
        execute(
            "DELETE FROM categories WHERE lower(name) = lower(?)", bindings: [.text(category.name)])
        execute("COMMIT")
        reload()
    }

    func deleteAllData() {
        suppressBackup = true
        defer { suppressBackup = false }
        execute("BEGIN IMMEDIATE TRANSACTION")
        execute("DELETE FROM entries")
        execute("DELETE FROM accounts")
        execute("DELETE FROM categories")
        execute("DELETE FROM bills")
        execute("DELETE FROM settings")
        execute("DELETE FROM exchange_rates")
        execute("COMMIT")
        reload()
        registerCurrentUser()
        discardBackups()
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
            .filter { $0.accountID == account.id && countsTowardBalance($0) }
            .reduce(0) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
    }

    var nextAvailableAccountColor: AccountColor {
        let usedColors = Set(accounts.map(\.color))
        return AccountColor.allCases.first(where: { !usedColors.contains($0) })
            ?? AccountColor.allCases[accounts.count % AccountColor.allCases.count]
    }

    func formattedDate(_ date: Date) -> String {
        if dateFormatter.dateFormat != settings.dateFormat.rawValue {
            dateFormatter.dateFormat = settings.dateFormat.rawValue
        }
        return dateFormatter.string(from: date)
    }


    func openMemoryDatabase() throws {
        guard
            sqlite3_open_v2(
                ":memory:", &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
                == SQLITE_OK
        else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(database)
            database = nil
            throw StoreError.message("Could not open the database in memory (\(message)).")
        }
    }

    func loadSealedSnapshot() throws {
        guard let databaseKey else {
            throw StoreError.message("The database key is missing.")
        }
        let blob = try Data(contentsOf: sealedURL)
        try installSnapshot(try DatabaseSeal.open(blob, using: databaseKey))
    }

    /// Opens the current file, or the newest daily backup that still decrypts.
    private func loadNewestReadableSnapshot() throws {
        guard let databaseKey else {
            throw StoreError.message("The database key is missing.")
        }
        var candidates: [URL] = []
        if FileManager.default.fileExists(atPath: sealedURL.path) {
            candidates.append(sealedURL)
        }
        if let backups = try? FileManager.default.contentsOfDirectory(
            at: backupFolder, includingPropertiesForKeys: [.contentModificationDateKey])
        {
            candidates += backups.filter { $0.pathExtension == "sealed" }.sorted {
                modificationDate(of: $0) > modificationDate(of: $1)
            }
        }
        var lastError: Error = StoreError.message("Could not open the database.")
        for url in candidates {
            let plain: Data
            do {
                plain = try DatabaseSeal.open(try Data(contentsOf: url), using: databaseKey)
            } catch {
                lastError = error
                continue
            }
            sqlite3_close(database)
            database = nil
            try openMemoryDatabase()
            try installSnapshot(plain)
            if url != sealedURL {
                pendingRecoveryNote =
                    "The current database could not be opened, so Saldo restored \(url.lastPathComponent)."
            }
            return
        }
        throw lastError
    }

    func loadPlaintextSnapshot() throws {
        var file: OpaquePointer?
        guard sqlite3_open_v2(plaintextURL.path, &file, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else {
            sqlite3_close(file)
            throw StoreError.message("Could not read the existing database.")
        }
        defer { sqlite3_close(file) }
        var size: sqlite3_int64 = 0
        guard let pointer = sqlite3_serialize(file, "main", &size, 0) else {
            throw StoreError.message("Could not read the existing database.")
        }
        defer { sqlite3_free(pointer) }
        try installSnapshot(Data(bytes: pointer, count: Int(size)))
    }

    func installSnapshot(_ data: Data) throws {
        guard let database else { throw StoreError.message("The database is not open.") }
        guard !data.isEmpty else { return }
        guard let raw = sqlite3_malloc64(UInt64(data.count)) else {
            throw StoreError.message("Could not allocate the database.")
        }
        let buffer = raw.bindMemory(to: UInt8.self, capacity: data.count)
        data.copyBytes(to: buffer, count: data.count)
        let flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE)
        let status = sqlite3_deserialize(
            database, "main", buffer, sqlite3_int64(data.count), sqlite3_int64(data.count), flags)
        guard status == SQLITE_OK else {
            sqlite3_free(buffer)
            throw StoreError.message("Could not open the saved database.")
        }
    }

    func persist() throws {
        guard let database, let databaseKey else { return }
        var size: sqlite3_int64 = 0
        guard let pointer = sqlite3_serialize(database, "main", &size, 0) else {
            throw StoreError.message("Could not save the database.")
        }
        defer { sqlite3_free(pointer) }
        let sealed = try DatabaseSeal.seal(
            Data(bytes: pointer, count: Int(size)), using: databaseKey)
        try writeAtomically(sealed, to: sealedURL)
        cacheSettings()
        deletePlaintextCopies()
        if !suppressBackup {
            try? performPeriodicBackup()
        }
    }

    func discardBackups() {
        try? FileManager.default.removeItem(at: backupFolder)
        try? FileManager.default.removeItem(at: safetyBackupURL)
    }

    func performPeriodicBackup() throws {
        let folder = backupFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let day = Self.backupDayStamp()
        let destination = folder.appendingPathComponent("saldo-\(day).sealed")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: sealedURL, to: destination)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        let extras = files.filter { $0.pathExtension == "sealed" }.sorted {
            modificationDate(of: $0) > modificationDate(of: $1)
        }.dropFirst(30)
        for extra in extras {
            try? FileManager.default.removeItem(at: extra)
        }
    }

    var backupFolder: URL {
        sealedURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    var safetyBackupURL: URL {
        sealedURL.deletingLastPathComponent().appendingPathComponent("saldo-before-restore.sealed")
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temporary = folder.appendingPathComponent(".saldo-write-\(UUID().uuidString)")
        try data.write(to: temporary, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func deletePlaintextCopies() {
        let support = TestDataMode.applicationSupport
        let legacy = support.appendingPathComponent("Ledger", isDirectory: true)
            .appendingPathComponent("ledger.sqlite")
        for url in [plaintextURL, legacy] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        }
    }

    private func tearDownMemory() {
        sqlite3_close(database)
        database = nil
        databaseKey = nil
        accounts = []
        debts = []
        bills = []
        entries = []
        categories = []
        exchangeRates = [:]
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func cacheSettings() {
        TestDataMode.defaults.set(settingsDictionary(settings), forKey: Self.settingsCacheKey)
    }

    /// Older databases lack newer columns. Checking first keeps a normal open free of SQL errors.
    private func addColumnIfMissing(_ table: String, _ column: String, _ definition: String) {
        let existing = query("PRAGMA table_info(\(table))") { text(at: 1, from: $0) }
        guard !existing.contains(column) else { return }
        execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    func createTables() {
        execute(
            "CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, icon TEXT NOT NULL DEFAULT 'wallet.pass.fill', color TEXT NOT NULL DEFAULT 'blue', opening_balance REAL NOT NULL, created_at REAL NOT NULL)"
        )
        addColumnIfMissing("accounts", "icon", "TEXT NOT NULL DEFAULT 'wallet.pass.fill'")
        addColumnIfMissing("accounts", "color", "TEXT NOT NULL DEFAULT 'blue'")
        addColumnIfMissing("accounts", "interest_rate", "REAL NOT NULL DEFAULT 0")
        addColumnIfMissing("accounts", "interest_tax_rate", "REAL NOT NULL DEFAULT 0")
        addColumnIfMissing("accounts", "interest_accrued_through", "REAL NOT NULL DEFAULT 0")
        execute(
            "CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL, category TEXT NOT NULL, note TEXT NOT NULL, amount REAL NOT NULL, date REAL NOT NULL, account_id TEXT NOT NULL)"
        )
        execute(
            "CREATE TABLE IF NOT EXISTS categories (name TEXT PRIMARY KEY, icon TEXT NOT NULL DEFAULT 'tag.fill', color TEXT NOT NULL DEFAULT 'blue')"
        )
        addColumnIfMissing("categories", "icon", "TEXT NOT NULL DEFAULT 'tag.fill'")
        addColumnIfMissing("categories", "color", "TEXT NOT NULL DEFAULT 'blue'")
        execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        addColumnIfMissing("accounts", "currency", "TEXT NOT NULL DEFAULT ''")
        addColumnIfMissing("accounts", "sort_order", "REAL NOT NULL DEFAULT 0")
        addColumnIfMissing("accounts", "counts_in_net_worth", "INTEGER NOT NULL DEFAULT 1")
        addColumnIfMissing("accounts", "closed", "INTEGER NOT NULL DEFAULT 0")
        addColumnIfMissing("entries", "transfer_id", "TEXT NOT NULL DEFAULT ''")
        addColumnIfMissing("entries", "source", "TEXT NOT NULL DEFAULT 'manual'")
        addColumnIfMissing("entries", "spare_change_id", "TEXT NOT NULL DEFAULT ''")
        addColumnIfMissing("entries", "debt_id", "TEXT NOT NULL DEFAULT ''")
        addColumnIfMissing("entries", "debt_amount", "REAL NOT NULL DEFAULT 0")
        addColumnIfMissing("entries", "counts_in_available", "INTEGER NOT NULL DEFAULT 1")
        execute(
            "CREATE TABLE IF NOT EXISTS debts (id TEXT PRIMARY KEY, name TEXT NOT NULL, direction TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', principal REAL NOT NULL, currency TEXT NOT NULL DEFAULT '', icon TEXT NOT NULL DEFAULT 'person.fill', color TEXT NOT NULL DEFAULT 'orange', started_at REAL NOT NULL, created_at REAL NOT NULL, sort_order REAL NOT NULL DEFAULT 0)"
        )
        execute(
            "CREATE TABLE IF NOT EXISTS exchange_rates (code TEXT PRIMARY KEY, rate REAL NOT NULL)"
        )
        execute(
            "CREATE TABLE IF NOT EXISTS bills (id TEXT PRIMARY KEY, name TEXT NOT NULL, amount REAL NOT NULL, cleared_month TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL)"
        )
        execute(
            "INSERT OR IGNORE INTO categories (name, icon, color) SELECT DISTINCT category, 'tag.fill', 'blue' FROM entries WHERE trim(category) <> ''"
        )
    }

    func reload() {
        accounts = loadAccounts()
        debts = loadDebts()
        bills = loadBills()
        entries = loadEntries()
        categories = loadCategories()
        loadSettings()
        exchangeRates = loadExchangeRates()
    }

    private func nextAccountSortOrder() -> Double {
        let current = query("SELECT COALESCE(MAX(sort_order), -1) FROM accounts") { statement in
            sqlite3_column_double(statement, 0)
        }
        return (current.first ?? -1) + 1
    }

    private func loadAccounts() -> [Account] {
        query(
            "SELECT id, name, type, icon, color, opening_balance, created_at, currency, counts_in_net_worth, closed FROM accounts ORDER BY sort_order, name COLLATE NOCASE"
        ) { statement -> Account? in
            guard let id = uuid(at: 0, from: statement) else { return nil }
            var account = Account(
                id: id,
                name: text(at: 1, from: statement),
                type: Self.accountType(from: text(at: 2, from: statement)),
                icon: AccountIcon(rawValue: text(at: 3, from: statement)) ?? .wallet,
                color: AccountColor(rawValue: text(at: 4, from: statement)) ?? .blue,
                openingBalance: sqlite3_column_double(statement, 5),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                currencyCode: text(at: 7, from: statement),
                countsInNetWorth: sqlite3_column_int(statement, 8) != 0
            )
            account.isClosed = sqlite3_column_int(statement, 9) != 0
            return account
        }.compactMap { $0 }
    }

    private func loadDebts() -> [Debt] {
        query(
            "SELECT id, name, direction, note, principal, currency, icon, color, started_at, created_at FROM debts ORDER BY sort_order, name COLLATE NOCASE"
        ) { statement -> Debt? in
            guard let id = uuid(at: 0, from: statement) else { return nil }
            return Debt(
                id: id,
                name: text(at: 1, from: statement),
                direction: DebtDirection(rawValue: text(at: 2, from: statement)) ?? .iOwe,
                note: text(at: 3, from: statement),
                principal: sqlite3_column_double(statement, 4),
                currencyCode: text(at: 5, from: statement),
                icon: DebtIcon(rawValue: text(at: 6, from: statement)) ?? .person,
                color: AccountColor(rawValue: text(at: 7, from: statement))
                    ?? AccountColor(preset: "orange"),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
            )
        }.compactMap { $0 }
    }

    private func loadEntries() -> [LedgerEntry] {
        query(
            "SELECT id, kind, category, note, amount, date, account_id, transfer_id, source, spare_change_id, debt_id, debt_amount, counts_in_available FROM entries ORDER BY date DESC, rowid DESC"
        ) { statement -> LedgerEntry? in
            guard let id = uuid(at: 0, from: statement),
                let accountID = uuid(at: 6, from: statement)
            else { return nil }
            return LedgerEntry(
                id: id,
                kind: EntryKind(rawValue: text(at: 1, from: statement)) ?? .expense,
                category: text(at: 2, from: statement),
                note: text(at: 3, from: statement),
                amount: sqlite3_column_double(statement, 4),
                date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                accountID: accountID,
                transferID: UUID(uuidString: text(at: 7, from: statement)),
                spareChangeTransferID: UUID(uuidString: text(at: 9, from: statement)),
                source: EntrySource(rawValue: text(at: 8, from: statement)) ?? .manual,
                debtID: UUID(uuidString: text(at: 10, from: statement)),
                debtAmount: sqlite3_column_double(statement, 11),
                countsInAvailable: sqlite3_column_int(statement, 12) != 0
            )
        }.compactMap { $0 }
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
        settings = Self.settings(from: values)
        cacheSettings()
    }

    private func saveSettings() {
        let wasSuspended = writesSuspended
        writesSuspended = true
        defer {
            writesSuspended = wasSuspended
            if !wasSuspended {
                do {
                    try persist()
                } catch {
                    saveError = error.localizedDescription
                }
            }
        }
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


    func insertEntry(_ entry: LedgerEntry) {
        execute(
            "INSERT INTO entries (id, kind, category, note, amount, date, account_id, transfer_id, source, spare_change_id, debt_id, debt_amount, counts_in_available) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(entry.id.uuidString), .text(entry.kind.rawValue), .text(entry.category),
                .text(entry.note), .double(entry.amount), .double(entry.date.timeIntervalSince1970),
                .text(entry.accountID.uuidString), .text(entry.transferID?.uuidString ?? ""),
                .text(entry.source.rawValue), .text(entry.spareChangeTransferID?.uuidString ?? ""),
                .text(entry.debtID?.uuidString ?? ""), .double(entry.debtAmount),
                .double(entry.countsInAvailable ? 1 : 0),
            ]
        )
    }


    func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }


    func execute(_ sql: String, bindings: [SQLiteValue] = []) {
        guard let database else { return }
        let kind = sqlKind(sql)
        // One failed statement makes the whole transaction roll back instead of saving half of it.
        if kind == .commit, transactionFailed { return execute("ROLLBACK") }
        if kind == .begin { transactionDepth += 1 }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK
        defer { sqlite3_finalize(statement) }
        if prepared { bind(bindings, to: statement) }
        let step = prepared ? sqlite3_step(statement) : SQLITE_ERROR
        let succeeded = step == SQLITE_DONE || step == SQLITE_ROW
        guard succeeded else {
            saveError = "Could not save the change (\(String(cString: sqlite3_errmsg(database))))."
            switch kind {
            case .begin: transactionDepth = max(0, transactionDepth - 1)
            case .commit: execute("ROLLBACK")
            case .rollback:
                transactionDepth = 0
                transactionFailed = false
            case .write, .other:
                if transactionDepth > 0 { transactionFailed = true }
            }
            return
        }
        if kind == .commit || kind == .rollback {
            transactionDepth = 0
            transactionFailed = false
        }
        let shouldPersist =
            succeeded && transactionDepth == 0 && !writesSuspended
            && (kind == .write || kind == .commit)
        guard shouldPersist else { return }
        do {
            try persist()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private enum SQLKind {
        case begin, commit, rollback, write, other
    }

    private func sqlKind(_ sql: String) -> SQLKind {
        let word = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isLetter }
            .uppercased()
        switch word {
        case "BEGIN": return .begin
        case "COMMIT", "END": return .commit
        case "ROLLBACK": return .rollback
        case "INSERT", "UPDATE", "DELETE", "REPLACE", "CREATE", "ALTER", "DROP": return .write
        default: return .other
        }
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

    /// Nil for a malformed id; loaders skip that row instead of inventing an id for it.
    func uuid(at index: Int32, from statement: OpaquePointer) -> UUID? {
        UUID(uuidString: text(at: index, from: statement))
    }

    func text(at index: Int32, from statement: OpaquePointer) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    static let settingsCacheKey = "saldo.settingsCache"

    private static func backupDayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    static func supportFolder(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("Saldo", isDirectory: true)
    }

    static func accountType(from raw: String) -> AccountType {
        if raw == "Credit card" { return .checking }
        return AccountType(rawValue: raw) ?? .checking
    }

    static func loadCachedSettings() -> AppSettings? {
        guard let values = TestDataMode.defaults.dictionary(forKey: settingsCacheKey) as? [String: String],
            !values.isEmpty
        else { return nil }
        return settings(from: values)
    }

    static func readSettings(at url: URL) -> AppSettings? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "SELECT key, value FROM settings", -1, &statement, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(statement) }
        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = sqlite3_column_text(statement, 0),
                let value = sqlite3_column_text(statement, 1)
            else { continue }
            values[String(cString: key)] = String(cString: value)
        }
        guard !values.isEmpty else { return nil }
        return settings(from: values)
    }

    static func settings(from values: [String: String]) -> AppSettings {
        AppSettings(
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

    private func settingsDictionary(_ settings: AppSettings) -> [String: String] {
        [
            "currencyCode": settings.currencyCode,
            "dateFormat": settings.dateFormat.rawValue,
            "theme": settings.theme.rawValue,
            "fontSize": settings.fontSize.rawValue,
            "defaultImportedCategoryIcon": settings.defaultImportedCategoryIcon.rawValue,
            "defaultImportedCategoryColor": settings.defaultImportedCategoryColor.rawValue,
            "autoLockMinutes": String(settings.autoLockMinutes),
            "ownerUsername": settings.ownerUsername,
            "ownerName": settings.ownerName,
        ]
    }
}

enum SQLiteValue {
    case text(String)
    case double(Double)
}


private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension Account {
    fileprivate init(
        id: UUID, name: String, type: AccountType, icon: AccountIcon, color: AccountColor,
        openingBalance: Double, createdAt: Date, currencyCode: String,
        countsInNetWorth: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.color = color
        self.openingBalance = openingBalance
        self.createdAt = createdAt
        self.currencyCode = currencyCode
        self.countsInNetWorth = countsInNetWorth
    }
}

extension Debt {
    fileprivate init(
        id: UUID, name: String, direction: DebtDirection, note: String, principal: Double,
        currencyCode: String, icon: DebtIcon, color: AccountColor, startedAt: Date, createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.direction = direction
        self.note = note
        self.principal = principal
        self.currencyCode = currencyCode
        self.icon = icon
        self.color = color
        self.startedAt = startedAt
        self.createdAt = createdAt
    }
}

extension LedgerEntry {
    fileprivate init(
        id: UUID, kind: EntryKind, category: String, note: String, amount: Double, date: Date,
        accountID: UUID, transferID: UUID?, spareChangeTransferID: UUID?, source: EntrySource,
        debtID: UUID?, debtAmount: Double, countsInAvailable: Bool
    ) {
        self.id = id
        self.kind = kind
        self.category = category
        self.note = note
        self.amount = amount
        self.date = date
        self.accountID = accountID
        self.transferID = transferID
        self.spareChangeTransferID = spareChangeTransferID
        self.source = source
        self.debtID = debtID
        self.debtAmount = debtAmount
        self.countsInAvailable = countsInAvailable
    }
}
