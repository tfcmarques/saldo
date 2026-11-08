import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: LedgerStore
    let appLock: AppLock
    @State private var isShowingResetConfirmation = false
    @State private var isResetAuthenticating = false
    @State private var resetError = ""
    @State private var isShowingResetError = false
    @State private var dataMessage = ""
    @State private var dataError = ""
    @State private var isShowingDataError = false
    @State private var pendingRestoreURL: URL?
    @State private var editingRateCode: String?

    private var currencyOptions: [String] {
        Array(Set(supportedCurrencies + [store.settings.currencyCode])).sorted()
    }

    private let lockOptions = [0, 1, 5, 15, 30]

    var body: some View {
        Form {
            Section("Display") {
                Picker(
                    "Main currency",
                    selection: Binding(
                        get: { store.settings.currencyCode },
                        set: { store.updateCurrency($0) }
                    )
                ) {
                    ForEach(currencyOptions, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                Picker(
                    "Date format",
                    selection: Binding(
                        get: { store.settings.dateFormat },
                        set: { store.updateDateFormat($0) }
                    )
                ) {
                    ForEach(LedgerDateFormat.allCases) { format in
                        Text("\(format.title) (\(format.rawValue))").tag(format)
                    }
                }
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { store.settings.theme },
                        set: { store.updateTheme($0) }
                    )
                ) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                Picker(
                    "Text size",
                    selection: Binding(
                        get: { store.settings.fontSize },
                        set: { store.updateFontSize($0) }
                    )
                ) {
                    ForEach(AppFontSize.allCases) { fontSize in
                        Text(fontSize.rawValue).tag(fontSize)
                    }
                }
            }

            if !store.foreignCurrencies.isEmpty {
                Section("Exchange rates") {
                    ForEach(store.foreignCurrencies, id: \.self) { code in
                        HStack {
                            Text(code)
                            Spacer()
                            if let rate = store.exchangeRates[code] {
                                Text(
                                    "1 \(code) = \(rate.formatted(.number.precision(.fractionLength(0...6)))) \(store.settings.currencyCode)"
                                )
                                .foregroundStyle(DS.Palette.textSecondary)
                            } else {
                                Text("Rate needed").foregroundStyle(DS.Palette.warning)
                            }
                            Button("Edit rate", systemImage: "pencil") {
                                editingRateCode = code
                            }
                            .buttonStyle(.icon)
                            .help("Edit the exchange rate for \(code)")
                        }
                    }
                    Text(
                        "Totals and charts convert foreign accounts to your main currency using these rates."
                    )
                    .formHint()
                }
            }

            Section("Security") {
                Picker(
                    "Lock after inactivity",
                    selection: Binding(
                        get: { store.settings.autoLockMinutes },
                        set: { store.updateAutoLockMinutes($0) }
                    )
                ) {
                    ForEach(lockOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? "Never" : "\(minutes) min").tag(minutes)
                    }
                }
                Text("You can also lock at any time with \u{2318}L.")
                    .formHint()
                LabeledContent(
                    "Registered to",
                    value: "\(store.settings.ownerName) (\(store.settings.ownerUsername))")
                Text(
                    "The ledger is encrypted on this Mac. Touch ID or your Mac password unlocks it, and the data stays in memory only while Saldo is unlocked."
                )
                .formHint()
            }

            Section("Backup") {
                HStack(spacing: DS.Space.xs) {
                    Button("Export CSV\u{2026}", systemImage: "square.and.arrow.up") {
                        exportCSV()
                    }
                    .help("Save every entry as a spreadsheet file")
                    Button("Back up\u{2026}", systemImage: "externaldrive") {
                        backupDatabase()
                    }
                    .help("Save an encrypted copy of the database")
                    Button("Restore\u{2026}", systemImage: "arrow.counterclockwise") {
                        chooseBackupToRestore()
                    }
                    .help("Replace your data with a backup")
                }
                .buttonStyle(.pill(.secondary, compact: true))
                if let latest = store.latestAutomaticBackupLabel {
                    Text("Latest automatic backup: \(latest).")
                        .formHint()
                }
                Text(
                    "Saldo keeps an encrypted backup on this Mac once a day, for 30 days. A backup only opens in Saldo on this Mac."
                )
                .formHint()
                if !dataMessage.isEmpty {
                    Label(dataMessage, systemImage: "checkmark")
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.success)
                }
            }

            Section("About") {
                HStack(spacing: 12) {
                    SaldoMark(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SaldoBrand.name).font(DS.Typeface.title3)
                        Text(SaldoBrand.tagline)
                            .formHint()
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Delete data") {
                Text(
                    "Permanently delete all accounts, entries, categories, bills, settings, and automatic backups from this Mac."
                )
                .formHint()
                Button("Delete all data", systemImage: "trash", role: .destructive) {
                    isShowingResetConfirmation = true
                }
                .buttonStyle(.pill(.destructive, compact: true))
                .disabled(isResetAuthenticating)
                .help("Erase everything Saldo stores on this Mac")
                if isResetAuthenticating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for Touch ID")
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .pageList()
        .navigationTitle("Settings")
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Settings")
                .background(DS.Palette.background)
        }
        .sheet(
            isPresented: Binding(
                get: { editingRateCode != nil },
                set: { if !$0 { editingRateCode = nil } }
            )
        ) {
            if let editingRateCode {
                NavigationStack {
                    ExchangeRateSheet(store: store, code: editingRateCode)
                }
            }
        }
        .confirmationDialog(
            "Delete all Saldo data?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all data", role: .destructive) {
                confirmReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. You will verify with Touch ID before anything is deleted.")
        }
        .alert("Data was not deleted", isPresented: $isShowingResetError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetError)
        }
        .alert("Backup action failed", isPresented: $isShowingDataError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dataError)
        }
        .confirmationDialog(
            "Replace all data with this backup?",
            isPresented: Binding(
                get: { pendingRestoreURL != nil },
                set: { if !$0 { pendingRestoreURL = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace data", role: .destructive) { confirmRestore() }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text(
                "Your current data is replaced. A copy of it is kept as saldo-before-restore.sealed. You will verify your identity first."
            )
        }
    }

    private var dateStamp: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    private func showDataError(_ error: Error) {
        dataError = error.localizedDescription
        isShowingDataError = true
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "saldo-export-\(dateStamp).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportCSV(to: url)
            dataMessage = "Exported \(store.entries.count) entries."
        } catch {
            showDataError(error)
        }
    }

    private func backupDatabase() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "saldo") ?? .data]
        panel.nameFieldStringValue = "saldo-backup-\(dateStamp).saldo"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.backupDatabase(to: url)
            dataMessage = "Backup saved."
        } catch {
            showDataError(error)
        }
    }

    private func chooseBackupToRestore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "saldo") ?? .data,
            UTType(filenameExtension: "sealed") ?? .data,
            UTType(filenameExtension: "sqlite") ?? .data,
            .data,
        ]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingRestoreURL = url
    }

    private func confirmRestore() {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil
        appLock.authenticateForDestructiveAction(reason: "Confirm restoring a Saldo backup.") {
            verified in
            guard verified else {
                dataError = "Identity was not verified. Nothing was changed."
                isShowingDataError = true
                return
            }
            do {
                try store.restoreDatabase(from: url)
                dataMessage = "Backup restored."
            } catch {
                showDataError(error)
            }
        }
    }

    private func confirmReset() {
        isResetAuthenticating = true
        appLock.authenticateForDestructiveAction { verified in
            isResetAuthenticating = false
            guard verified else {
                resetError = "Touch ID did not verify. No data was deleted."
                isShowingResetError = true
                return
            }
            store.deleteAllData()
        }
    }

}

