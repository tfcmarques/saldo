import Foundation

enum AccountType: String, CaseIterable, Identifiable {
    case cash = "Cash"
    case checking = "Checking"
    case savings = "Savings"
    case creditCard = "Credit card"
    case investment = "Investment"

    var id: String { rawValue }
}

enum AccountIcon: String, CaseIterable, Identifiable {
    case wallet = "wallet.pass.fill"
    case bank = "building.columns.fill"
    case card = "creditcard.fill"
    case cash = "banknote.fill"
    case savings = "lock.fill"
    case investment = "chart.line.uptrend.xyaxis"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallet: "Wallet"
        case .bank: "Bank"
        case .card: "Card"
        case .cash: "Cash"
        case .savings: "Savings"
        case .investment: "Investment"
        }
    }
}

enum AccountColor: String, CaseIterable, Identifiable {
    case blue
    case teal
    case green
    case orange
    case pink
    case indigo
    case red

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CategoryIcon: String, CaseIterable, Identifiable {
    case tag = "tag.fill"
    case food = "fork.knife"
    case transport = "car.fill"
    case home = "house.fill"
    case shopping = "bag.fill"
    case health = "cross.case.fill"
    case entertainment = "film.fill"
    case work = "briefcase.fill"
    case gift = "gift.fill"
    case interest = "percent"
    case transfer = "arrow.left.arrow.right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tag: "General"
        case .food: "Food"
        case .transport: "Transport"
        case .home: "Home"
        case .shopping: "Shopping"
        case .health: "Health"
        case .entertainment: "Entertainment"
        case .work: "Work"
        case .gift: "Gift"
        case .interest: "Interest"
        case .transfer: "Transfer"
        }
    }
}

enum CategoryColor: String, CaseIterable, Identifiable {
    case blue
    case teal
    case green
    case orange
    case pink
    case purple
    case red

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Account: Identifiable, Hashable {
    var id: UUID
    var name: String
    var type: AccountType
    var icon: AccountIcon
    var color: AccountColor
    var openingBalance: Double
    var createdAt: Date
    var interestRate: Double = 0
    var interestTaxRate: Double = 0
    var interestAccruedThrough: Date?
    /// Empty means the account follows the app's base currency.
    var currencyCode: String = ""

    init(
        name: String,
        type: AccountType,
        icon: AccountIcon = .wallet,
        color: AccountColor = .blue,
        openingBalance: Double,
        createdAt: Date = .now
    ) {
        id = UUID()
        self.name = name
        self.type = type
        self.icon = icon
        self.color = color
        self.openingBalance = openingBalance
        self.createdAt = createdAt
    }
}

enum EntryKind: String, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"

    var id: String { rawValue }
}

enum EntrySource: String {
    case manual
    case interest
    case recurring
}

struct LedgerEntry: Identifiable, Hashable {
    var id: UUID
    var kind: EntryKind
    var category: String
    var note: String
    var amount: Double
    var date: Date
    var accountID: UUID
    var transferID: UUID?
    var source: EntrySource = .manual

    var isTransfer: Bool { transferID != nil }

    init(
        kind: EntryKind, category: String, note: String, amount: Double, date: Date,
        accountID: UUID,
        transferID: UUID? = nil, source: EntrySource = .manual
    ) {
        id = UUID()
        self.kind = kind
        self.category = category
        self.note = note
        self.amount = amount
        self.date = date
        self.accountID = accountID
        self.transferID = transferID
        self.source = source
    }
}

struct Budget: Identifiable, Hashable {
    var category: String
    /// Monthly limit in the app's base currency.
    var monthlyLimit: Double
    var id: String { category }
}

enum RecurrenceFrequency: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"

    var id: String { rawValue }
}

enum RecurringKind: String, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"

    var id: String { rawValue }
}

struct RecurringRule: Identifiable, Hashable {
    var id = UUID()
    var kind: RecurringKind
    var category: String
    var note: String
    /// In the source account's currency.
    var amount: Double
    var accountID: UUID
    var toAccountID: UUID?
    var frequency: RecurrenceFrequency
    var startDate: Date
    var endDate: Date?
    var generatedCount: Int = 0
    var isActive = true
}

struct LedgerCategory: Identifiable, Hashable {
    var name: String
    var icon: CategoryIcon
    var color: CategoryColor
    var id: String { name }

    init(name: String, icon: CategoryIcon = .tag, color: CategoryColor = .blue) {
        self.name = name
        self.icon = icon
        self.color = color
    }
}

enum LedgerDateFormat: String, CaseIterable, Identifiable {
    case dayMonthYear = "dd-MM-yyyy"
    case monthDayYear = "MM/dd/yyyy"
    case yearMonthDay = "yyyy-MM-dd"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dayMonthYear: "Day-Month-Year"
        case .monthDayYear: "Month/Day/Year"
        case .yearMonthDay: "Year-Month-Day"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

enum AppFontSize: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case large = "Large"

    var id: String { rawValue }
}

struct AppSettings: Hashable {
    var currencyCode: String
    var dateFormat: LedgerDateFormat
    var theme: AppTheme
    var fontSize: AppFontSize
    var defaultImportedCategoryIcon: CategoryIcon = .tag
    var defaultImportedCategoryColor: CategoryColor = .blue
    /// 0 disables auto-lock.
    var autoLockMinutes: Int = 5
    /// The Mac user Saldo was registered to on first launch.
    var ownerUsername: String = ""
    var ownerName: String = ""

    var isRegistered: Bool { !ownerUsername.isEmpty }

    var ownerFirstName: String {
        ownerName.split(separator: " ").first.map(String.init) ?? ownerUsername
    }

    static let `default` = AppSettings(
        currencyCode: Locale.current.currency?.identifier ?? "USD",
        dateFormat: .dayMonthYear,
        theme: .system,
        fontSize: .standard,
        defaultImportedCategoryIcon: .tag,
        defaultImportedCategoryColor: .blue,
        autoLockMinutes: 5
    )
}

struct CSVImportSummary {
    var importedEntries: Int
    var createdAccounts: Int
    var createdCategories: Int
    var skippedRows: Int
    var duplicateRows: Int = 0
}
