import AppKit
import Charts
import Collaboration
import SwiftUI

/// Saldo's design tokens. Colours, type, spacing and radii come from here, not from views.
enum DS {
    /// True while the Ambient theme is on. AppRootView sets it and rebuilds the window.
    nonisolated(unsafe) static var isAmbient = false
    /// True while the Glass theme is on: frosted panels on green and black, with a Liquid
    /// Glass sidebar and controls. Only ever true where `supportsGlass` is.
    nonisolated(unsafe) static var isGlass = false

    static var supportsGlass: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// Each token has a standard pair, an Ambient pair (light, dark) and a Glass value.
    /// Glass is green on black and always dark.
    enum Palette {
        static let background = Color(light: 0xFFFFFF, dark: 0x000000, ambient: (0xF1F2F3, 0x080910), glass: 0x050A08)
        static let surface = Color(light: 0xF4F4F4, dark: 0x16181A, ambient: (0xFFFFFF, 0x14151D), glass: 0x0E1512)
        static let surfaceSubtle = Color(light: 0xF7F7F7, dark: 0x1C1E21, ambient: (0xE9EAEC, 0x0D0E15), glass: 0x0A100D)
        static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x242629, ambient: (0xFFFFFF, 0x20212B), glass: 0x1A2620)
        static let border = Color(light: 0xE2E2E7, dark: 0x2A2D31, ambient: (0xDFE0E2, 0x23242D), glass: 0x22302A)
        static let textPrimary = Color(light: 0x191C1F, dark: 0xFFFFFF, ambient: (0x17181D, 0xF7F7F8), glass: 0xF2F7F4)
        static let textSecondary = Color(light: 0x505A63, dark: 0xA0A4AA, ambient: (0x5E5F6A, 0x92939D), glass: 0xA3B0A9)
        static let textMuted = Color(light: 0x8D969E, dark: 0x70767D, ambient: (0x858690, 0x6C6D78), glass: 0x74827B)
        static let accent = Color(light: 0x494FDF, dark: 0x6E73F2, ambient: (0x2878FF, 0x2878FF), glass: 0x2FBF83)
        static let accentHover = Color(light: 0x4F55F1, dark: 0x8287F5, ambient: (0x3154F5, 0x4A8DFF), glass: 0x45D398)
        static let success = Color(light: 0x00A87E, dark: 0x1FC497, ambient: (0x00A982, 0x00CFA5), glass: 0x4ADE9F)
        static let warning = Color(light: 0xEC7E00, dark: 0xFF9A2E, ambient: (0xD97706, 0xFFA63D), glass: 0xE0A84A)
        static let danger = Color(light: 0xE23B4A, dark: 0xFF5C69, ambient: (0xE8421A, 0xFF572B), glass: 0xEB7563)
        /// Primary buttons: dark on light, light on dark.
        static let inverse = Color(light: 0x191C1F, dark: 0xFFFFFF, ambient: (0x17181D, 0xF7F7F8), glass: 0xF2F7F4)
        static let onInverse = Color(light: 0xFFFFFF, dark: 0x191C1F, ambient: (0xFFFFFF, 0x17181D), glass: 0x07100C)
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
        static var small: CGFloat { DS.isAmbient ? 10 : 8 }
        static var control: CGFloat { DS.isAmbient ? 16 : 12 }
        static var card: CGFloat { DS.isAmbient ? 28 : DS.isGlass ? 24 : 16 }
        static var large: CGFloat { DS.isAmbient ? 36 : 20 }
    }

    /// Sizes are macOS points at the Standard text size. The Text size setting multiplies
    /// them by `scale`; AppRootView sets it and rebuilds the window when it changes.
    @MainActor
    enum Typeface {
        static var scale: CGFloat = 1

        static func size(_ points: CGFloat) -> CGFloat { (points * scale).rounded() }

        /// Ambient keeps large figures light and headings medium.
        private static var strong: Font.Weight { DS.isAmbient ? .medium : .semibold }
        private static var figureWeight: Font.Weight { DS.isAmbient ? .regular : .semibold }

        static var display: Font {
            .system(size: size(DS.isAmbient ? 52 : 40), weight: figureWeight)
        }
        static var pageTitle: Font { .system(size: size(26), weight: strong) }
        static var figure: Font {
            .system(size: size(DS.isAmbient ? 30 : 26), weight: figureWeight)
        }
        static var title1: Font { .system(size: size(22), weight: strong) }
        static var title2: Font { .system(size: size(17), weight: strong) }
        static var title3: Font { .system(size: size(15), weight: strong) }
        static var body: Font { .system(size: size(13)) }
        static var bodyStrong: Font { .system(size: size(13), weight: .medium) }
        static var small: Font { .system(size: size(12)) }
        static var caption: Font { .system(size: size(10)) }
        static var micro: Font { .system(size: size(10)) }
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
    }
}

