import AppKit
import SwiftUI

@main
struct SaldoApp: App {
    @NSApplicationDelegateAdaptor(SaldoApplicationDelegate.self) private var appDelegate
    @State private var store = LedgerStore()
    @State private var appLock = AppLock()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup(TestDataMode.isActive ? "\(SaldoBrand.name) (test data)" : SaldoBrand.name) {
            AppRootView(store: store, appLock: appLock)
                .environment(router)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            AppCommands(store: store, appLock: appLock, router: router)
        }
    }
}

struct AppCommands: Commands {
    let store: LedgerStore
    let appLock: AppLock
    let router: AppRouter

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") { router.sheet = .newEntry(.expense) }
                .keyboardShortcut("n")
                .disabled(!appLock.isUnlocked || store.openAccounts.isEmpty)
            Button("Schedule Payment") { router.sheet = .newScheduledPayment }
                .keyboardShortcut("n", modifiers: [.command, .option, .shift])
                .disabled(!appLock.isUnlocked || store.openAccounts.isEmpty)
            Button("Schedule Refund") { router.sheet = .newScheduledRefund }
                .disabled(!appLock.isUnlocked || store.openAccounts.isEmpty)
            Button("New Transfer") { router.sheet = .newTransfer }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!appLock.isUnlocked || store.openAccounts.count < 2)
            Button("New Account") { router.sheet = .newAccount }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!appLock.isUnlocked)
            Button("Update Account Value") {
                router.sheet = .reconcileAccount(store.openAccounts.first)
            }
            .disabled(!appLock.isUnlocked || store.openAccounts.isEmpty)
            Divider()
            Button("Lock Saldo") { appLock.lock() }
                .keyboardShortcut("l")
                .disabled(!appLock.isUnlocked)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") { router.selection = .settings }
                .keyboardShortcut(",")
                .disabled(!appLock.isUnlocked)
        }
        CommandGroup(after: .textEditing) {
            Button("Find in Ledger") {
                router.selection = .ledger
                router.searchRequest += 1
            }
            .keyboardShortcut("f")
            .disabled(!appLock.isUnlocked)
        }
        CommandMenu("Go") {
            ForEach(Array(AppSection.main.enumerated()), id: \.element) { index, section in
                Button(section.rawValue) { router.selection = section }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(index + 1))), modifiers: .command
                    )
                    .disabled(!appLock.isUnlocked)
            }
        }
    }
}

