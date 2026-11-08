import AppKit
import Charts
import Collaboration
import SwiftUI

/// Saldo's design tokens. Colours, type, spacing and radii come from here, not from views.
enum DS {
    enum Palette {
        static let background = Color(light: 0xFFFFFF, dark: 0x000000)
        static let surface = Color(light: 0xF4F4F4, dark: 0x16181A)
        static let surfaceSubtle = Color(light: 0xF7F7F7, dark: 0x1C1E21)
        static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x242629)
        static let border = Color(light: 0xE2E2E7, dark: 0x2A2D31)
        static let textPrimary = Color(light: 0x191C1F, dark: 0xFFFFFF)
        static let textSecondary = Color(light: 0x505A63, dark: 0xA0A4AA)
        static let textMuted = Color(light: 0x8D969E, dark: 0x70767D)
        static let accent = Color(light: 0x494FDF, dark: 0x6E73F2)
        static let accentHover = Color(light: 0x4F55F1, dark: 0x8287F5)
        static let success = Color(light: 0x00A87E, dark: 0x1FC497)
        static let warning = Color(light: 0xEC7E00, dark: 0xFF9A2E)
        static let danger = Color(light: 0xE23B4A, dark: 0xFF5C69)
        /// Primary buttons: dark on light, light on dark.
        static let inverse = Color(light: 0x191C1F, dark: 0xFFFFFF)
        static let onInverse = Color(light: 0xFFFFFF, dark: 0x191C1F)
    }

    /// 4-point scale.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Layout {
        /// Top inset of the sidebar brand and every page title, clear of the window buttons.
        static let chromeTop: CGFloat = 44
    }

    enum Radius {
        /// Tooltips and other small floating labels.
        static let small: CGFloat = 8
        static let control: CGFloat = 12
        static let card: CGFloat = 16
        static let large: CGFloat = 20
    }

    enum Typeface {
        static let display = Font.system(size: 40, weight: .semibold)
        static let pageTitle = Font.system(size: 26, weight: .semibold)
        static let figure = Font.system(size: 26, weight: .semibold)
        static let title1 = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)
        static let body = Font.body
        static let bodyStrong = Font.body.weight(.medium)
        static let small = Font.callout
        static let caption = Font.caption
        static let micro = Font.caption2
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
    }
}

extension Color {
    /// A colour that follows the window's light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let hex = isDark ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1)
            })
    }
}

// MARK: - Surfaces

private struct Surface: ViewModifier {
    var padding: CGFloat
    var fillHeight: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(
                maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(
                DS.Palette.surface,
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

extension View {
    /// A grouped area on the page background. No shadow, no border.
    func surface(padding: CGFloat = DS.Space.l, fillHeight: Bool = false) -> some View {
        modifier(Surface(padding: padding, fillHeight: fillHeight))
    }

    /// Page background for a section's root view.
    func pageBackground() -> some View {
        background(DS.Palette.background)
    }

    /// Explanation under a form field: small, secondary, never the main message.
    func formHint() -> some View {
        font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
    }

    /// Lists drawn on the page background instead of the system's grouped grey.
    func pageList() -> some View {
        scrollContentBackground(.hidden).background(DS.Palette.background)
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, tertiary, accent, destructive }
    var kind: Kind = .primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, compact: compact)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(compact ? DS.Typeface.small.weight(.medium) : DS.Typeface.bodyStrong)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, compact ? DS.Space.s : DS.Space.m)
                .padding(.vertical, compact ? 5 : DS.Space.xs)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(DS.Motion.quick, value: configuration.isPressed)
                .animation(DS.Motion.quick, value: isHovered)
                .onHover { isHovered = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .primary: DS.Palette.onInverse
            case .accent: .white
            case .secondary, .tertiary: DS.Palette.textPrimary
            case .destructive: DS.Palette.danger
            }
        }

        private var background: Color {
            let active = isHovered || configuration.isPressed
            switch kind {
            case .primary: return DS.Palette.inverse.opacity(active ? 0.85 : 1)
            case .accent: return active ? DS.Palette.accentHover : DS.Palette.accent
            case .secondary: return DS.Palette.textPrimary.opacity(active ? 0.12 : 0.07)
            case .tertiary: return DS.Palette.textPrimary.opacity(active ? 0.07 : 0)
            case .destructive: return DS.Palette.danger.opacity(active ? 0.2 : 0.12)
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind = .primary, compact: Bool = false)
        -> PillButtonStyle
    {
        PillButtonStyle(kind: kind, compact: compact)
    }
}

// MARK: - Small components

enum Tone {
    case neutral, accent, success, warning, danger

    var color: Color {
        switch self {
        case .neutral: DS.Palette.textSecondary
        case .accent: DS.Palette.accent
        case .success: DS.Palette.success
        case .warning: DS.Palette.warning
        case .danger: DS.Palette.danger
        }
    }
}

/// Compact pill for statuses like "Scheduled" or a change in value.
struct StatusBadge: View {
    let text: String
    var systemImage: String?
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(DS.Typeface.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(tone.color)
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, 3)
        .background(tone.color.opacity(0.12), in: Capsule())
    }
}

/// Round avatar with an outline symbol, used for accounts, categories and transfers.
struct IconBubble: View {
    let systemName: String
    var tint: Color = DS.Palette.accent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: Symbol.outline(systemName))
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