extension Color {
    /// A colour that follows the window's light or dark appearance, and the Ambient theme.
    init(
        light: UInt32, dark: UInt32, ambient: (light: UInt32, dark: UInt32)? = nil,
        glass: UInt32? = nil
    ) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                var pair = (light: light, dark: dark)
                if DS.isAmbient, let ambient { pair = ambient }
                if DS.isGlass, let glass { pair = (glass, glass) }
                let hex = isDark ? pair.dark : pair.light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1)
            })
    }

    init(hex: UInt32) { self.init(light: hex, dark: hex) }
}

// MARK: - Surfaces

/// A card's fill. The Ambient theme adds coloured light, a hairline edge and a soft shadow.
struct CardBackground: View {
    /// The light's colour: the main colour of what the card shows. Nil is a faint silver.
    var glow: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        if DS.isAmbient {
            let dark = scheme == .dark
            let strength = (dark ? 1 : 0.6) * (glow == nil ? 0.3 : 1)
            let primary = glow ?? DS.Palette.textSecondary
            let secondary = primary
            shape.fill(DS.Palette.surface)
                .overlay {
                    ZStack {
                        EllipticalGradient(
                            colors: [primary.opacity(0.2 * strength), primary.opacity(0)],
                            center: .topTrailing, endRadiusFraction: 0.8)
                        EllipticalGradient(
                            colors: [secondary.opacity(0.09 * strength), secondary.opacity(0)],
                            center: UnitPoint(x: 0.1, y: 1.15), endRadiusFraction: 0.6)
                    }
                    .clipShape(shape)
                }
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                DS.Palette.textPrimary.opacity(0.16),
                                DS.Palette.textPrimary.opacity(0.05),
                            ], startPoint: .top, endPoint: .bottom))
                )
                .shadow(color: .black.opacity(dark ? 0.35 : 0.07), radius: 16, y: 8)
        } else if DS.isGlass {
            // A frosted panel: faint white fill, a lit top edge and a soft shadow. The
            // backdrop is smooth light, so a real blur would look the same and cost more.
            shape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.1), .white.opacity(0.035)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.04)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        } else {
            shape.fill(DS.Palette.surface)
        }
    }
}

private struct WindowSizeKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    /// Size of the whole window, measured by AppRootView on the backdrop.
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

private struct PageHeaderBackground: ViewModifier {
    @Environment(\.windowSize) private var windowSize

    func body(content: Content) -> some View {
        if DS.isGlass {
            // The window's backdrop again, cut to the header, so no seam shows. The header
            // sits in the window's top right corner.
            content.background {
                Color.clear
                    .overlay(alignment: .topTrailing) {
                        // Clipping does not clip clicks: without this the window-sized
                        // backdrop swallows every click in the window.
                        PageBackdrop()
                            .frame(width: windowSize.width, height: windowSize.height)
                            .allowsHitTesting(false)
                    }
                    .clipped()
            }
        } else {
            content.background(DS.Palette.background)
        }
    }
}

