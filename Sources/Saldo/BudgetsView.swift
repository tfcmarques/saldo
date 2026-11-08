import SwiftUI

struct BudgetsView: View {
    let store: LedgerStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if store.budgets.isEmpty {
                ContentUnavailableView(
                    "No budgets yet",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Set a monthly limit for a category to track your spending.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(Date.now.formatted(.dateTime.month(.wide).year())) {
                        ForEach(store.budgets) { budget in
                            BudgetRow(store: store, budget: budget)
                        }
                    }
                }
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add budget", systemImage: "plus") { router.sheet = .editBudget(nil) }
                    .disabled(store.categories.allSatisfy { category in
                        store.budgets.contains {
                            $0.category.caseInsensitiveCompare(category.name) == .orderedSame
                        }
                    })
            }
        }
    }
}

private struct BudgetRow: View {
    let store: LedgerStore
    let budget: Budget
    @Environment(AppRouter.self) private var router

    private var spent: Double { store.spent(in: budget.category) }
    private var ratio: Double { budget.monthlyLimit > 0 ? spent / budget.monthlyLimit : 0 }
    private var category: LedgerCategory? {
        store.categories.first {
            $0.name.caseInsensitiveCompare(budget.category) == .orderedSame
        }
    }

    private var tint: Color {
        if ratio > 1 { return .red }
        return ratio >= 0.8 ? .orange : .green
    }

    var body: some View {
        let code = store.settings.currencyCode
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: category?.icon.rawValue ?? "tag.fill")
                    .foregroundStyle(category?.color.color ?? Color.accentColor)
                    .frame(width: 20)
                Text(budget.category).fontWeight(.medium)
                Spacer()
                Text("\(spent.formatted(.currency(code: code))) of \(budget.monthlyLimit.formatted(.currency(code: code)))")
                    .font(.subheadline)
                Button {
                    router.sheet = .editBudget(budget.category)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit budget")
            }
            ProgressView(value: min(ratio, 1))
                .tint(tint)
            Text(
                ratio > 1
                    ? "\((spent - budget.monthlyLimit).formatted(.currency(code: code))) over budget"
                    : "\((budget.monthlyLimit - spent).formatted(.currency(code: code))) left"
            )
            .font(.caption)
            .foregroundStyle(ratio > 1 ? .red : .secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { router.sheet = .editBudget(budget.category) }
            Button("Remove budget", systemImage: "trash", role: .destructive) {
                store.deleteBudget(budget)
            }
        }
    }
}

struct BudgetSheet: View {
    let store: LedgerStore
    let category: String?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: String
    @State private var limit: Double

    init(store: LedgerStore, category: String?) {
        self.store = store
        self.category = category
        let available = Self.availableCategories(store: store, editing: category)
        _selectedCategory = State(initialValue: category ?? available.first ?? "")
        _limit = State(
            initialValue: store.budgets.first { $0.category == category }?.monthlyLimit ?? 0)
    }

    private static func availableCategories(store: LedgerStore, editing: String?) -> [String] {
        store.categories.map(\.name).filter { name in
            name == editing
                || !store.budgets.contains {
                    $0.category.caseInsensitiveCompare(name) == .orderedSame
                }
        }
    }

    var body: some View {
        Form {
            if let category {
                LabeledContent("Category", value: category)
            } else {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(Self.availableCategories(store: store, editing: nil), id: \.self) {
                        Text($0).tag($0)
                    }
                }
            }
            TextField(
                "Monthly limit (\(store.settings.currencyCode))", value: $limit,
                format: .number.precision(.fractionLength(2)))
            Text("Spending is counted per calendar month in your main currency. Transfers are ignored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .navigationTitle(category == nil ? "New budget" : "Edit budget")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.setBudget(category: selectedCategory, monthlyLimit: limit)
                    dismiss()
                }
                .disabled(selectedCategory.isEmpty || limit <= 0)
            }
        }
    }
}
