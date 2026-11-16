import Foundation
import SwiftUI

/// Debug builds only. Launch with `SALDO_TEST_DATA_DIR=/some/folder` to keep every file and
/// preference away from the real Saldo data, skip Touch ID, and fill an empty ledger with samples.
/// Release builds (scripts/build-app.sh) compile this out, so the real app always authenticates.
enum TestDataMode {
    #if DEBUG
        static let folder: URL? = ProcessInfo.processInfo.environment["SALDO_TEST_DATA_DIR"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    #else
        static let folder: URL? = nil
    #endif

    static var isActive: Bool { folder != nil }

    /// Sample owner for test data, so screenshots never show the real Mac account.
    static var ownerName: String? { isActive ? "Alex Morgan" : nil }

    /// True while UISnapshots is capturing pages.
    static var isSnapshotting: Bool {
        isActive && ProcessInfo.processInfo.environment["SALDO_SNAPSHOT_DIR"] != nil
    }

    /// Stands in for ~/Library/Application Support.
    static var applicationSupport: URL {
        folder
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    // UserDefaults is thread-safe; it just is not marked Sendable.
    nonisolated(unsafe) static let defaults: UserDefaults =
        isActive ? UserDefaults(suiteName: "local.saldo.app.testdata") ?? .standard : .standard
}

/// A page's vertical scroll view. While snapshotting it lays content out flat instead,
/// because AppKit does not draw scroll view content into an offscreen image.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if TestDataMode.isSnapshotting {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content }
        }
    }
}

extension LedgerStore {
    /// Fills an empty test ledger with a few months of made-up activity. Never runs on real data.
    func seedSampleDataIfEmpty() {
        guard TestDataMode.isActive, accounts.isEmpty, entries.isEmpty else { return }
        writesSuspended = true
        defer { writesSuspended = false }
        assert(CategoryIcon.suggested(for: "Transport") == .transport)
        assert(CategoryIcon.suggested(for: "Eating out") == .food)
        assert(CategoryIcon.suggested(for: "Parents") == .tag)
        // Test data skips the welcome screen, which is where the owner is normally registered.
        if !settings.isRegistered { registerCurrentUser() }

        addAccount(name: "Wallet", type: .cash, openingBalance: 650)
        addAccount(name: "Everyday", type: .checking, openingBalance: 2_400)
        addAccount(name: "Rainy day", type: .savings, openingBalance: 5_000)
        addAccount(name: "Index fund", type: .investment, openingBalance: 8_000)
        addAccount(name: "Travel USD", type: .checking, openingBalance: 300, currencyCode: "USD")
        guard let wallet = accounts.first(where: { $0.name == "Wallet" }),
            let everyday = accounts.first(where: { $0.name == "Everyday" }),
            let savings = accounts.first(where: { $0.name == "Rainy day" }),
            let fund = accounts.first(where: { $0.name == "Index fund" })
        else { return }

        let calendar = Calendar.current
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
        }
        let expenses: [(String, String, Double)] = [
            ("Groceries", "Supermarket", 64.30), ("Coffee", "Corner café", 3.20),
            ("Transport", "Metro card", 40), ("Eating out", "Dinner with friends", 48.75),
            ("Groceries", "Market", 22.10), ("Shopping", "Running shoes", 89.99),
            ("Utilities", "Electricity", 71.45), ("Health", "Pharmacy", 12.60),
        ]
        for offset in stride(from: 0, through: 120, by: 2) {
            let (category, note, amount) = expenses[offset / 2 % expenses.count]
            addEntry(
                kind: .expense, category: category, note: note,
                amount: amount + Double(offset % 7), date: day(offset),
                accountID: offset % 12 == 0 ? wallet.id : everyday.id,
                spareChangeAccountID: offset % 10 == 0 ? savings.id : nil)
        }
        for month in 0..<4 {
            addEntry(
                kind: .income, category: "Salary", note: "Monthly pay", amount: 2_850,
                date: day(month * 30 + 1), accountID: everyday.id)
            addTransfer(
                from: everyday.id, to: savings.id, amount: 300, receivedAmount: 300,
                date: day(month * 30), note: "Monthly saving")
        }
        reconcileAccount(fund, to: 8_420, note: "", date: day(45))
        addEntry(
            kind: .expense, category: "Utilities", note: "Internet", amount: 35,
            date: calendar.date(byAdding: .day, value: 5, to: .now) ?? .now,
            accountID: everyday.id)
        _ = addBill(name: "Rent", amount: 950)
        _ = addBill(name: "Phone", amount: 18)
        _ = addDebt(
            name: "Sam", direction: .owedToMe, note: "Concert tickets", principal: 120,
            currencyCode: settings.currencyCode, icon: .person, color: .blue, startedAt: day(20))

