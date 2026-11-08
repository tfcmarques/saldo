import Foundation

enum AccountType: String, CaseIterable, Identifiable {
    case cash = "Cash"
    case checking = "Checking"
    case savings = "Savings"
    case investment = "Investment"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cash: "banknote"
        case .checking: "building.columns"
        case .savings: "lock"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }
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

/// A named preset (`blue`) or a custom `#RRGGBB` chosen in the color picker.
struct PaletteColor: Hashable, Identifiable {
    var rawValue: String

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static let blue = PaletteColor(preset: "blue")
    static let teal = PaletteColor(preset: "teal")
    static let green = PaletteColor(preset: "green")
    static let presets: [PaletteColor] = [
        "blue", "teal", "mint", "green", "cyan", "indigo",
        "purple", "pink", "red", "orange", "yellow", "brown",
    ].map { PaletteColor(preset: $0) }

    static var allCases: [PaletteColor] { presets }

    init(preset name: String) {
        rawValue = name
    }

    init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.rawValue = value
    }
}

typealias AccountColor = PaletteColor
typealias CategoryColor = PaletteColor

enum CategoryIcon: String, CaseIterable, Identifiable {
    case tag = "tag.fill"
    case food = "fork.knife"
    case groceries = "cart.fill"
    case coffee = "cup.and.saucer.fill"
    case drinks = "wineglass.fill"
    case transport = "car.fill"
    case fuel = "fuelpump.fill"
    case transit = "bus.fill"
    case travel = "airplane"
    case home = "house.fill"
    case utilities = "bolt.fill"
    case phone = "iphone"
    case technology = "laptopcomputer"
    case repairs = "wrench.and.screwdriver.fill"
    case shopping = "bag.fill"
    case clothing = "tshirt.fill"
    case health = "cross.case.fill"
    case fitness = "figure.run"
    case pets = "pawprint.fill"
    case family = "person.2.fill"
    case entertainment = "film.fill"
    case music = "music.note"
    case games = "gamecontroller.fill"
    case education = "graduationcap.fill"
    case books = "book.fill"
    case work = "briefcase.fill"
    case income = "banknote.fill"
    case savings = "lock.fill"
    case investment = "chart.line.uptrend.xyaxis"
    case insurance = "shield.fill"
    case subscriptions = "arrow.triangle.2.circlepath"
    case gift = "gift.fill"
    case charity = "heart.fill"
    case interest = "percent"
    case transfer = "arrow.left.arrow.right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tag: "General"
        case .food: "Food"
        case .groceries: "Groceries"
        case .coffee: "Coffee"
        case .drinks: "Drinks"
        case .transport: "Transport"
        case .fuel: "Fuel"
        case .transit: "Transit"
        case .travel: "Travel"
        case .home: "Home"
        case .utilities: "Utilities"
        case .phone: "Phone"
        case .technology: "Technology"
        case .repairs: "Repairs"
        case .shopping: "Shopping"
        case .clothing: "Clothing"
        case .health: "Health"
        case .fitness: "Fitness"
        case .pets: "Pets"
        case .family: "Family"
        case .entertainment: "Entertainment"
        case .music: "Music"
        case .games: "Games"
        case .education: "Education"
        case .books: "Books"
        case .work: "Work"
        case .income: "Income"
        case .savings: "Savings"
        case .investment: "Investment"
        case .insurance: "Insurance"
        case .subscriptions: "Subscriptions"
        case .gift: "Gift"
        case .charity: "Charity"
        case .interest: "Interest"
        case .transfer: "Transfer"
        }
    }
}

struct Account: Identifiable, Hashable {
    var id: UUID
    var name: String
    var type: AccountType
    var icon: AccountIcon
    var color: AccountColor
    var openingBalance: Double
    var createdAt: Date
    /// Empty means the account follows the app's base currency.
    var currencyCode: String = ""
    /// Off for money set aside, such as tax savings. The balance stays on the account.
    var countsInNetWorth: Bool = true
    /// Still in history and totals. Hidden from pickers for new entries and transfers.
    var isClosed: Bool = false

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

enum DebtDirection: String, CaseIterable, Identifiable {
    case iOwe = "I owe"
    case owedToMe = "Owed to me"

    var id: String { rawValue }

    var paymentKind: EntryKind {
        switch self {
        case .iOwe: .expense
        case .owedToMe: .income
        }
    }

    var paymentCategory: String {
        switch self {
        case .iOwe: "Debt payment"
        case .owedToMe: "Debt repayment"
        }
    }
}

enum DebtIcon: String, CaseIterable, Identifiable {
    case person = "person.fill"
    case people = "person.2.fill"
    case car = "car.fill"
    case house = "house.fill"
    case bank = "building.columns.fill"
    case card = "creditcard.fill"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .person: "Person"
        case .people: "People"
        case .car: "Car"
        case .house: "Home"
        case .bank: "Bank"
        case .card: "Card"
        }
    }
}

struct Debt: Identifiable, Hashable {
    var id: UUID
    var name: String
    var direction: DebtDirection
    var note: String
    var principal: Double
    var currencyCode: String
    var icon: DebtIcon
    var color: AccountColor
    var startedAt: Date
    var createdAt: Date

    init(
        name: String,
        direction: DebtDirection,
        note: String = "",
        principal: Double,
        currencyCode: String = "",
        icon: DebtIcon = .person,
        color: AccountColor = AccountColor(preset: "orange"),
        startedAt: Date = .now,
        createdAt: Date = .now
    ) {
        id = UUID()
        self.name = name
        self.direction = direction
        self.note = note
        self.principal = principal
        self.currencyCode = currencyCode
        self.icon = icon
        self.color = color
        self.startedAt = startedAt
        self.createdAt = createdAt
    }
}

struct Bill: Identifiable, Hashable {
    var id: UUID
    var name: String
    var amount: Double
    /// `yyyy-MM` when ticked off for that month. Empty means still due.
    var clearedMonth: String
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, amount: Double, clearedMonth: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.clearedMonth = clearedMonth
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
    /// The difference between the book balance and a value the user stated.
    case reconciliation
}

extension LedgerEntry {
    /// The note as shown. Older spare-change notes were written as "Spare change · Note".
    var displayNote: String {
        let legacy = "Spare change \u{00B7} "
        guard note.hasPrefix(legacy) else { return note }
        return "Spare change for " + note.dropFirst(legacy.count)
    }
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
    /// Transfer created to hold this expense's spare change, when it has one.
    var spareChangeTransferID: UUID?
    var source: EntrySource = .manual
    /// Set when this entry is a payment against a debt. `debtAmount` is in the debt's currency.
    var debtID: UUID?
    var debtAmount: Double = 0
    /// Pending payments with this off stay out of available cash and the other current totals.
    var countsInAvailable: Bool = true

    var isTransfer: Bool { transferID != nil }

    init(
        kind: EntryKind, category: String, note: String, amount: Double, date: Date,
        accountID: UUID,
        transferID: UUID? = nil, spareChangeTransferID: UUID? = nil, source: EntrySource = .manual,
        debtID: UUID? = nil, debtAmount: Double = 0, countsInAvailable: Bool = true
    ) {
        id = UUID()
        self.kind = kind
        self.category = category
        self.note = note
        self.amount = amount
        self.date = date
        self.accountID = accountID
        self.transferID = transferID
        self.spareChangeTransferID = spareChangeTransferID
        self.source = source
        self.debtID = debtID
        self.debtAmount = debtAmount
        self.countsInAvailable = countsInAvailable
    }
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

    /// How much bigger every font is than Standard.
    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.18
        }
    }
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