struct AddCategorySheet: View {
    let store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var icon: CategoryIcon = .tag
    @State private var color: CategoryColor = .blue

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .focused($isNameFocused)
            Picker("Icon", selection: $icon) {
                ForEach(CategoryIcon.allCases) { icon in
                    Label(icon.title, systemImage: Symbol.outline(icon.rawValue)).tag(icon)
                }
            }
            PaletteColorPicker(label: "Color", color: $color)
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 440)
        .navigationTitle("New category")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    store.addCategory(name: name, icon: icon, color: color)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.pill(.primary))
            }
        }
        .onAppear { isNameFocused = true }
    }
}

struct EditCategorySheet: View {
    let store: LedgerStore
    let category: LedgerCategory
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var icon: CategoryIcon
    @State private var color: CategoryColor

    init(store: LedgerStore, category: LedgerCategory) {
        self.store = store
        self.category = category
        _name = State(initialValue: category.name)
        _icon = State(initialValue: category.icon)
        _color = State(initialValue: category.color)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .focused($isNameFocused)
            Picker("Icon", selection: $icon) {
                ForEach(CategoryIcon.allCases) { icon in
                    Label(icon.title, systemImage: Symbol.outline(icon.rawValue)).tag(icon)
                }
            }
            PaletteColorPicker(label: "Color", color: $color)
            Text("Renaming this category updates every entry that uses it.")
                .formHint()
        }
        .formStyle(.grouped)
        .pageList()
        .frame(width: 420)
        .navigationTitle("Edit category")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.updateCategory(category, name: name, icon: icon, color: color)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.pill(.primary))
            }
        }
        .onAppear { isNameFocused = true }
    }
}

