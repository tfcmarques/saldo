import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case ledger = "Ledger"
    case accounts = "Accounts"
    case recurring = "Recurring"
    case budgets = "Budgets"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .ledger: "list.bullet.rectangle"
        case .accounts: "building.columns"
        case .recurring: "arrow.triangle.2.circlepath"
        case .budgets: "chart.bar.doc.horizontal"
        case .settings: "gearshape"
        }
    }
}

enum AppSheet: Identifiable {
    case newEntry(EntryKind)
    case editEntry(LedgerEntry)
    case newTransfer
    case editTransfer(LedgerEntry)
    case newAccount
    case editAccount(Account)
    case newRecurring
    case editRecurring(RecurringRule)
    case editBudget(String?)
    case exchangeRate(String)

    var id: String {
        switch self {
        case .newEntry(let kind): "newEntry-\(kind.rawValue)"
        case .editEntry(let entry): "editEntry-\(entry.id)"
        case .newTransfer: "newTransfer"
        case .editTransfer(let entry): "editTransfer-\(entry.id)"
        case .newAccount: "newAccount"
        case .editAccount(let account): "editAccount-\(account.id)"
        case .newRecurring: "newRecurring"
        case .editRecurring(let rule): "editRecurring-\(rule.id)"
        case .editBudget(let category): "editBudget-\(category ?? "new")"
        case .exchangeRate(let code): "exchangeRate-\(code)"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selection: AppSection = .dashboard
    var sheet: AppSheet?
}

let supportedCurrencies = [
    "USD", "EUR", "GBP", "BRL", "CAD", "AUD", "JPY", "CHF", "SEK", "NOK", "DKK", "PLN", "MXN",
    "CNY", "INR",
]
