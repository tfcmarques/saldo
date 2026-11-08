import Charts
import Foundation
import SwiftUI

struct DashboardView: View {
    enum TimeRange: String, CaseIterable, Identifiable {
        case all = "All time"
        case lastYear = "Last year"
        case last30Days = "Last 30 days"
        case last7Days = "Last 7 days"
        case lastDay = "Last day"

        var id: String { rawValue }
    }

    let store: LedgerStore
    @State private var timeRange: TimeRange = .lastYear

    private var rangeStart: Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        switch timeRange {
        case .all: return nil
        case .lastYear: return calendar.date(byAdding: .year, value: -1, to: today)
        case .last30Days: return calendar.date(byAdding: .day, value: -29, to: today)
        case .last7Days: return calendar.date(byAdding: .day, value: -6, to: today)
        case .lastDay: return today
        }
    }

    private var accountHistory: [AccountBalancePoint] {
        store.accounts.flatMap { account in
            let allEntries = store.entries.filter { $0.accountID == account.id }
            let earliest = allEntries.map(\.date).min() ?? account.createdAt
            let startDate = rangeStart ?? min(account.createdAt, earliest)
            let accountEntries =
                allEntries
                .filter { $0.date >= startDate }
                .sorted { $0.date < $1.date }
            var balance = balance(for: account, before: startDate)
            let rate = store.rate(for: store.currencyCode(for: account))
            var points = [
                AccountBalancePoint(account: account, date: startDate, balance: balance * rate)
            ]

            for entry in accountEntries {
                balance += signedAmount(for: entry)
                points.append(
                    AccountBalancePoint(
                        account: account, date: entry.date, balance: balance * rate))
            }

            let today = Calendar.current.startOfDay(for: .now)
            if let lastPoint = points.last, lastPoint.date < today {
                points.append(
                    AccountBalancePoint(account: account, date: today, balance: lastPoint.balance))
            }
            return points
        }
    }

    private var accountTypeStats: [AccountTypeStat] {
        AccountType.allCases.compactMap { type in
            let accounts = store.accounts.filter { $0.type == type }
            guard !accounts.isEmpty else { return nil }
            return AccountTypeStat(
                type: type,
                accountCount: accounts.count,
                balance: accounts.reduce(0) { $0 + store.baseBalance(for: $1) }
            )
        }
        .sorted { $0.balance > $1.balance }
    }

    private var netWorthAtRangeStart: Double {
        store.accounts.reduce(0) {
            $0
                + store.toBase(
                    balance(for: $1, before: rangeStart ?? .distantPast),
                    in: store.currencyCode(for: $1))
        }
    }

    private var header: some View {
        let netWorth = store.totalBalance
        let change = netWorth - netWorthAtRangeStart
        let percent = netWorthAtRangeStart != 0 ? change / abs(netWorthAtRangeStart) : nil
        let code = store.settings.currencyCode
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                SaldoMark(size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(SaldoBrand.name)
                        .font(.largeTitle.weight(.bold))
                    Text(SaldoBrand.tagline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Net worth").font(.caption).foregroundStyle(.secondary)
                    Text(netWorth, format: .currency(code: code))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    HStack(spacing: 6) {
                        Text(change, format: .currency(code: code).sign(strategy: .always()))
                        if let percent {
                            Text("(\(percent.formatted(.percent.precision(.fractionLength(1)))))")
                        }
                        Text(timeRange.rawValue.lowercased()).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(change >= 0 ? Color.green : Color.red)
                }
            }
            if !store.currenciesMissingRate.isEmpty {
                Label(
                    "Set an exchange rate for \(store.currenciesMissingRate.joined(separator: ", ")) in Settings so totals are accurate.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                ContentUnavailableView(
                    "Add your first account",
                    systemImage: "building.columns",
                    description: Text("Your balances and account history will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header

                        accountCarousel

                        HStack(alignment: .top, spacing: 24) {
                            balanceHistoryPanel
                                .frame(maxWidth: .infinity, alignment: .leading)
                            accountTypePanel
                                .frame(width: 280)
                        }

                        HStack(alignment: .top, spacing: 24) {
                            CashFlowCard(store: store)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            CategorySpendingCard(store: store)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(alignment: .top, spacing: 24) {
                            if store.earnsInterest {
                                InterestCard(store: store)
                                    .frame(width: 280)
                            }
                            RecentActivityCard(store: store)
                        }
                    }
                    .padding(28)
                }
            }
        }
        .navigationTitle("Dashboard")
    }

    private var accountCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accounts").font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(store.accounts) { account in
                        DashboardAccountCard(
                            account: account,
                            balance: store.balance(for: account),
                            currencyCode: store.currencyCode(for: account)
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private var balanceHistoryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Account balance history").font(.headline)
                    Text(timeRange.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Time range", selection: $timeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            accountLegend

            Chart(accountHistory) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.balance),
                    series: .value("Account", point.accountID.uuidString)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Account", point.accountID.uuidString))
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.balance)
                )
                .foregroundStyle(by: .value("Account", point.accountID.uuidString))
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartForegroundStyleScale(
                domain: store.accounts.map { $0.id.uuidString },
                range: store.accounts.map { $0.color.color }
            )
            .chartLegend(.hidden)
            .frame(height: 320)
        }
        .padding(18)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var accountLegend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(store.accounts) { account in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(account.color.color)
                            .frame(width: 8, height: 8)
                        Text(account.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var accountTypePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account types").font(.headline)
            Text("Current total by type")
                .font(.caption)
                .foregroundStyle(.secondary)

            AccountTypeAllocationChart(
                slices: accountTypeStats.map {
                    AccountTypeAllocationChart.Slice(type: $0.type, amount: $0.balance)
                })

            ForEach(accountTypeStats) { stat in
                AccountTypeStatCard(stat: stat, currencyCode: store.settings.currencyCode)
            }
        }
        .padding(18)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func balance(for account: Account, before date: Date) -> Double {
        account.openingBalance
            + store.entries
            .filter { $0.accountID == account.id && $0.date < date }
            .reduce(0) { $0 + signedAmount(for: $1) }
    }

    private func signedAmount(for entry: LedgerEntry) -> Double {
        entry.kind == .income ? entry.amount : -entry.amount
    }
}

private struct DashboardAccountCard: View {
    let account: Account
    let balance: Double
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: account.icon.rawValue)
                    .foregroundStyle(account.color.color)
                Spacer()
                Circle()
                    .fill(account.color.color)
                    .frame(width: 9, height: 9)
            }
            Text(account.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(balance, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(width: 126, height: 126, alignment: .leading)
        .background(account.color.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AccountTypeStatCard: View {
    let stat: AccountTypeStat
    let currencyCode: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: stat.type))
                .frame(width: 18)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.type.rawValue)
                    .font(.subheadline.weight(.medium))
                Text("\(stat.accountCount) \(stat.accountCount == 1 ? "account" : "accounts")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(stat.balance, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func symbol(for type: AccountType) -> String {
        switch type {
        case .cash: "banknote"
        case .checking: "building.columns"
        case .savings: "lock"
        case .creditCard: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }
}

private struct AccountTypeStat: Identifiable {
    let type: AccountType
    let accountCount: Int
    let balance: Double

    var id: String { type.id }
}

private struct AccountBalancePoint: Identifiable {
    let accountID: UUID
    let date: Date
    let balance: Double

    init(account: Account, date: Date, balance: Double) {
        accountID = account.id
        self.date = date
        self.balance = balance
    }

    var id: String { "\(accountID.uuidString)-\(date.timeIntervalSince1970)-\(balance)" }
}
