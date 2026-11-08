import Charts
import SwiftUI

extension View {
    func dashboardCard(fillHeight: Bool = false) -> some View {
        surface(fillHeight: fillHeight)
    }
}

struct ChartTooltip: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typeface.caption.weight(.semibold))
            Text(value)
                .font(DS.Typeface.caption)
            if let detail {
                Text(detail)
                    .font(DS.Typeface.micro)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            DS.Palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                .strokeBorder(DS.Palette.border))
        .fixedSize()
        .allowsHitTesting(false)
    }
}

func chartTooltipPosition(_ anchor: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(
        x: min(max(anchor.x, 72), max(72, size.width - 72)),
        y: min(max(anchor.y - 34, 22), max(22, size.height - 22))
    )
}

private struct FlowPoint: Identifiable {
    let month: Date
    let label: String
    let amount: Double

    var id: String { "\(month.timeIntervalSince1970)-\(label)" }
}

struct CashFlowCard: View {
    let store: LedgerStore
    @State private var hover: CashFlowHover?

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
                    Text("Cash flow").font(DS.Typeface.title3)
                    Text("Income and expenses, last 6 months")
                        .formHint()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(rateText(currentRate))
                        .font(DS.Typeface.title3)
                        .foregroundStyle((currentRate ?? 0) >= 0 ? DS.Palette.success : DS.Palette.danger)
                    Text("Savings rate this month")
                        .formHint()
                }
            }

            Chart(points) { point in
                BarMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("Amount", point.amount)
                )
                .foregroundStyle(by: .value("Type", point.label))
                .position(by: .value("Type", point.label))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .chartForegroundStyleScale(["Income": DS.Palette.success, "Expenses": DS.Palette.danger])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .foregroundStyle(DS.Palette.textMuted)
                }
            }
            .chartYAxis { quietYAxis() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let next = cashFlowHover(
                                    at: location, proxy: proxy, geometry: geometry, flows: flows)
                                if hover != next { hover = next }
                            case .ended:
                                hover = nil
                            }
                        }
                    if let hover {
                        ChartTooltip(
                            title: hover.label,
                            value: hover.amount.formatted(
                                .currency(code: store.settings.currencyCode)),
                            detail: hover.month.formatted(.dateTime.month(.wide).year())
                        )
                        .position(chartTooltipPosition(hover.location, in: geometry.size))
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text("Six-month savings rate: \(rateText(sixMonthRate))")
                .formHint()
        }
        .dashboardCard(fillHeight: true)
    }

    private func rateText(_ rate: Double?) -> String {
        guard let rate else { return "n/a" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    private func cashFlowHover(
        at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, flows: [MonthlyFlow]
    ) -> CashFlowHover? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return nil }
        let x = location.x - frame.origin.x
        let y = location.y - frame.origin.y
        var nearest: (flow: MonthlyFlow, center: CGFloat)?
        for flow in flows {
            guard let center = proxy.position(forX: flow.month) else { continue }
            if nearest == nil || abs(x - center) < abs(x - nearest!.center) {
                nearest = (flow, center)
            }
        }
        guard let nearest, abs(x - nearest.center) < 36 else { return nil }
        let income = x <= nearest.center
        let amount = income ? nearest.flow.income : nearest.flow.expenses
        guard amount > 0,
            let top = proxy.position(forY: amount),
            let base = proxy.position(forY: 0)
        else { return nil }
        let low = min(top, base) - 6
        let high = max(top, base) + 6
        guard y >= low && y <= high else { return nil }
        return CashFlowHover(
            label: income ? "Income" : "Expenses",
            month: nearest.flow.month,
            amount: amount,
            location: CGPoint(x: frame.origin.x + nearest.center, y: frame.origin.y + min(top, base))
        )
    }
}

private struct CashFlowHover: Equatable {
    let label: String
    let month: Date
    let amount: Double
    let location: CGPoint
}

struct CategorySpendingCard: View {
    let store: LedgerStore
    @State private var hover: SpendingHover?

    var body: some View {
        let spending = store.categorySpending()
        let total = spending.reduce(0) { $0 + $1.amount }
        let code = store.settings.currencyCode

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Spending by category").font(DS.Typeface.title3)
                Text(Date.now.formatted(.dateTime.month(.wide).year()))
                    .formHint()
            }

            if spending.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(DS.Typeface.title2)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text("No spending this month")
                        .font(DS.Typeface.small.weight(.medium))
                    Text("Expenses you add will show up here.")
                        .font(DS.Typeface.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let next = spendingHover(
                                        at: location, proxy: proxy, geometry: geometry,
                                        spending: spending, total: total)
                                    if hover != next { hover = next }
                                case .ended:
                                    hover = nil
                                }
                            }
                    }
                }
                .overlay {
                    VStack(spacing: 2) {
                        Text(total, format: .currency(code: code))
                            .font(DS.Typeface.caption.weight(.semibold))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("spent").font(DS.Typeface.micro).foregroundStyle(DS.Palette.textSecondary)
                    }
                    .frame(maxWidth: 64)
                }
                .frame(width: 96, height: 96)
                .clipped()
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(spending) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.categoryColor?.color ?? Color.gray)
                                .frame(width: 8, height: 8)
                            Text(item.name).font(DS.Typeface.small).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.amount, format: .currency(code: code))
                                .font(DS.Typeface.small.weight(.medium))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let hover {
                ChartTooltip(
                    title: hover.name,
                    value: hover.amount.formatted(.currency(code: code)),
                    detail: hover.share.formatted(.percent.precision(.fractionLength(0)))
                        + " of spending"
                )
                .padding(DS.Space.s)
            }
        }
        .dashboardCard(fillHeight: true)
    }

    private func spendingHover(
        at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy,
        spending: [CategorySpend], total: Double
    ) -> SpendingHover? {
        guard total > 0, let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        let outer = min(frame.width, frame.height) / 2
        guard distance >= outer * 0.5 && distance <= outer * 1.08 else { return nil }
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)
        var covered = 0.0
        for item in spending {
            covered += item.amount / total
            if fraction <= covered {
                return SpendingHover(name: item.name, amount: item.amount, share: item.amount / total)
            }
        }
        return nil
    }
}

