import AppKit
import SwiftUI

extension PaletteColor {
    var color: Color {
        if let components = Self.rgbComponents(in: rawValue) {
            return Color(red: components.r, green: components.g, blue: components.b)
        }
        switch rawValue.lowercased() {
        case "blue": return Color.blue
        case "teal": return Color.teal
        case "mint": return Color.mint
        case "green": return Color.green
        case "cyan": return Color.cyan
        case "indigo": return Color.indigo
        case "purple": return Color.purple
        case "pink": return Color.pink
        case "red": return Color.red
        case "orange": return Color.orange
        case "yellow": return Color.yellow
        case "brown": return Color.brown
        default: return Color.blue
        }
    }

    init(color: Color) {
        rawValue = Self.hex(from: color) ?? Self.blue.rawValue
    }

    func isApproximately(_ other: PaletteColor) -> Bool {
        guard let left = resolvedRGB, let right = other.resolvedRGB else {
            return rawValue.caseInsensitiveCompare(other.rawValue) == .orderedSame
        }
        return abs(left.r - right.r) < 0.02 && abs(left.g - right.g) < 0.02
            && abs(left.b - right.b) < 0.02
    }

    private var resolvedRGB: (r: Double, g: Double, b: Double)? {
        Self.rgbComponents(in: rawValue) ?? Self.rgbComponents(of: color)
    }

    private static func hex(from color: Color) -> String? {
        guard let components = rgbComponents(of: color) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((components.r * 255).rounded()),
            Int((components.g * 255).rounded()),
            Int((components.b * 255).rounded())
        )
    }

    private static func rgbComponents(of color: Color) -> (r: Double, g: Double, b: Double)? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (
            Double(converted.redComponent),
            Double(converted.greenComponent),
            Double(converted.blueComponent)
        )
    }

    private static func rgbComponents(in stored: String) -> (r: Double, g: Double, b: Double)? {
        var hex = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = Int(hex, radix: 16) else {
            return nil
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

struct PaletteColorPicker: View {
    let label: String
    @Binding var color: PaletteColor
    @State private var isPresented = false

    var body: some View {
        LabeledContent(label) {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Circle()
                        .fill(color.color)
                        .frame(width: 12, height: 12)
                    Text(color.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .buttonStyle(.pill(.secondary, compact: true))
            .help("Choose a color")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(28), spacing: DS.Space.xs), count: 6),
                    spacing: DS.Space.xs
                ) {
                    ForEach(PaletteColor.presets) { preset in
                        Button {
                            color = preset
                            isPresented = false
                        } label: {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 18, height: 18)
                                .padding(DS.Space.xxs)
                                .overlay {
                                    if color.rawValue == preset.rawValue {
                                        Circle().strokeBorder(DS.Palette.textPrimary, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.title)
                    }
                }
                .padding(DS.Space.s)
            }
        }
    }
}
