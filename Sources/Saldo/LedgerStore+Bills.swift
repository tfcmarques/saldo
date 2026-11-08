import Foundation
import SQLite3

extension LedgerStore {
    /// Local calendar month, so a tick from last month is due again on the 1st.
    static func billMonthKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    func isBillStillDue(_ bill: Bill, on date: Date = .now) -> Bool {
        bill.clearedMonth != Self.billMonthKey(for: date)
    }

    var billsStillDue: [Bill] {
        bills.filter { isBillStillDue($0) }
    }

    var billsStillDueTotal: Double {
        billsStillDue.reduce(0) { $0 + $1.amount }
    }

    /// Available cash minus bills not yet ticked off. Does not post anything.
    var leftThisMonth: Double {
        availableCash - billsStillDueTotal
    }

    func loadBills() -> [Bill] {
        query(
            "SELECT id, name, amount, cleared_month, created_at FROM bills ORDER BY created_at, name COLLATE NOCASE"
        ) { statement -> Bill? in
            guard let id = uuid(at: 0, from: statement) else { return nil }
            return Bill(
                id: id,
                name: text(at: 1, from: statement),
                amount: sqlite3_column_double(statement, 2),
                clearedMonth: text(at: 3, from: statement),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            )
        }.compactMap { $0 }
    }

    @discardableResult
    func addBill(name: String, amount: Double) -> Bill? {
        let name = normalized(name)
        guard !name.isEmpty, amount > 0 else { return nil }
        let bill = Bill(name: name, amount: amount)
        execute(
            "INSERT INTO bills (id, name, amount, cleared_month, created_at) VALUES (?, ?, ?, ?, ?)",
            bindings: [
                .text(bill.id.uuidString), .text(bill.name), .double(bill.amount),
                .text(""), .double(bill.createdAt.timeIntervalSince1970),
            ]
        )
        reload()
        return bills.first { $0.id == bill.id }
    }

    func updateBill(_ bill: Bill, name: String, amount: Double) {
        let name = normalized(name)
        guard !name.isEmpty, amount > 0 else { return }
        execute(
            "UPDATE bills SET name = ?, amount = ? WHERE id = ?",
            bindings: [.text(name), .double(amount), .text(bill.id.uuidString)]
        )
        reload()
    }

    /// Ticked means paid or skipped for this month. Unticked means it still reduces what's left.
    func setBillHandled(_ bill: Bill, _ handled: Bool) {
        let month = handled ? Self.billMonthKey() : ""
        guard bill.clearedMonth != month else { return }
        execute(
            "UPDATE bills SET cleared_month = ? WHERE id = ?",
            bindings: [.text(month), .text(bill.id.uuidString)]
        )
        reload()
    }

    func deleteBill(_ bill: Bill) {
        execute("DELETE FROM bills WHERE id = ?", bindings: [.text(bill.id.uuidString)])
        reload()
    }
}
