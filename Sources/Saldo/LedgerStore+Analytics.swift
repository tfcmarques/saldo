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
            for entry in entries where !entry.isTransfer && interval.contains(entry.date) {
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
                $0.kind == .expense && !$0.isTransfer && month.contains($0.date)
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

    var earnsInterest: Bool {
        accounts.contains { $0.interestRate > 0 }
    }

    func interestEarned(inYearOf date: Date = .now) -> Double {
        let year = Calendar.current.component(.year, from: date)
        return entries
            .filter {
                $0.source == .interest && Calendar.current.component(.year, from: $0.date) == year
            }
            .reduce(0) { $0 + toBase($1.amount, accountID: $1.accountID) }
    }

    /// Net interest over the next 12 months at today's balances, compounded daily like the accrual.
    var projectedAnnualInterest: Double {
        accounts.reduce(0) { total, account in
            let balance = balance(for: account)
            guard account.interestRate > 0, balance > 0 else { return total }
            let dailyRate = account.interestRate / 100 / 365 * (1 - account.interestTaxRate / 100)
            let growth = pow(1 + dailyRate, 365) - 1
            return total + toBase(balance * growth, in: currencyCode(for: account))
        }
    }

    func recentEntries(limit: Int = 8) -> [LedgerEntry] {
        let today = startOfDay(.now)
        return Array(
            entries.filter { $0.date <= today }.sorted { $0.date > $1.date }.prefix(limit))
    }
}
