import Foundation
import SQLite3

extension LedgerStore {
    func currencyCode(for debt: Debt) -> String {
        debt.currencyCode.isEmpty ? settings.currencyCode : debt.currencyCode
    }

    func payments(for debt: Debt) -> [LedgerEntry] {
        entries
            .filter { $0.debtID == debt.id }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.note.localizedStandardCompare(rhs.note) == .orderedAscending
            }
    }

    func paid(for debt: Debt, before date: Date = .distantFuture) -> Double {
        entries.reduce(0) { total, entry in
            guard entry.debtID == debt.id, entry.date < date else { return total }
            return total + appliedAmount(of: entry)
        }
    }

    func remaining(for debt: Debt, before date: Date = .distantFuture) -> Double {
        guard startOfDay(debt.startedAt) < date else { return 0 }
        return max(0, debt.principal - paid(for: debt, before: date))
    }

    func baseRemaining(for debt: Debt) -> Double {
        toBase(remaining(for: debt), in: currencyCode(for: debt))
    }

    /// Negative while you still owe it, positive while it is still owed to you.
    func signedRemaining(for debt: Debt, before date: Date) -> Double {
        let base = toBase(remaining(for: debt, before: date), in: currencyCode(for: debt))
        return debt.direction == .iOwe ? -base : base
    }

    func accountAmount(forDebtAmount amount: Double, debt: Debt, accountID: UUID) -> Double {
        let debtCode = currencyCode(for: debt)
        let accountCode = currencyCode(forAccountID: accountID)
        guard debtCode != accountCode else { return amount }
        let accountRate = rate(for: accountCode)
        guard accountRate > 0 else { return amount }
        return amount * rate(for: debtCode) / accountRate
    }

    func refreshedDebtAmount(for entry: LedgerEntry, amount: Double, accountID: UUID) -> Double {
        guard let debtID = entry.debtID, let debt = debts.first(where: { $0.id == debtID }) else {
            return entry.debtAmount
        }
        return amountInDebtCurrency(amount, accountID: accountID, debt: debt)
    }

    @discardableResult
    func addDebt(
        name: String,
        direction: DebtDirection,
        note: String,
        principal: Double,
        currencyCode: String,
        icon: DebtIcon,
        color: AccountColor,
        startedAt: Date
    ) -> Debt? {
        let name = normalized(name)
        guard !name.isEmpty, principal > 0 else { return nil }
        var debt = Debt(
            name: name,
            direction: direction,
            note: normalized(note),
            principal: principal,
            icon: icon,
            color: color,
            startedAt: startOfDay(startedAt)
        )
        debt.currencyCode = normalizedCurrency(currencyCode)
        execute(
            "INSERT INTO debts (id, name, direction, note, principal, currency, icon, color, started_at, created_at, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(debt.id.uuidString), .text(debt.name), .text(debt.direction.rawValue),
                .text(debt.note), .double(debt.principal), .text(debt.currencyCode),
                .text(debt.icon.rawValue), .text(debt.color.rawValue),
                .double(debt.startedAt.timeIntervalSince1970),
                .double(debt.createdAt.timeIntervalSince1970),
                .double(nextDebtSortOrder()),
            ]
        )
        reload()
        return debts.first { $0.id == debt.id }
    }

    func updateDebt(
        _ debt: Debt,
        name: String,
        direction: DebtDirection,
        note: String,
        principal: Double,
        currencyCode: String,
        icon: DebtIcon,
        color: AccountColor,
        startedAt: Date
    ) {
        let name = normalized(name)
        guard !name.isEmpty, principal > 0 else { return }
        let lockedDirection = payments(for: debt).isEmpty ? direction : debt.direction
        execute(
            "UPDATE debts SET name = ?, direction = ?, note = ?, principal = ?, currency = ?, icon = ?, color = ?, started_at = ? WHERE id = ?",
            bindings: [
                .text(name), .text(lockedDirection.rawValue), .text(normalized(note)),
                .double(principal), .text(normalizedCurrency(currencyCode)),
                .text(icon.rawValue), .text(color.rawValue),
                .double(startOfDay(startedAt).timeIntervalSince1970),
                .text(debt.id.uuidString),
            ]
        )
        reload()
    }

    func moveDebts(from source: IndexSet, to destination: Int) {
        var ordered = debts
        ordered.move(fromOffsets: source, toOffset: destination)
        execute("BEGIN IMMEDIATE TRANSACTION")
        for (index, debt) in ordered.enumerated() {
            execute(
                "UPDATE debts SET sort_order = ? WHERE id = ?",
                bindings: [.double(Double(index)), .text(debt.id.uuidString)]
            )
        }
        execute("COMMIT")
        debts = ordered
    }

    /// Removes the debt. Payments already posted stay in the ledger, unlinked.
    func deleteDebt(_ debt: Debt) {
        execute("BEGIN IMMEDIATE TRANSACTION")
        execute(
            "UPDATE entries SET debt_id = '', debt_amount = 0 WHERE debt_id = ?",
            bindings: [.text(debt.id.uuidString)])
        execute("DELETE FROM debts WHERE id = ?", bindings: [.text(debt.id.uuidString)])
        execute("COMMIT")
        reload()
    }

    func addDebtPayment(
        _ debt: Debt, amount: Double, date: Date, accountID: UUID, note: String
    ) {
        guard amount > 0, accounts.contains(where: { $0.id == accountID }) else { return }
        guard amount <= remaining(for: debt) + 0.000_001 else { return }
        let day = startOfDay(date)
        guard day <= startOfDay(.now) else { return }
        let accountAmount = accountAmount(forDebtAmount: amount, debt: debt, accountID: accountID)
        guard accountAmount > 0 else { return }
        let category = debt.direction.paymentCategory
        let icon: CategoryIcon = debt.direction == .iOwe ? .family : .income
        let color: CategoryColor = debt.direction == .iOwe ? CategoryColor(preset: "orange") : .green
        let paymentNote = normalized(note).isEmpty ? debt.name : normalized(note)
        execute("BEGIN IMMEDIATE TRANSACTION")
        _ = insertCategoryIfNeeded(category, icon: icon, color: color)
        insertEntry(
            LedgerEntry(
                kind: debt.direction.paymentKind,
                category: category,
                note: paymentNote,
                amount: accountAmount,
                date: day,
                accountID: accountID,
                debtID: debt.id,
                debtAmount: amount
            ))
        execute("COMMIT")
        reload()
    }

    private func appliedAmount(of entry: LedgerEntry) -> Double {
        entry.debtAmount > 0 ? entry.debtAmount : entry.amount
    }

    private func amountInDebtCurrency(_ amount: Double, accountID: UUID, debt: Debt) -> Double {
        let accountCode = currencyCode(forAccountID: accountID)
        let debtCode = currencyCode(for: debt)
        guard accountCode != debtCode else { return amount }
        let debtRate = rate(for: debtCode)
        guard debtRate > 0 else { return amount }
        return amount * rate(for: accountCode) / debtRate
    }

    private func nextDebtSortOrder() -> Double {
        let current = query("SELECT COALESCE(MAX(sort_order), -1) FROM debts") { statement in
            sqlite3_column_double(statement, 0)
        }
        return (current.first ?? -1) + 1
    }
}