private struct SpendingHover: Equatable {
    let name: String
    let amount: Double
    let share: Double
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
        case .cash: DS.Palette.success
        case .checking: DS.Palette.accent
        case .savings: Color(light: 0x00A3C4, dark: 0x2EC4E0)
        case .investment: DS.Palette.warning
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
            .frame(height: 120)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ScheduledPaymentsCard: View {
    let store: LedgerStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        let payments = store.scheduledPayments
        let refunds = store.scheduledRefunds
        if !payments.isEmpty || !refunds.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if !payments.isEmpty {
                    scheduledGroup(
                        title: "Scheduled payments",
                        detail: "Check a payment to count it in available cash. It still posts on its date.",
                        total: store.scheduledTotal,
                        addHelp: "Schedule payment",
                        entries: payments
                    ) {
                        router.sheet = .newScheduledPayment
                    }
                }
                if !refunds.isEmpty {
                    scheduledGroup(
                        title: "Scheduled refunds",
                        detail: "Counted now. Each refund posts on its date.",
                        total: store.scheduledRefundTotal,
                        addHelp: "Schedule refund",
                        entries: refunds
                    ) {
                        router.sheet = .newScheduledRefund
                    }
                }
            }
            .dashboardCard()
        }
    }

    private func scheduledGroup(
        title: String, detail: String, total: Double, addHelp: String, entries: [LedgerEntry],
        add: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(DS.Typeface.title3)
                    Text(detail)
                        .formHint()
                }
                Spacer()
                Text(total, format: .currency(code: store.settings.currencyCode))
                    .font(DS.Typeface.title3)
                    .foregroundStyle(entries.first?.kind == .income ? DS.Palette.success : DS.Palette.textPrimary)
                Button(addHelp, systemImage: "plus", action: add)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.icon)
                    .help(addHelp)
            }
            ForEach(entries) { entry in
                ScheduledPaymentRow(store: store, entry: entry)
                if entry.id != entries.last?.id { Divider() }
            }
        }
    }
}

private struct ScheduledPaymentRow: View {
    let store: LedgerStore
    let entry: LedgerEntry
    @Environment(AppRouter.self) private var router
    @Environment(\.undoManager) private var undoManager

    private var account: Account? { store.accounts.first { $0.id == entry.accountID } }
    private var category: LedgerCategory? {
        store.categories.first {
            $0.name.caseInsensitiveCompare(entry.category) == .orderedSame
        }
    }

    private var isRefund: Bool { entry.kind == .income }

    private var receivedTitle: String { isRefund ? "Mark as received" : "Mark as paid" }

    var body: some View {
        HStack(spacing: 10) {
            IconBubble(
                systemName: category?.icon.rawValue ?? "calendar.badge.clock",
                tint: category?.color.color ?? DS.Palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? entry.category : entry.note)
                    .font(DS.Typeface.small.weight(.medium))
                    .lineLimit(1)
                DetailLine([account?.name ?? "Deleted account", store.formattedDate(entry.date)])
            }
            Spacer()
            if !isRefund {
                Toggle(
                    "Set aside",
                    isOn: Binding(
                        get: { entry.countsInAvailable },
                        set: { store.setCountsInAvailable(entry, $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .help("Take this payment out of available cash now, before it posts")
            }
            Text(
                isRefund ? entry.amount : -entry.amount,
                format: .currency(code: store.currencyCode(forAccountID: entry.accountID))
            )
            .font(DS.Typeface.small.weight(.semibold))
            .foregroundStyle(isRefund ? DS.Palette.success : DS.Palette.textPrimary)
            Button(receivedTitle, systemImage: "checkmark.circle") {
                store.markScheduledPaid(entry)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.icon)
            .help(receivedTitle)
            Button("Edit", systemImage: "pencil") {
                router.sheet = .editEntry(entry)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.icon)
            .help(isRefund ? "Edit scheduled refund" : "Edit scheduled payment")
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { router.sheet = .editEntry(entry) }
            Button(receivedTitle, systemImage: "checkmark.circle") {
                store.markScheduledPaid(entry)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.deleteEntry(entry, undoManager: undoManager)
            }
        }
    }
}

struct RecentActivityCard: View {
    let store: LedgerStore

    var body: some View {
        let recent = store.recentEntries(limit: 5)
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity").font(DS.Typeface.title3)
            if recent.isEmpty {
                Text("No entries yet.")
                    .font(DS.Typeface.small)
                    .foregroundStyle(DS.Palette.textSecondary)
            } else {
                ForEach(recent) { entry in
                    RecentRow(store: store, entry: entry)
                }
            }
            Spacer(minLength: 0)
        }
        .dashboardCard(fillHeight: true)
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
        TransactionRow(
            symbol: entry.isTransfer ? "arrow.left.arrow.right" : (category?.icon.rawValue ?? "tag"),
            tint: entry.isTransfer ? DS.Palette.textSecondary : (category?.color.color ?? DS.Palette.accent),
            title: entry.note.isEmpty ? entry.category : entry.displayNote,
            details: [account?.name ?? "Deleted account", store.formattedDate(entry.date)],
            amount: store.signedAmount(entry),
            currencyCode: store.currencyCode(forAccountID: entry.accountID))
    }
}
