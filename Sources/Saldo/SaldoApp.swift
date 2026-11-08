import AppKit
import SwiftUI

@main
struct SaldoApp: App {
    @NSApplicationDelegateAdaptor(SaldoApplicationDelegate.self) private var appDelegate
    @State private var store = LedgerStore()
    @State private var appLock = AppLock()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup(SaldoBrand.name) {
            AppRootView(store: store, appLock: appLock)
                .environment(router)
        }
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
                .disabled(!appLock.isUnlocked || store.accounts.isEmpty)
            Button("New Transfer") { router.sheet = .newTransfer }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!appLock.isUnlocked || store.accounts.count < 2)
            Button("New Account") { router.sheet = .newAccount }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!appLock.isUnlocked)
            Divider()
            Button("Lock Saldo") { appLock.lock() }
                .keyboardShortcut("l")
                .disabled(!appLock.isUnlocked)
        }
        CommandMenu("Go") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
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

    var body: some View {
        Group {
            if appLock.isUnlocked {
                AppNavigationView(store: store, appLock: appLock)
            } else if !store.settings.isRegistered {
                WelcomeScreen(store: store, appLock: appLock)
            } else {
                LockScreen(store: store, appLock: appLock)
            }
        }
        .onAppear {
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
                catchUp()
            } else {
                router.sheet = nil
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            if appLock.isUnlocked {
                appLock.lockIfIdle()
                catchUp()
            } else {
                appLock.authenticate()
            }
        }
        .preferredColorScheme(themeOverride(for: store.settings.theme))
        .dynamicTypeSize(textSizeOverride(for: store.settings.fontSize))
    }

    private func catchUp() {
        store.accrueInterest()
        store.generateRecurringEntries()
    }
}

struct AppNavigationView: View {
    let store: LedgerStore
    let appLock: AppLock
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    SaldoMark(size: 32)
                    Text(SaldoBrand.name)
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        appLock.lock()
                    } label: {
                        Image(systemName: "lock")
                    }
                    .buttonStyle(.borderless)
                    .help("Lock Saldo")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                List(
                    AppSection.allCases,
                    selection: Binding<AppSection?>(
                        get: { router.selection },
                        set: { router.selection = $0 ?? .dashboard }
                    )
                ) { section in
                    Label(section.rawValue, systemImage: section.symbol)
                        .tag(section)
                }

                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.settings.ownerName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text("Registered Mac user")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } detail: {
            switch router.selection {
            case .dashboard: DashboardView(store: store)
            case .ledger: LedgerView(store: store)
            case .accounts: AccountsView(store: store)
            case .recurring: RecurringView(store: store)
            case .budgets: BudgetsView(store: store)
            case .settings: SettingsView(store: store, appLock: appLock)
            }
        }
        .sheet(item: $router.sheet) { sheet in
            NavigationStack {
                sheetContent(sheet)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .newEntry(let kind): AddEntrySheet(store: store, initialKind: kind)
        case .editEntry(let entry): AddEntrySheet(store: store, entry: entry)
        case .newTransfer: TransferSheet(store: store)
        case .editTransfer(let entry): TransferSheet(store: store, entry: entry)
        case .newAccount: AddAccountSheet(store: store)
        case .editAccount(let account): EditAccountSheet(store: store, account: account)
        case .newRecurring: RecurringSheet(store: store, rule: nil)
        case .editRecurring(let rule): RecurringSheet(store: store, rule: rule)
        case .editBudget(let category): BudgetSheet(store: store, category: category)
        case .exchangeRate(let code): ExchangeRateSheet(store: store, code: code)
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

private func textSizeOverride(for fontSize: AppFontSize) -> DynamicTypeSize {
    switch fontSize {
    case .standard: .medium
    case .large: .large
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
                        .fill(Color.accentColor)
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