/// Every category with how often it is used. Opened from the Ledger.
struct CategoriesSheet: View {
    let store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var editing: LedgerCategory?
    @State private var pendingDeletion: LedgerCategory?

    private func entryCount(_ category: LedgerCategory) -> Int {
        store.entries.filter {
            $0.category.caseInsensitiveCompare(category.name) == .orderedSame
        }.count
    }

    var body: some View {
        List {
            ForEach(store.categories) { category in
                let count = entryCount(category)
                HStack(spacing: DS.Space.s) {
                    IconBubble(systemName: category.icon.rawValue, tint: category.color.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(DS.Typeface.bodyStrong)
                            .foregroundStyle(DS.Palette.textPrimary)
                        DetailLine([count == 1 ? "1 entry" : "\(count) entries"])
                    }
                    Spacer()
                    Button("Edit \(category.name)", systemImage: "pencil") { editing = category }
                        .buttonStyle(.icon)
                        .help("Rename \(category.name) or change its icon and colour")
                    if category.name.caseInsensitiveCompare("Uncategorized") != .orderedSame {
                        Button("Delete \(category.name)", systemImage: "trash", role: .destructive) {
                            pendingDeletion = category
                        }
                        .buttonStyle(.icon)
                        .help("Delete \(category.name)")
                    }
                }
                .padding(.vertical, DS.Space.xxs)
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editing = category }
                    if category.name.caseInsensitiveCompare("Uncategorized") != .orderedSame {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = category
                        }
                    }
                }
            }
        }
        .pageList()
        .frame(width: 440, height: 520)
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .buttonStyle(.pill(.secondary))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("New category", systemImage: "plus") { isAdding = true }
                    .buttonStyle(.pill(.primary))
                    .help("Create a category you can use on entries")
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack { AddCategorySheet(store: store) }
        }
        .sheet(item: $editing) { category in
            NavigationStack { EditCategorySheet(store: store, category: category) }
        }
        .confirmationDialog(
            pendingDeletion.map { "Delete \($0.name)?" } ?? "Delete this category?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion { store.deleteCategory(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            if let pendingDeletion {
                let count = entryCount(pendingDeletion)
                Text(
                    count == 0
                        ? "No entries use this category."
                        : "\(count) \(count == 1 ? "entry moves" : "entries move") to Uncategorized. This cannot be undone."
                )
            }
        }
    }
}
