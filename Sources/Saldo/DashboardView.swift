import Charts
import Foundation
import SwiftUI

struct DashboardView: View {
    enum TimeRange: String, CaseIterable, Identifiable {
        case all = "All time"
        case lastYear = "Last year"
        case last30Days = "Last 30 days"
        case last7Days = "Last 7 days"
        case lastDay = "Today"

        var id: String { rawValue }
    }

    enum HistoryGrouping: String, CaseIterable, Identifiable {
        case netWorth = "Net worth"
        case accounts = "Accounts"
        case types = "Account types"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .netWorth: "chart.line.uptrend.xyaxis"
            case .accounts: "building.columns"
            case .types: "square.stack"
            }
        }
    }

    let store: LedgerStore
    @Environment(AppRouter.self) private var router
    @State private var timeRange = Self.storedTimeRange()
    @State private var historyGrouping = Self.storedGrouping()
    @State private var hiddenSeriesIDs = Self.storedHiddenSeries()
    @State private var historyHover: HistoryHover?
    @State private var contentWidth: CGFloat = 1000

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
        chartedAccounts.flatMap(history(for:))
    }

    private var accountTypeHistory: [AccountBalancePoint] {
        AccountType.allCases.flatMap { type in
            combinedHistory(
                accounts: chartedAccounts.filter { $0.type == type },
                seriesID: type.rawValue)
        }
    }

    /// Closed accounts stay in the totals but never appear on a chart.
    private var chartedAccounts: [Account] {
        store.accounts.filter { !$0.isClosed }
    }

    private var netWorthHistory: [AccountBalancePoint] {
        combinedHistory(
            accounts: chartedAccounts.filter(\.countsInNetWorth), seriesID: Self.netWorthSeriesID)
    }

    private static let netWorthSeriesID = "net-worth"

    private var accountTypeStats: [AccountTypeStat] {
        AccountType.allCases.compactMap { type in
            let accounts = chartedAccounts.filter { $0.type == type }
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
        store.netWorth(before: rangeStart ?? .distantPast)
    }

    private var debtTotals: (owed: Double, receivable: Double) {
        let owed = store.debts
            .filter { $0.direction == .iOwe }
            .reduce(0) { $0 + store.baseRemaining(for: $1) }
        let receivable = store.debts
            .filter { $0.direction == .owedToMe }
            .reduce(0) { $0 + store.baseRemaining(for: $1) }
        return (owed, receivable)
    }

    private var excludedCaption: String? {
        let names = store.accounts.filter { !$0.countsInNetWorth }.map(\.name)
        guard !names.isEmpty else { return nil }
        return "Excludes \(names.joined(separator: ", "))"
    }

    private func leftThisMonthCaption(code: String) -> String {
        let stillDue = store.billsStillDueTotal
        guard stillDue > 0.004 else { return "Nothing still due" }
        return "\(stillDue.formatted(.currency(code: code))) still due"
    }

    private var header: some View {
        let netWorth = store.netWorth
        let change = netWorth - netWorthAtRangeStart
        let percent = netWorthAtRangeStart != 0 ? change / abs(netWorthAtRangeStart) : nil
        let code = store.settings.currencyCode
        let firstName = store.settings.ownerFirstName
        let greeting = firstName.isEmpty ? "Welcome back" : "Welcome back, \(firstName)"
        var changeText = change.formatted(.currency(code: code).sign(strategy: .always()))
        if let percent {
            changeText += " (\(percent.formatted(.percent.precision(.fractionLength(1)))))"
        }
        return VStack(alignment: .leading, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(greeting)
                    .font(DS.Typeface.small)
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(netWorth, format: .currency(code: code))
                    .font(DS.Typeface.display)
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: DS.Space.xs) {
                    Text("Net worth")
                        .font(DS.Typeface.small)
                        .foregroundStyle(DS.Palette.textSecondary)
                    StatusBadge(
                        text: changeText,
                        systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right",
                        tone: change >= 0 ? .success : .danger)
                    Text(timeRange.rawValue.lowercased())
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textMuted)
                }
                if let excludedCaption {
                    Text(excludedCaption)
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textMuted)
                }
            }

            HStack(spacing: DS.Space.xs) {
                Button("Add entry", systemImage: "plus") { router.sheet = .newEntry(.expense) }
                    .buttonStyle(.pill(.primary))
                    .disabled(store.openAccounts.isEmpty)
                    .help("Record income or an expense (⌘N)")
                Button("Transfer", systemImage: "arrow.left.arrow.right") {
                    router.sheet = .newTransfer
                }
                .buttonStyle(.pill(.secondary))
                .disabled(store.openAccounts.count < 2)
                .help("Move money between two accounts (⇧⌘N)")
                Button("Update value", systemImage: "plusminus") {
                    router.sheet = .reconcileAccount(store.openAccounts.first)
                }
                .buttonStyle(.pill(.secondary))
                .disabled(store.openAccounts.isEmpty)
                .help("Set an account to the balance it has right now")
            }

            statsStrip(code: code)

            if !store.currenciesMissingRate.isEmpty {
                Label(
                    "Set an exchange rate for \(store.currenciesMissingRate.joined(separator: ", ")) in Settings so totals are accurate.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.warning)
            }
        }
    }

    /// Key figures side by side in one grouped surface.
    private func statsStrip(code: String) -> some View {
        let debts = debtTotals
        return HStack(alignment: .top, spacing: 0) {
            stat("Available cash", amount: store.availableCash, code: code) {
                Text("Cash and checking")
                if store.scheduledTotal > 0 {
                    Text("\(store.scheduledTotal.formatted(.currency(code: code))) set aside")
                        .foregroundStyle(DS.Palette.warning)
                }
                if store.scheduledRefundTotal > 0 {
                    Text("\(store.scheduledRefundTotal.formatted(.currency(code: code))) coming back")
                        .foregroundStyle(DS.Palette.success)
                }
            }
            if !store.bills.isEmpty {
                Divider().padding(.horizontal, DS.Space.m)
                Button {
                    router.selection = .bills
                } label: {
                    stat(
                        "Left this month", amount: store.leftThisMonth, code: code,
                        negative: store.leftThisMonth < 0
                    ) {
                        Text(leftThisMonthCaption(code: code))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open bills")
            }
            if debts.owed > 0.004 {
                Divider().padding(.horizontal, DS.Space.m)
                stat("Still to pay", amount: debts.owed, code: code) { Text("Debts you owe") }
            }
            if debts.receivable > 0.004 {
                Divider().padding(.horizontal, DS.Space.m)
                stat("Owed to you", amount: debts.receivable, code: code) {
                    Text("Money to collect")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .surface(padding: DS.Space.l - 4)
    }

    private func stat(
        _ title: String, amount: Double, code: String, negative: Bool = false,
        @ViewBuilder captions: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title)
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Text(amount, format: .currency(code: code))
                .font(DS.Typeface.figure)
                .monospacedDigit()
                .foregroundStyle(negative ? DS.Palette.danger : DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) { captions() }
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        header

                        if !store.openAccounts.isEmpty {
                            accountCarousel
                        }

                        chartsRow

                        summaryRow
                    }
                    .padding([.horizontal, .bottom], DS.Space.xl)
                    .padding(.top, DS.Space.xs)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width - DS.Space.xl * 2 } action: {
                        contentWidth = $0
                    }
                }
            }
        }
        .pageBackground()
        .navigationTitle("Dashboard")
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Dashboard")
                .background(DS.Palette.background)
        }
        .onChange(of: timeRange) { _, range in
            TestDataMode.defaults.set(range.rawValue, forKey: Self.timeRangeKey)
        }
        .onChange(of: historyGrouping) { _, grouping in
            TestDataMode.defaults.set(grouping.rawValue, forKey: Self.groupingKey)
        }
    }

    /// Cards sit side by side when the window is wide and stack when it is narrow.
    private var chartsRow: some View {
        let layout = contentWidth >= 760
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(spacing: 24))
        return layout {
            historyPanel
                .frame(maxWidth: .infinity)
                .frame(height: 340)
            CashFlowCard(store: store)
                .frame(maxWidth: .infinity)
                .frame(height: 340)
        }
    }

    private var summaryRow: some View {
        let wide = contentWidth >= 1100
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(spacing: 24))
        let pairLayout = contentWidth >= 560
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(spacing: 24))
        return layout {
            pairLayout {
                summaryCard(accountTypePanel)
                summaryCard(CategorySpendingCard(store: store))
            }
            .frame(maxWidth: .infinity)
            summaryCard(RecentActivityCard(store: store))
        }
    }

    private func summaryCard(_ card: some View) -> some View {
        card
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 340, alignment: .topLeading)
            // Clip to the card's own shape so overflowing rows never square off its corners.
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private var accountCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Accounts")
            ScrollView(.horizontal) {
                LazyHStack(spacing: DS.Space.s) {
                    ForEach(store.openAccounts) { account in
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

    private var historySeries: [HistorySeries] {
        switch historyGrouping {
        case .netWorth:
            [HistorySeries(id: Self.netWorthSeriesID, title: "Net worth", color: DS.Palette.accent)]
        case .accounts:
            chartedAccounts.map {
                HistorySeries(id: $0.id.uuidString, title: $0.name, color: $0.color.color)
            }
        case .types:
            accountTypeStats.map {
                HistorySeries(
                    id: $0.type.rawValue,
                    title: $0.type.rawValue,
                    color: AccountTypeAllocationChart.color(for: $0.type))
            }
        }
    }

    private var displayedHistory: [AccountBalancePoint] {
        let points =
            switch historyGrouping {
            case .netWorth: netWorthHistory
            case .accounts: accountHistory
            case .types: accountTypeHistory
            }
        return points.filter { !hiddenSeriesIDs.contains($0.seriesID) }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Balance history").font(DS.Typeface.title3)
                    Text(timeRange.rawValue)
                        .formHint()
                }
                Spacer(minLength: 24)
                PillPicker(
                    title: "Show", selection: $historyGrouping,
                    options: HistoryGrouping.allCases.map {
                        PillOption(value: $0, label: $0.rawValue, systemImage: $0.symbol)
                    },
                    help: "Show net worth, each account, or each account type")
                PillPicker(
                    title: "Time range", selection: $timeRange,
                    options: TimeRange.allCases.map { PillOption(value: $0, label: $0.rawValue) },
                    help: "How far back this chart and the net worth change go")
            }

            if historyGrouping != .netWorth {
                ScrollView(.horizontal) {
                    HStack(spacing: DS.Space.m) {
                        ForEach(historySeries) { series in
                            legendItem(series)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Chart(displayedHistory) { point in
                if historyGrouping == .netWorth {
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DS.Palette.accent.opacity(0.22), DS.Palette.accent.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                }
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.balance),
                    series: .value("Series", point.seriesID)
                )
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(by: .value("Series", point.seriesID))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel().foregroundStyle(DS.Palette.textMuted)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { quietYAxis() }
            .chartForegroundStyleScale(
                domain: historySeries.map(\.id),
                range: historySeries.map(\.color)
            )
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let next = hoveredHistory(
                                    at: location, proxy: proxy, geometry: geometry)
                                if historyHover != next { historyHover = next }
                            case .ended:
                                historyHover = nil
                            }
                        }
                    if let historyHover {
                        ChartTooltip(
                            title: historyHover.title,
                            value: historyHover.balance.formatted(
                                .currency(code: store.settings.currencyCode)),
                            detail: store.formattedDate(historyHover.date)
                        )
                        .position(chartTooltipPosition(historyHover.location, in: geometry.size))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .dashboardCard(fillHeight: true)
    }

    private func legendItem(_ series: HistorySeries) -> some View {
        let hidden = hiddenSeriesIDs.contains(series.id)
        return Button {
            if hidden {
                hiddenSeriesIDs.remove(series.id)
            } else {
                hiddenSeriesIDs.insert(series.id)
            }
            TestDataMode.defaults.set(Array(hiddenSeriesIDs), forKey: Self.hiddenSeriesKey)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(series.color)
                    .frame(width: 8, height: 8)
                    .opacity(hidden ? 0.3 : 1)
                Text(series.title)
                    .font(DS.Typeface.caption)
                    .strikethrough(hidden)
                    .foregroundStyle(hidden ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(hidden ? "Show \(series.title)" : "Hide \(series.title)")
    }

    private func hoveredHistory(
        at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy
    ) -> HistoryHover? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        let origin = frame.origin
        var best: (hover: HistoryHover, distance: CGFloat)?
        for series in historySeries where !hiddenSeriesIDs.contains(series.id) {
            let points = displayedHistory.filter { $0.seriesID == series.id }.sorted {
                $0.date < $1.date
            }
            for (index, point) in points.enumerated() {
                guard let x = proxy.position(forX: point.date),
                    let y = proxy.position(forY: point.balance)
                else { continue }
                let anchor = CGPoint(x: origin.x + x, y: origin.y + y)
                var distance = hypot(location.x - anchor.x, location.y - anchor.y)
                var tipAnchor = anchor
                if index + 1 < points.count, let nextX = proxy.position(forX: points[index + 1].date)
                {
                    let start = origin.x + x
                    let end = origin.x + nextX
                    if location.x >= start && location.x <= end {
                        let along = abs(location.y - anchor.y)
                        if along < distance {
                            distance = along
                            tipAnchor = CGPoint(x: location.x, y: anchor.y)
                        }
                    }
                }
                guard distance < 16 else { continue }
                if best == nil || distance < best!.distance {
                    best = (
                        HistoryHover(
                            title: series.title, date: point.date, balance: point.balance,
                            location: tipAnchor),
                        distance
                    )
                }
            }
        }
        return best?.hover
    }

    private var accountTypePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account types").font(DS.Typeface.title3)
            Text("Current total by type")
                .formHint()

            ForEach(accountTypeStats) { stat in
                AccountTypeStatCard(stat: stat, currencyCode: store.settings.currencyCode)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(fillHeight: true)
    }

    private func history(for account: Account) -> [AccountBalancePoint] {
        let today = Calendar.current.startOfDay(for: .now)
        let allEntries = store.entries.filter { $0.accountID == account.id && $0.date <= today }
        let earliest = allEntries.map(\.date).min() ?? min(account.createdAt, today)
        let startDate = rangeStart ?? min(account.createdAt, earliest)
        let accountEntries =
            allEntries
            .filter { $0.date >= startDate }
            .sorted { $0.date < $1.date }
        var balance = balance(for: account, before: startDate)
        let rate = store.rate(for: store.currencyCode(for: account))
        let seriesID = account.id.uuidString
        var points = [
            AccountBalancePoint(seriesID: seriesID, date: startDate, balance: balance * rate)
        ]

        for entry in accountEntries {
            balance += signedAmount(for: entry)
            points.append(
                AccountBalancePoint(seriesID: seriesID, date: entry.date, balance: balance * rate))
        }

        var daily = dailyBalances(points)
        let available = store.baseBalance(for: account)
        if let index = daily.lastIndex(where: { $0.date == today }) {
            daily[index] = AccountBalancePoint(
                seriesID: seriesID, date: today, balance: available)
        } else {
            daily.append(
                AccountBalancePoint(seriesID: seriesID, date: today, balance: available))
        }
        return daily
    }

    /// One point per day, using the balance after that day's entries. Same-day points
    /// otherwise stack on one x value and the line bends between them.
    private func dailyBalances(_ points: [AccountBalancePoint]) -> [AccountBalancePoint] {
        let calendar = Calendar.current
        var lastByDay: [Date: AccountBalancePoint] = [:]
        var order: [Date] = []
        for point in points {
            let day = calendar.startOfDay(for: point.date)
            if lastByDay[day] == nil { order.append(day) }
            lastByDay[day] = AccountBalancePoint(
                seriesID: point.seriesID, date: day, balance: point.balance)
        }
        return order.compactMap { lastByDay[$0] }
    }

    private static let hiddenSeriesKey = "dashboard.hiddenHistorySeries"
    private static let timeRangeKey = "dashboard.historyTimeRange"
    private static let groupingKey = "dashboard.historyGrouping"

    private static func storedHiddenSeries() -> Set<String> {
        Set(TestDataMode.defaults.stringArray(forKey: hiddenSeriesKey) ?? [])
    }

    private static func storedTimeRange() -> TimeRange {
        let stored = TestDataMode.defaults.string(forKey: timeRangeKey) ?? ""
        // "Last day" is the old name of Today.
        return TimeRange(rawValue: stored == "Last day" ? TimeRange.lastDay.rawValue : stored)
            ?? .lastYear
    }

    private static func storedGrouping() -> HistoryGrouping {
        HistoryGrouping(rawValue: TestDataMode.defaults.string(forKey: groupingKey) ?? "")
            ?? .netWorth
    }

    private func combinedHistory(accounts: [Account], seriesID: String) -> [AccountBalancePoint] {
        guard !accounts.isEmpty else { return [] }
        let points = accounts.flatMap(history(for:))
        let dates = Set(points.map(\.date)).sorted()
        let byDate = Dictionary(grouping: points, by: \.date)
        var lastBalance: [String: Double] = [:]
        return dates.map { date in
            for point in byDate[date] ?? [] {
                lastBalance[point.seriesID] = point.balance
            }
            return AccountBalancePoint(
                seriesID: seriesID,
                date: date,
                balance: lastBalance.values.reduce(0, +))
        }
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
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            IconBubble(systemName: account.icon.rawValue, tint: account.color.color, size: 32)
            Spacer(minLength: 0)
            Text(account.name)
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
            Text(balance, format: .currency(code: currencyCode))
                .font(DS.Typeface.title3)
                .monospacedDigit()
                .foregroundStyle(balance < 0 ? DS.Palette.danger : DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(DS.Space.m)
        .frame(width: 176, height: 128, alignment: .leading)
        .background(
            DS.Palette.surface,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contextMenu {
            Button("Update value", systemImage: "plusminus") {
                router.sheet = .reconcileAccount(account)
            }
        }
    }
}

private struct AccountTypeStatCard: View {
    let stat: AccountTypeStat
    let currencyCode: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: stat.type.symbol)
                .frame(width: 18)
                .foregroundStyle(AccountTypeAllocationChart.color(for: stat.type))
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.type.rawValue)
                    .font(DS.Typeface.small.weight(.medium))
                Text("\(stat.accountCount) \(stat.accountCount == 1 ? "account" : "accounts")")
                    .formHint()
            }
            Spacer()
            Text(stat.balance, format: .currency(code: currencyCode))
                .font(DS.Typeface.small.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct AccountTypeStat: Identifiable {
    let type: AccountType
    let accountCount: Int
    let balance: Double

    var id: String { type.id }
}

private struct HistoryHover: Equatable {
    let title: String
    let date: Date
    let balance: Double
    let location: CGPoint
}

private struct HistorySeries: Identifiable {
    let id: String
    let title: String
    let color: Color
}

private struct AccountBalancePoint: Identifiable {
    let seriesID: String
    let date: Date
    let balance: Double

    var id: String { "\(seriesID)-\(date.timeIntervalSince1970)-\(balance)" }
}
