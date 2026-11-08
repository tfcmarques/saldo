import Foundation

struct MonthlyFlow: Identifiable {
    let month: Date
    let income: Double
    let expenses: Double

    var id: Date { month }
    var net: Double { income - expenses }
}

struct CategorySpend: Identifiable {
    let name: String
    let amount: Double
    let categoryColor: CategoryColor?

    var id: String { name }
}

// All figures are in the main currency and ignore transfers between accounts.
extension LedgerStore {
    func monthlyFlows(months: Int = 6, endingAt date: Date = .now) -> [MonthlyFlow] {
        let calendar = Calendar.current
        guard let currentMonth = calendar.dateInterval(of: .month, for: date) else { return [] }
        return (0..<months).reversed().compactMap { offset -> MonthlyFlow? in
            guard
                let start = calendar.date(byAdding: .month, value: -offset, to: currentMonth.start),
                let interval = calendar.dateInterval(of: .month, for: start)
            else { return nil }
            var income = 0.0
            var expenses = 0.0
            for entry in entries
            where !entry.isTransfer && !isPending(entry) && entry.source != .reconciliation
                && interval.contains(entry.date) {
                let value = toBase(entry.amount, accountID: entry.accountID)
                if entry.kind == .income { income += value } else { expenses += value }
            }
            return MonthlyFlow(month: interval.start, income: income, expenses: expenses)
        }
    }

    /// Share of income kept over the given flows, or nil when there was no income.
    func savingsRate(for flows: [MonthlyFlow]) -> Double? {
        let income = flows.reduce(0) { $0 + $1.income }
        guard income > 0 else { return nil }
        return flows.reduce(0) { $0 + $1.net } / income
    }

    func categorySpending(during date: Date = .now, limit: Int = 6) -> [CategorySpend] {
        guard let month = Calendar.current.dateInterval(of: .month, for: date) else { return [] }
        let totals = Dictionary(
            grouping: entries.filter {
                $0.kind == .expense && !$0.isTransfer && !isPending($0)
                    && $0.source != .reconciliation && month.contains($0.date)
            }, by: \.category
        ).mapValues { group in
            group.reduce(0) { $0 + toBase($1.amount, accountID: $1.accountID) }
        }
        let sorted = totals.sorted { $0.value > $1.value }
        var result = sorted.prefix(limit - 1).map { item in
            CategorySpend(
                name: item.key, amount: item.value,
                categoryColor: categories.first {
                    $0.name.caseInsensitiveCompare(item.key) == .orderedSame
                }?.color)
        }
        let rest = sorted.dropFirst(limit - 1)
        if !rest.isEmpty {
            result.append(
                CategorySpend(
                    name: "Other", amount: rest.reduce(0) { $0 + $1.value }, categoryColor: nil))
        }
        return result
    }

    func recentEntries(limit: Int = 8) -> [LedgerEntry] {
        let today = startOfDay(.now)
        return Array(
            entries.filter { $0.date <= today }.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// An income or expense dated after today. Payments are already reserved, refunds are already counted, and each posts on its date.
    func isPending(_ entry: LedgerEntry) -> Bool {
        !entry.isTransfer && entry.date > startOfDay(.now)
    }

    var scheduledEntries: [LedgerEntry] {
        entries.filter(isPending).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.note.localizedStandardCompare(rhs.note) == .orderedAscending
        }
    }

    var scheduledPayments: [LedgerEntry] {
        scheduledEntries.filter { $0.kind == .expense }
    }

    var scheduledRefunds: [LedgerEntry] {
        scheduledEntries.filter { $0.kind == .income }
    }

    /// Scheduled expenses that currently reduce available cash, in the app currency.
    var scheduledTotal: Double {
        scheduledPayments.filter(\.countsInAvailable).reduce(0) {
            $0 + toBase($1.amount, accountID: $1.accountID)
        }
    }

    /// Scheduled refunds, in the app currency. Already included in the balance.
    var scheduledRefundTotal: Double {
        scheduledRefunds.reduce(0) { $0 + toBase($1.amount, accountID: $1.accountID) }
    }

    /// Posts a scheduled expense today, including any spare change saved with it.
    func markScheduledPaid(_ entry: LedgerEntry) {
        guard isPending(entry) else { return }
        updateEntry(
            entry, kind: entry.kind, category: entry.category, note: entry.note,
            amount: entry.amount, date: .now, accountID: entry.accountID,
            spareChangeAccountID: spareChangeLegs(for: entry)?.destination.accountID,
            countsInAvailable: entry.countsInAvailable)
    }

    func setCountsInAvailable(_ entry: LedgerEntry, _ counts: Bool) {
        guard entry.kind == .expense, isPending(entry) else { return }
        execute(
            "UPDATE entries SET counts_in_available = ? WHERE id = ?",
            bindings: [.double(counts ? 1 : 0), .text(entry.id.uuidString)])
        reload()
    }

    /// Pending payments left unchecked stay out of current totals. Their spare change does too.
    func countsTowardBalance(_ entry: LedgerEntry) -> Bool {
        if entry.kind == .expense, isPending(entry), !entry.countsInAvailable { return false }
        if let transferID = entry.transferID,
            entries.contains(where: {
                $0.spareChangeTransferID == transferID && $0.kind == .expense && isPending($0)
                    && !$0.countsInAvailable
            })
        {
            return false
        }
        return true
    }
}