/// What sits behind the window. The Glass theme adds soft green light for the panels and
/// glass above it to pick up.
struct PageBackdrop: View {
    var body: some View {
        if DS.isGlass {
            ZStack {
                DS.Palette.background
                light(0.34, radius: 0.8, at: UnitPoint(x: 0.1, y: 0))
                light(0.26, radius: 0.7, at: UnitPoint(x: 1, y: 0.85))
                light(0.12, radius: 0.45, at: UnitPoint(x: 0.55, y: 0.45))
            }
        } else {
            DS.Palette.background
        }
    }

    private func light(_ opacity: Double, radius: Double, at center: UnitPoint) -> some View {
        EllipticalGradient(
            colors: [DS.Palette.accent.opacity(opacity), DS.Palette.accent.opacity(0)],
            center: center, endRadiusFraction: radius)
    }
}

private struct Surface: ViewModifier {
    var padding: CGFloat
    var fillHeight: Bool
    var glow: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(
                maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(CardBackground(glow: glow))
    }
}

extension View {
    /// A grouped area on the page background. `glow` tints the card's light in the Ambient theme.
    func surface(
        padding: CGFloat = DS.Space.l, fillHeight: Bool = false, glow: Color? = nil
    ) -> some View {
        modifier(Surface(padding: padding, fillHeight: fillHeight, glow: glow))
    }

    /// Page background for a section's root view.
    func pageBackground() -> some View {
        // Glass pages show the one backdrop AppRootView draws behind the whole window.
        background { if !DS.isGlass { DS.Palette.background } }
    }

    /// A capsule control's fill: Liquid Glass in the Glass theme, otherwise a flat colour.
    @ViewBuilder
    func capsuleFill(_ color: Color, glassTint: Color? = nil, glass: Bool = true) -> some View {
        if DS.isGlass, glass, #available(macOS 26, *) {
            glassEffect(.regular.tint(glassTint).interactive(), in: .capsule)
        } else {
            background(color, in: Capsule())
        }
    }

    /// Behind a pinned `PageHeader`, so scrolled content does not show through the title.
    func pageHeaderBackground() -> some View {
        modifier(PageHeaderBackground())
    }

    /// Explanation under a form field: small, secondary, never the main message.
    func formHint() -> some View {
        font(DS.Typeface.caption).foregroundStyle(DS.Palette.textSecondary)
    }

    /// Lists drawn on the page background instead of the system's grouped grey.
    func pageList() -> some View {
        scrollContentBackground(.hidden).background {
            if !DS.isGlass { DS.Palette.background }
        }
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
                .capsuleFill(background, glassTint: glassTint, glass: kind != .tertiary)
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
            case .accent: DS.isGlass ? DS.Palette.onInverse : .white
            case .secondary, .tertiary: DS.Palette.textPrimary
            case .destructive: DS.Palette.danger
            }
        }

        private var glassTint: Color? {
            switch kind {
            case .primary, .accent: DS.Palette.accent
            case .destructive: DS.Palette.danger.opacity(0.2)
            case .secondary, .tertiary: nil
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

/// "Today", "Yesterday", then the weekday and date. The year only shows when it is not this one.
func dayTitle(_ day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
    return day.formatted(
        sameYear
            ? .dateTime.weekday(.wide).day().month(.wide)
            : .dateTime.day().month(.wide).year())
}

/// Thin progress track. Unlike the system's bar it draws nothing at zero.
struct ProgressBar: View {
    let value: Double
    let total: Double
    var tint: Color = DS.Palette.success

    private var fraction: Double { min(max(value / max(total, 0.01), 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(DS.Palette.border)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: geometry.size.width * fraction)
                }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
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
    var accessoryBadge: StatusBadge?
    /// No sign or colour, for a transfer shown as one row: it neither adds nor removes money.
    var neutralAmount = false

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
                MoneyText(
                    amount: neutralAmount ? abs(amount) : amount, currencyCode: currencyCode,
                    signed: !neutralAmount)
                if let badge { badge }
                if let accessoryBadge { accessoryBadge }
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
        .capsuleFill(DS.Palette.textPrimary.opacity(0.06))
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