final class SaldoApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        if Bundle.main.bundleURL.pathExtension != "app", let icon = AppIcon.image {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct AppRootView: View {
    let store: LedgerStore
    let appLock: AppLock
    @Environment(AppRouter.self) private var router
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        // The type scale reads this; AppNavigationView's .id rebuilds the pages when it changes.
        let _ = DS.Typeface.scale = store.settings.fontSize.scale
        Group {
            if appLock.isUnlocked {
                AppNavigationView(store: store, appLock: appLock)
                    // Settings live in here, so changing Text size rebuilds every page.
                    .id(store.settings.fontSize)
            } else if !store.hasExistingDatabase && !store.settings.isRegistered {
                WelcomeScreen(store: store, appLock: appLock)
            } else {
                LockScreen(store: store, appLock: appLock)
            }
        }
        .onAppear {
            WindowSizing.fillScreen()
            appLock.ownerUsername = store.settings.ownerUsername
            appLock.startActivityMonitoring()
            appLock.authenticate()
        }
        .onChange(of: store.settings.ownerUsername) { _, username in
            appLock.ownerUsername = username
        }
        .onChange(of: store.settings.autoLockMinutes, initial: true) { _, minutes in
            appLock.autoLockMinutes = minutes
        }
        .onChange(of: appLock.isUnlocked) { _, isUnlocked in
            if isUnlocked {
                if let error = store.open(using: appLock.authorization) {
                    appLock.noteLockedOut(error)
                }
            } else if let error = store.close() {
                store.saveError = error
                appLock.noteStillUnlocked(error)
            } else {
                router.sheet = nil
                // Undo steps hold deleted entries in memory; drop them with the database.
                undoManager?.removeAllActions()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
        ) { _ in
            _ = store.close()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            if appLock.isUnlocked {
                appLock.lockIfIdle()
            } else if !appLock.pausesAutomaticUnlock {
                appLock.authenticate()
            }
        }
        .font(DS.Typeface.body)
        .tint(DS.Palette.accent)
        .preferredColorScheme(themeOverride(for: store.settings.theme))
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { store.saveError != nil },
                set: { if !$0 { store.saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.saveError = nil }
        } message: {
            Text(store.saveError ?? "")
        }
    }
}

struct AppNavigationView: View {
    let store: LedgerStore
    let appLock: AppLock
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        HStack(spacing: 0) {
            Sidebar(store: store, appLock: appLock)
            Rectangle()
                .fill(DS.Palette.border)
                .frame(width: 1)
                .ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Page headers set their own top inset, the same in a window and in full screen.
                .ignoresSafeArea(.container, edges: .top)
                .pageBackground()
        }
        .sheet(item: $router.sheet) { sheet in
            NavigationStack {
                sheetContent(sheet)
            }
            .font(DS.Typeface.body)
        }
        #if DEBUG
            .onAppear { UISnapshots.runIfRequested(router: router, store: store) }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch router.selection {
        case .dashboard: DashboardView(store: store)
        case .ledger: LedgerView(store: store)
        case .accounts: AccountsView(store: store)
        case .bills: BillsView(store: store)
        case .settings: SettingsView(store: store, appLock: appLock)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .newEntry(let kind): AddEntrySheet(store: store, initialKind: kind)
        case .newScheduledPayment: AddEntrySheet(store: store, schedulePayment: true)
        case .newScheduledRefund:
            AddEntrySheet(store: store, initialKind: .income, schedulePayment: true)
        case .editEntry(let entry): AddEntrySheet(store: store, entry: entry)
        case .newTransfer: TransferSheet(store: store)
        case .editTransfer(let entry): TransferSheet(store: store, entry: entry)
        case .newAccount: AccountSheet(store: store)
        case .editAccount(let account): AccountSheet(store: store, account: account)
        case .reconcileAccount(let account): ReconcileAccountSheet(store: store, account: account)
        case .newDebt: DebtSheet(store: store)
        case .editDebt(let debt): DebtSheet(store: store, debt: debt)
        case .payDebt(let debt): PayDebtSheet(store: store, debt: debt)
        case .debtDetail(let id): DebtDetailSheet(store: store, debtID: id)
        case .categories: CategoriesSheet(store: store)
        case .newBill: BillSheet(store: store, bill: nil)
        case .editBill(let bill): BillSheet(store: store, bill: bill)
        }
    }
}

private func themeOverride(for theme: AppTheme) -> ColorScheme? {
    switch theme {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
}

struct SaldoMark: View {
    var size: CGFloat = 42

    var body: some View {
        Group {
            if let image = AppIcon.image {
                // The artwork keeps a transparent margin; scale it back up to fill the frame.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(1.22)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28)
                        .fill(DS.Palette.accent)
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: size * 0.52, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(SaldoBrand.name)
    }
}

/// Saldo opens filling the screen as a normal window, so the window buttons stay visible.
/// Full screen (its own Space) hides them, so a window restored in full screen leaves it first.
@MainActor
enum WindowSizing {
    static func fillScreen() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
            else { return }
            window.isRestorable = false
            guard window.styleMask.contains(.fullScreen) else {
                zoom(window)
                return
            }
            let exits = NotificationCenter.default.notifications(
                named: NSWindow.didExitFullScreenNotification, object: window)
            window.toggleFullScreen(nil)
            Task { @MainActor in
                for await _ in exits {
                    zoom(window)
                    break
                }
            }
        }
    }

    private static func zoom(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.visibleFrame, display: true, animate: false)
    }
}