        writesSuspended = false
        do {
            try persist()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#if DEBUG
    import AppKit

    /// With test data and `SALDO_SNAPSHOT_DIR`, renders each section at two widths to PNGs,
    /// then quits. Draws the window itself, so it needs no Screen Recording permission.
    @MainActor
    enum UISnapshots {
        private static var hasStarted = false

        static func runIfRequested(router: AppRouter, store: LedgerStore) {
            let environment = ProcessInfo.processInfo.environment
            // `SALDO_TEST_THEME=Glass` opens test data in that theme, for trying it by hand.
            if TestDataMode.isActive, !hasStarted,
                let theme = environment["SALDO_TEST_THEME"].flatMap(AppTheme.init(rawValue:))
            {
                hasStarted = true
                store.updateTheme(theme)
                // `SALDO_TEST_CLICK=80,152` then clicks that point (from the window's top
                // left), prints the section that ends up selected, and quits.
                let point = (environment["SALDO_TEST_CLICK"] ?? "").split(separator: ",")
                    .compactMap { Double($0) }
                if point.count == 2 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        guard
                            let window = NSApp.windows.first(where: {
                                $0.isVisible && $0.canBecomeMain
                            })
                        else { return }
                        let location = NSPoint(x: point[0], y: window.frame.height - point[1])
                        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            if let event = NSEvent.mouseEvent(
                                with: type, location: location, modifierFlags: [],
                                timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: window.windowNumber, context: nil,
                                eventNumber: 0, clickCount: 1, pressure: 1)
                            {
                                window.sendEvent(event)
                            }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        try? await Task.sleep(for: .seconds(1))
                        print("selected:", router.selection.rawValue)
                        NSApp.terminate(nil)
                    }
                }
            }
            // A theme or text size change rebuilds the window and calls this again.
            guard !hasStarted, TestDataMode.isActive,
                let path = ProcessInfo.processInfo.environment["SALDO_SNAPSHOT_DIR"]
            else { return }
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            hasStarted = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
                else { return }
                // The first drawn image comes back blank; draw once and throw it away.
                save(window, to: folder.appendingPathComponent(".warmup.png"))
                for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    NSApp.appearance = NSAppearance(named: appearance)
                    for width in [1440.0] {
                        window.setContentSize(NSSize(width: width, height: 900))
                        // Switch away first so the starting section redraws at the new size.
                        router.selection = .bills
                        try? await Task.sleep(for: .seconds(1))
                        for section in AppSection.allCases {
                            router.selection = section
                            // A hidden window skips drawing scroll content; keep it in front.
                            NSApp.activate(ignoringOtherApps: true)
                            window.orderFrontRegardless()
                            try? await Task.sleep(for: .seconds(1))
                            save(
                                window,
                                to: folder.appendingPathComponent(
                                    "\(section.rawValue)-\(Int(width))-\(name).png"))
                        }
                    }
                }
                // The Ambient and Glass themes, dark then light.
                for theme in [AppTheme.ambient, .glass] {
                    store.updateTheme(theme)
                    for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                        NSApp.appearance = NSAppearance(named: appearance)
                        for section in AppSection.allCases {
                            router.selection = section
                            NSApp.activate(ignoringOtherApps: true)
                            window.orderFrontRegardless()
                            try? await Task.sleep(for: .seconds(1))
                            save(
                                window,
                                to: folder.appendingPathComponent(
                                    "\(section.rawValue)-\(theme.rawValue)-\(name).png"))
                        }
                    }
                }
                store.updateTheme(.system)
                try? await Task.sleep(for: .seconds(1))
                // The same page at the Large text size, then back to Standard.
                store.updateFontSize(.large)
                router.selection = .ledger
                try? await Task.sleep(for: .seconds(1.5))
                save(window, to: folder.appendingPathComponent("Ledger-large.png"))
                store.updateFontSize(.standard)
                try? await Task.sleep(for: .seconds(1))
                save(window, to: folder.appendingPathComponent("Ledger-standard.png"))
                router.selection = .ledger
                // Every sheet, so forms can be reviewed without clicking through the app.
                var sheets: [(String, AppSheet)] = [
                    ("NewEntry", .newEntry(.expense)), ("NewScheduledPayment", .newScheduledPayment),
                    ("NewTransfer", .newTransfer), ("NewAccount", .newAccount),
                    ("UpdateValue", .reconcileAccount(store.openAccounts.first)),
                    ("NewDebt", .newDebt), ("Categories", .categories), ("NewBill", .newBill),
                ]
                if let entry = store.entries.first(where: { !$0.isTransfer }) {
                    sheets.append(("EditEntry", .editEntry(entry)))
                }
                if let debt = store.debts.first {
                    sheets += [("DebtDetail", .debtDetail(debt.id)), ("PayDebt", .payDebt(debt))]
                }
                for (name, sheet) in sheets {
                    router.sheet = sheet
                    try? await Task.sleep(for: .seconds(1.2))
                    if let attached = window.attachedSheet {
                        save(attached, to: folder.appendingPathComponent("\(name).png"))
                    }
                    router.sheet = nil
                    try? await Task.sleep(for: .seconds(0.8))
                }
                NSApp.terminate(nil)
            }
        }

        private static func save(_ window: NSWindow, to url: URL) {
            guard let view = window.contentView?.superview ?? window.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
#endif
