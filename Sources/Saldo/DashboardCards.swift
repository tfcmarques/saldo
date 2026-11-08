import Charts
import SwiftUI

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    fileprivate func dashboardCard() -> some View { modifier(CardBackground()) }
}

private struct FlowPoint: Identifiable {
    let month: Date
    let label: String
    let amount: Double

    var id: String { "\(month.timeIntervalSince1970)-\(label)" }
}

struct CashFlowCard: View {
    let store: LedgerStore

    var body: some View {
        let flows = store.monthlyFlows()
        let points = flows.flatMap {
            [
                FlowPoint(month: $0.month, label: "Income", amount: $0.income),
                FlowPoint(month: $0.month, label: "Expenses", amount: $0.expenses),
            ]
        }
        let currentRate = flows.last.flatMap { store.savingsRate(for: [$0]) }
        let sixMonthRate = store.savingsRate(for: flows)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cash flow").font(.headline)
                    Text("Income and expenses, last 6 months")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(rateText(currentRate))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle((currentRate ?? 0) >= 0 ? Color.green : Color.red)
                    Text("Savings rate this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Chart(points) { point in
                BarMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("Amount", point.amount)
                )
                .foregroundStyle(by: .value("Type", point.label))
                .position(by: .value("Type", point.label))
            }
            .chartForegroundStyleScale(["Income": Color.green, "Expenses": Color.red])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 210)

            Text("Six-month savings rate: \(rateText(sixMonthRate))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private func rateText(_ rate: Double?) -> String {
        guard let rate else { return "\u{2013}" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }
}

struct CategorySpendingCard: View {
    let store: LedgerStore

    var body: some View {
        let spending = store.categorySpending()
        let total = spending.reduce(0) { $0 + $1.amount }
        let code = store.settings.currencyCode

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Spending by category").font(.headline)
                Text(Date.now.formatted(.dateTime.month(.wide).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if spending.isEmpty {
                ContentUnavailableView(
                    "No spending this month", systemImage: "chart.pie",
                    description: Text("Expenses you add will show up here.")
                )
                .frame(maxWidth: .infinity, minHeight: 210)
            } else {
                HStack(alignment: .center, spacing: 18) {
                    Chart(spending) { item in
                        SectorMark(
                            angle: .value("Spent", item.amount),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Category", item.name))
                    }
                    .chartForegroundStyleScale(
                        domain: spending.map(\.name),
                        range: spending.map { $0.categoryColor?.color ?? Color.gray }
                    )
                    .chartLegend(.hidden)
                    .overlay {
                        VStack(spacing: 2) {
                            Text(total, format: .currency(code: code))
                                .font(.subheadline.weight(.semibold))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            Text("spent").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 90)
                    }
                    .frame(width: 190, height: 190)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(spending) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.categoryColor?.color ?? Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(item.name).font(.subheadline).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(item.amount, format: .currency(code: code))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                }
            }
        }
        .dashboardCard()
    }
}

struct AccountTypeAllocationChart: View {
    struct Slice: Identifiable {
        let type: AccountType
        let amount: Double
        var id: String { type.id }
    }

    let slices: [Slice]

    static func color(for type: AccountType) -> Color {
        switch type {
        case .cash: .green
        case .checking: .blue
        case .savings: .teal
        case .creditCard: .orange
        case .investment: .purple
        }
    }

    var body: some View {
        let positive = slices.filter { $0.amount > 0 }
        if !positive.isEmpty {
            Chart(positive) { slice in
                SectorMark(
                    angle: .value("Balance", slice.amount),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Type", slice.type.rawValue))
            }
            .chartForegroundStyleScale(
                domain: positive.map { $0.type.rawValue },
                range: positive.map { Self.color(for: $0.type) }
            )
            .chartLegend(.hidden)
            .frame(height: 140)
        }
    }
}

struct InterestCard: View {
    let store: LedgerStore

    var body: some View {
        let code = store.settings.currencyCode
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Interest").font(.headline)
                Text("Savings accounts earning interest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.interestEarned(), format: .currency(code: code))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Earned this year").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                Text(store.projectedAnnualInterest, format: .currency(code: code))
                    .font(.title3.weight(.semibold))
                Text("Projected over the next 12 months")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }
}

struct RecentActivityCard: View {
    let store: LedgerStore

    var body: some View {
        let recent = store.recentEntries()
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity").font(.headline)
            if recent.isEmpty {
                Text("No entries yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent) { entry in
                    RecentRow(store: store, entry: entry)
                    if entry.id != recent.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }
}

private struct RecentRow: View {
    let store: LedgerStore
    let entry: LedgerEntry

    private var account: Account? { store.accounts.first { $0.id == entry.accountID } }
    private var category: LedgerCategory? {
        store.categories.first {
            $0.name.caseInsensitiveCompare(entry.category) == .orderedSame
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isTransfer ? "arrow.left.arrow.right" : (category?.icon.rawValue ?? "tag.fill"))
                .foregroundStyle(entry.isTransfer ? Color.teal : (category?.color.color ?? Color.accentColor))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? entry.category : entry.note)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(account?.name ?? "Deleted account") \u{00B7} \(store.formattedDate(entry.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(
                store.signedAmount(entry),
                format: .currency(code: store.currencyCode(forAccountID: entry.accountID))
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(entry.kind == .income ? Color.green : Color.primary)
        }
    }
}
