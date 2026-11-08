import SwiftUI

/// Flat, full-height navigation column. Replaces the system's floating sidebar.
struct Sidebar: View {
    let store: LedgerStore
    let appLock: AppLock
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.xs) {
                SaldoMark(size: 26)
                Text(SaldoBrand.name)
                    .font(DS.Typeface.title3)
                    .foregroundStyle(DS.Palette.textPrimary)
            }
            .padding(.horizontal, DS.Space.m)
            // Clears the window's traffic lights, which sit over this column.
            .padding(.top, DS.Layout.chromeTop)
            .padding(.bottom, DS.Space.l)

            VStack(spacing: 2) {
                ForEach(AppSection.main) { section in
                    item(section)
                }
            }

            Spacer(minLength: DS.Space.l)

            VStack(spacing: 2) {
                item(.settings)
                Button {
                    appLock.lock()
                } label: {
                    row(title: "Lock Saldo", symbol: "lock", isSelected: false)
                }
                .buttonStyle(.plain)
                .help("Lock Saldo (⌘L)")
            }

            Rectangle()
                .fill(DS.Palette.border)
                .frame(height: 1)
                .padding(.vertical, DS.Space.s)

            HStack(spacing: DS.Space.xs) {
                UserAvatar(name: store.settings.ownerName, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.settings.ownerName)
                        .font(DS.Typeface.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Text("Registered Mac user")
                        .font(DS.Typeface.micro)
                        .foregroundStyle(DS.Palette.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.bottom, DS.Space.m)
        }
        .padding(.horizontal, DS.Space.s)
        .frame(width: 232)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.Palette.surfaceSubtle)
        .ignoresSafeArea()
    }

    private func item(_ section: AppSection) -> some View {
        Button {
            router.selection = section
        } label: {
            row(title: section.rawValue, symbol: section.symbol,
                isSelected: router.selection == section)
        }
        .buttonStyle(.plain)
        .help(shortcutHint(for: section))
        .accessibilityAddTraits(router.selection == section ? .isSelected : [])
    }

    private func shortcutHint(for section: AppSection) -> String {
        if section == .settings { return "Settings (⌘,)" }
        guard let index = AppSection.main.firstIndex(of: section) else { return section.rawValue }
        return "\(section.rawValue) (⌘\(index + 1))"
    }

    private func row(title: String, symbol: String, isSelected: Bool) -> some View {
        SidebarRow(title: title, symbol: symbol, isSelected: isSelected)
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
            Text(title)
                .font(DS.Typeface.bodyStrong)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .background(
            background,
            in: RoundedRectangle(cornerRadius: DS.Radius.control - 2, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.quick, value: isHovered)
    }

    private var background: Color {
        if isSelected { return DS.Palette.surfaceRaised }
        return DS.Palette.textPrimary.opacity(isHovered ? 0.05 : 0)
    }
}
