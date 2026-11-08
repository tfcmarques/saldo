import SwiftUI

/// Monthly bills as a checklist. Ticking a bill only changes this month's estimate:
/// nothing is posted to the ledger and no payment is scheduled.
struct BillsView: View {
    let store: LedgerStore
    @Environment(AppRouter.self) private var router
    @State private var billPendingDeletion: Bill?

    private var stillDue: [Bill] { store.bills.filter { store.isBillStillDue($0) } }
    private var handled: [Bill] { store.bills.filter { !store.isBillStillDue($0) } }
    private var monthlyTotal: Double { store.bills.reduce(0) { $0 + $1.amount } }
    private var code: String { store.settings.currencyCode }

    var body: some View {
        Group {
            if store.bills.isEmpty {
                ContentUnavailableView {
                    Label("No bills yet", systemImage: "checklist")
                } description: {
                    Text(
                        "List what you pay every month, like rent or internet, to see how much you have left. Bills never touch your accounts."
                    )
                } actions: {
                    Button("Add bill") { router.sheet = .newBill }
                        .buttonStyle(.pill(.primary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        summary
                        if !stillDue.isEmpty {
                            group("Still to pay", bills: stillDue)
                        }
                        if !handled.isEmpty {
                            group("Paid or skipped this month", bills: handled)
                        }
                        Text(
                            "Ticks clear on the 1st of each month. Bills are estimates for this page only, so your accounts and ledger stay as they are."
                        )
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.textMuted)
                    }
                    .padding([.horizontal, .bottom], DS.Space.xl)
                    .padding(.top, DS.Space.xs)
                }
            }
        }
        .pageBackground()
        .navigationTitle("Bills")
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Bills", subtitle: "What repeats every month") {
                Button("Add bill", systemImage: "plus") { router.sheet = .newBill }
                    .buttonStyle(.pill(.primary))
                    .help("Add a monthly bill")
            }
            .background(DS.Palette.background)
        }
        .confirmationDialog(
            billPendingDeletion.map { "Delete \($0.name)?" } ?? "Delete this bill?",
            isPresented: Binding(
                get: { billPendingDeletion != nil },
                set: { if !$0 { billPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let billPendingDeletion {
                    store.deleteBill(billPendingDeletion)
                }
                billPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { billPendingDeletion = nil }
        } message: {
            Text("This only removes the bill from this list. Your ledger stays as it is.")
        }
    }

    /// The month's sum in words: what you have, what is still to go, what remains.
    private var summary: some View {
        let paidAmount = handled.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .top, spacing: 0) {
                figure("Available cash", store.availableCash, caption: "Cash and checking now")
                Divider().padding(.horizontal, DS.Space.m)
                figure("Still to pay", store.billsStillDueTotal, caption: "Bills not ticked yet")
                Divider().padding(.horizontal, DS.Space.m)
                figure(
                    "Left this month", store.leftThisMonth,
                    caption: "Available cash after the bills still to pay",
                    tint: store.leftThisMonth < 0 ? DS.Palette.danger : DS.Palette.textPrimary)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("\(handled.count) of \(store.bills.count) bills handled")
                        .font(DS.Typeface.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    Text(
                        "\(paidAmount.formatted(.currency(code: code))) of \(monthlyTotal.formatted(.currency(code: code))) a month"
                    )
                    .font(DS.Typeface.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textMuted)
                }
                ProgressView(value: paidAmount, total: max(monthlyTotal, 0.01))
                    .tint(DS.Palette.success)
            }
        }
        .surface()
    }

    private func figure(
        _ title: String, _ amount: Double, caption: String,
        tint: Color = DS.Palette.textPrimary
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
            Text(amount, format: .currency(code: code))
                .font(DS.Typeface.figure)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption).font(DS.Typeface.caption).foregroundStyle(DS.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group(_ title: String, bills: [Bill]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SectionLabel(title)
            VStack(spacing: 0) {
                ForEach(bills) { bill in
                    BillRow(store: store, bill: bill) { billPendingDeletion = bill }
                    if bill.id != bills.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .surface(padding: DS.Space.xs)
        }
    }
}

/// One bill. Clicking anywhere on the row ticks it off for this month, or brings it back.
private struct BillRow: View {
    let store: LedgerStore
    let bill: Bill
    let delete: () -> Void
    @Environment(AppRouter.self) private var router
    @State private var isHovered = false

    private var handled: Bool { !store.isBillStillDue(bill) }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                withAnimation(DS.Motion.quick) { store.setBillHandled(bill, !handled) }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: handled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(handled ? DS.Palette.success : DS.Palette.textMuted)
                        .frame(width: 36, height: 36)
                    Text(bill.name)
                        .font(DS.Typeface.bodyStrong)
                        .strikethrough(handled, color: DS.Palette.textMuted)
                        .foregroundStyle(handled ? DS.Palette.textMuted : DS.Palette.textPrimary)
                    Spacer(minLength: DS.Space.s)
                    Text(bill.amount, format: .currency(code: store.settings.currencyCode))
                        .font(DS.Typeface.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(handled ? DS.Palette.textMuted : DS.Palette.textPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(bill.name), \(handled ? "paid or skipped" : "still to pay")")
            .help(handled ? "Mark as still to pay" : "Mark as paid or skipped this month")

            Button("Edit", systemImage: "pencil") { router.sheet = .editBill(bill) }
                .buttonStyle(.icon)
                .help("Edit bill")
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                .buttonStyle(.icon)
                .help("Delete bill")
        }
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .background(
            DS.Palette.textPrimary.opacity(isHovered ? 0.04 : 0),
            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(handled ? "Mark as still to pay" : "Mark as paid or skipped") {
                store.setBillHandled(bill, !handled)
            }
            Button("Edit", systemImage: "pencil") { router.sheet = .editBill(bill) }
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }
}

struct BillSheet: View {
    let store: LedgerStore
    let bill: Bill?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var amount: Double
    @State private var isAmountValid = true

    init(store: LedgerStore, bill: Bill?) {
        self.store = store
        self.bill = bill
        _name = State(initialValue: bill?.name ?? "")
        _amount = State(initialValue: bill?.amount ?? 0)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("Internet"))
                .focused($isNameFocused)
            AmountField(
                "Estimate (\(store.settings.currencyCode))", value: $amount,
                currencyCode: store.settings.currencyCode, isValid: $isAmountValid)
            Text("A rounded guess is fine. This does not change your accounts.")
                .formHint()
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 440)
        .navigationTitle(bill == nil ? "New bill" : "Edit bill")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(bill == nil ? "Add" : "Save") {
                    if let bill {
                        store.updateBill(bill, name: name, amount: amount)
                    } else {
                        store.addBill(name: name, amount: amount)
                    }
                    dismiss()
                }
                .disabled(!canSave)
                .buttonStyle(.pill(.primary))
            }
        }
        .onAppear { isNameFocused = true }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isAmountValid && amount > 0
    }
}
