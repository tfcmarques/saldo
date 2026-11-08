import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: LedgerStore
    let appLock: AppLock
    @State private var isAddingCategory = false
    @State private var editingCategory: LedgerCategory?
    @State private var isImporting = false
    @State private var didCopyCSVTemplate = false
    @State private var importSummary: CSVImportSummary?
    @State private var importError = ""
    @State private var isShowingImportError = false
    @State private var isShowingResetConfirmation = false
    @State private var isResetAuthenticating = false
    @State private var resetError = ""
    @State private var isShowingResetError = false
    @State private var dataMessage = ""
    @State private var dataError = ""
    @State private var isShowingDataError = false
    @State private var pendingRestoreURL: URL?
    @Environment(AppRouter.self) private var router

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
                Picker(
                    "Imported category icon",
                    selection: Binding(
                        get: { store.settings.defaultImportedCategoryIcon },
                        set: { store.updateDefaultImportedCategoryIcon($0) }
                    )
                ) {
                    ForEach(CategoryIcon.allCases) { icon in
                        Label(icon.title, systemImage: icon.rawValue).tag(icon)
                    }
                }
                Picker(
                    "Imported category color",
                    selection: Binding(
                        get: { store.settings.defaultImportedCategoryColor },
                        set: { store.updateDefaultImportedCategoryColor($0) }
                    )
                ) {
                    ForEach(CategoryColor.allCases) { color in
                        CategoryColorLabel(color: color).tag(color)
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
                                .foregroundStyle(.secondary)
                            } else {
                                Text("Rate needed").foregroundStyle(.orange)
                            }
                            Button("Edit rate", systemImage: "pencil") {
                                router.sheet = .exchangeRate(code)
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    Text(
                        "Totals, charts and budgets convert foreign accounts to your main currency using these rates."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(
                    "Registered to",
                    value: "\(store.settings.ownerName) (\(store.settings.ownerUsername))")
                Text(
                    "Saldo unlocks with your fingerprint or your Mac password. Lock it any time with \u{2318}L."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Categories") {
                Button("Add category", systemImage: "plus") { isAddingCategory = true }
                ForEach(store.categories) { category in
                    HStack {
                        Image(systemName: category.icon.rawValue)
                            .frame(width: 20)
                            .foregroundStyle(category.color.color)
                        Text(category.name)
                        Spacer()
                        Button("Edit category", systemImage: "pencil") {
                            editingCategory = category
                        }
                        .labelStyle(.iconOnly)
                        if category.name.caseInsensitiveCompare("Uncategorized") != .orderedSame {
                            Button("Delete category", systemImage: "trash", role: .destructive) {
                                store.deleteCategory(category)
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }

            Section("Import") {
                Button("Import CSV", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                Button("Copy CSV template", systemImage: "doc.on.doc") {
                    copyCSVTemplate()
                }
                Text("Flow, Account, Category, Amount, Description, Date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "Dates use dd-MM-yyyy. Optional columns: Currency (for new accounts) and TransferID. Missing accounts and categories are created automatically; entries that already exist are skipped."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if didCopyCSVTemplate {
                    Label("CSV template copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let importSummary {
                    Text(
                        "Imported \(importSummary.importedEntries) entries. Added \(importSummary.createdAccounts) accounts and \(importSummary.createdCategories) categories. Skipped \(importSummary.duplicateRows) duplicates and \(importSummary.skippedRows) invalid rows."
                    )
                    .font(.caption)
                }
            }

            Section("Backup") {
                Button("Export entries as CSV\u{2026}", systemImage: "square.and.arrow.up") {
                    exportCSV()
                }
                Button("Back up database\u{2026}", systemImage: "externaldrive") {
                    backupDatabase()
                }
                Button("Restore from backup\u{2026}", systemImage: "arrow.counterclockwise") {
                    chooseBackupToRestore()
                }
                if !dataMessage.isEmpty {
                    Label(dataMessage, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("About") {
                HStack(spacing: 12) {
                    SaldoMark(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SaldoBrand.name).font(.headline)
                        Text(SaldoBrand.tagline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Danger Zone") {
                Text(
                    "Permanently delete all accounts, entries, categories, and settings from this Mac."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Delete all data", systemImage: "trash", role: .destructive) {
                    isShowingResetConfirmation = true
                }
                .disabled(isResetAuthenticating)
                if isResetAuthenticating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for Touch ID")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $isAddingCategory) {
            NavigationStack {
                AddCategorySheet(store: store)
            }
        }
        .sheet(item: $editingCategory) { category in
            NavigationStack {
                EditCategorySheet(store: store, category: category)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText]) {
            result in
            switch result {
            case .success(let url):
                do {
                    importSummary = try store.importCSV(from: url)
                } catch {
                    importError = error.localizedDescription
                    isShowingImportError = true
                }
            case .failure(let error):
                importError = error.localizedDescription
                isShowingImportError = true
            }
        }
        .alert("CSV import failed", isPresented: $isShowingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError)
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
                "Your current data is replaced. A copy of it is kept as saldo-before-restore.sqlite. You will verify your identity first."
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
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.nameFieldStringValue = "saldo-backup-\(dateStamp).sqlite"
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
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data, .data]
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

    private func copyCSVTemplate() {
        let template = """
            Flow,Account,Category,Amount,Description,Date
            Expense,Checking,Food,42.50,Dinner,28-09-2026
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(template, forType: .string)
        didCopyCSVTemplate = true
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
                    Label(icon.title, systemImage: icon.rawValue).tag(icon)
                }
            }
            Picker("Color", selection: $color) {
                ForEach(CategoryColor.allCases) { color in
                    CategoryColorLabel(color: color).tag(color)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .navigationTitle("New category")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    store.addCategory(name: name, icon: icon, color: color)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Label(icon.title, systemImage: icon.rawValue).tag(icon)
                }
            }
            Picker("Color", selection: $color) {
                ForEach(CategoryColor.allCases) { color in
                    CategoryColorLabel(color: color).tag(color)
                }
            }
            Text("Renaming this category updates every entry that uses it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .navigationTitle("Edit category")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.updateCategory(category, name: name, icon: icon, color: color)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { isNameFocused = true }
    }
}
