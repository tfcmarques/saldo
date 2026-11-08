import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case ledger = "Ledger"
    case accounts = "Accounts"
    case bills = "Bills"
    case settings = "Settings"

    var id: String { rawValue }

    /// Sections listed at the top of the sidebar. Settings sits on its own at the bottom.
    static let main: [AppSection] = [.dashboard, .ledger, .accounts, .bills]

    var symbol: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .ledger: "list.bullet.rectangle"
        case .accounts: "building.columns"
        case .bills: "checklist"
        case .settings: "gearshape"
        }
    }
}

enum AppSheet: Identifiable {
    case newEntry(EntryKind)
    case newScheduledPayment
    case newScheduledRefund
    case editEntry(LedgerEntry)
    case newTransfer
    case editTransfer(LedgerEntry)
    case newAccount
    case editAccount(Account)
    case reconcileAccount(Account?)
    case newDebt
    case editDebt(Debt)
    case payDebt(Debt)
    case debtDetail(UUID)
    case categories
    case newBill
    case editBill(Bill)

    var id: String {
        switch self {
        case .newEntry(let kind): "newEntry-\(kind.rawValue)"
        case .newScheduledPayment: "newScheduledPayment"
        case .newScheduledRefund: "newScheduledRefund"
        case .editEntry(let entry): "editEntry-\(entry.id)"
        case .newTransfer: "newTransfer"
        case .editTransfer(let entry): "editTransfer-\(entry.id)"
        case .newAccount: "newAccount"
        case .editAccount(let account): "editAccount-\(account.id)"
        case .reconcileAccount(let account): "reconcile-\(account?.id.uuidString ?? "choose")"
        case .newDebt: "newDebt"
        case .editDebt(let debt): "editDebt-\(debt.id)"
        case .payDebt(let debt): "payDebt-\(debt.id)"
        case .debtDetail(let id): "debtDetail-\(id)"
        case .categories: "categories"
        case .newBill: "newBill"
        case .editBill(let bill): "editBill-\(bill.id)"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selection: AppSection = .dashboard
    var sheet: AppSheet?
    /// Bumped by ⌘F; the ledger focuses its search field when it changes.
    var searchRequest = 0
}

let supportedCurrencies = [
    "USD", "EUR", "GBP", "BRL", "CAD", "AUD", "JPY", "CHF", "SEK", "NOK", "DKK", "PLN", "MXN",
    "CNY", "INR",
]