/// An amount in tabular figures. Money coming in is green with a plus sign.
struct MoneyText: View {
    let amount: Double
    let currencyCode: String
    var font: Font = DS.Typeface.bodyStrong
    /// Colours income green and prefixes "+". Off for balances.
    var signed = false

    var body: some View {
        Text(formatted)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(signed && amount > 0 ? DS.Palette.success : DS.Palette.textPrimary)
            .lineLimit(1)
    }

    private var formatted: String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: currencyCode)
        return signed ? amount.formatted(style.sign(strategy: .always()))
            : amount.formatted(style)
    }
}

/// Secondary facts side by side, told apart by space and tone. Saldo never joins text with
/// separator glyphs (dots, bars, dashes).
struct DetailLine: View {
    let parts: [String]

    init(_ parts: [String]) {
        self.parts = parts.filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                    .foregroundStyle(index == 0 ? DS.Palette.textSecondary : DS.Palette.textMuted)
            }
        }
        .font(DS.Typeface.caption)
        .lineLimit(1)
    }
}

/// Small grey heading above a group of rows.
struct SectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(DS.Typeface.small.weight(.semibold))
            .foregroundStyle(DS.Palette.textSecondary)
    }
}

/// Saldo stores some SF Symbols in their filled form; the UI draws the outline family.
@MainActor
enum Symbol {
    private static var cache: [String: String] = [:]

    static func outline(_ name: String) -> String {
        if let cached = cache[name] { return cached }
        var outline = name
        if name.hasSuffix(".fill") {
            let candidate = String(name.dropLast(5))
            if NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
                outline = candidate
            }
        }
        if outline == name, name.contains(".fill.") {
            let candidate = name.replacingOccurrences(of: ".fill.", with: ".")
            if NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
                outline = candidate
            }
        }
        cache[name] = outline
        return outline
    }
}

// MARK: - Charts

/// Y axis with faint dashed gridlines and muted labels.
@AxisContentBuilder
func quietYAxis() -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            .foregroundStyle(DS.Palette.border)
        AxisValueLabel()
            .foregroundStyle(DS.Palette.textMuted)
    }
}

// MARK: - Rows

/// One ledger line: round icon, title over detail, signed amount on the right.
struct TransactionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let details: [String]
    let amount: Double
    let currencyCode: String
    var badge: StatusBadge?

    var body: some View {
        HStack(spacing: DS.Space.s) {
            IconBubble(systemName: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typeface.bodyStrong)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                DetailLine(details)
            }
            Spacer(minLength: DS.Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(amount: amount, currencyCode: currencyCode, signed: true)
                if let badge { badge }
            }
        }
        .padding(.vertical, DS.Space.xxs)
    }
}

// MARK: - Page structure

/// Title row at the top of every section, with that section's actions as pills.
struct PageHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typeface.pageTitle)
                    .tracking(-0.3)
                    .foregroundStyle(DS.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typeface.small)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            Spacer(minLength: DS.Space.m)
            HStack(spacing: DS.Space.xs) { actions }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Layout.chromeTop)
        .padding(.bottom, DS.Space.m)
    }
}

extension PageHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct PillOption<Value: Hashable> {
    let value: Value
    let label: String
    var systemImage: String?
}

/// A choice shown as a pill that opens a native menu with checkmarks, icons and a header.
/// `allOption` ("All accounts") sits first, above a divider.
struct PillPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    var allOption: PillOption<Value>?
    let options: [PillOption<Value>]
    var help: String?

    private var selected: PillOption<Value>? {
        ([allOption].compactMap { $0 } + options).first { $0.value == selection }
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                if let allOption {
                    row(allOption)
                    Divider()
                }
                ForEach(options, id: \.value) { row($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: DS.Space.xxs) {
                if let image = selected?.systemImage {
                    Image(systemName: Symbol.outline(image))
                }
                Text(selected?.label ?? title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.pill(.secondary, compact: true))
        .fixedSize()
        .help(help ?? title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func row(_ option: PillOption<Value>) -> some View {
        if let image = option.systemImage {
            Label(option.label, systemImage: Symbol.outline(image)).tag(option.value)
        } else {
            Text(option.label).tag(option.value)
        }
    }
}

/// Round, icon-only button for row actions like edit and delete.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    DS.Palette.textPrimary.opacity(
                        configuration.isPressed ? 0.12 : isHovered ? 0.07 : 0),
                    in: Circle()
                )
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.35)
                .animation(DS.Motion.quick, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

/// Text field in a pill, with a magnifying glass and a clear button.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.Palette.textMuted)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused(focus)
            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Palette.textMuted)
            }
        }
        .font(DS.Typeface.small)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 6)
        .frame(width: 240)
        .background(DS.Palette.textPrimary.opacity(0.06), in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                focus.wrappedValue ? DS.Palette.accent : .clear, lineWidth: 1.5)
        )
        .animation(DS.Motion.quick, value: focus.wrappedValue)
    }
}

// MARK: - People

/// The Mac account's picture, from the same place the login window reads it.
@MainActor
enum MacUser {
    static let picture: NSImage? = {
        guard !TestDataMode.isActive else { return nil }
        let identity = CBIdentity(name: NSUserName(), authority: CBIdentityAuthority.default())
        return (identity as? CBUserIdentity)?.image
    }()
}

/// Round avatar: the Mac profile picture, or initials when there is none.
struct UserAvatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let picture = MacUser.picture {
                Image(nsImage: picture)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(DS.Palette.onInverse)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Palette.inverse)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
