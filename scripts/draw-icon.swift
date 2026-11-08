import AppKit
import ImageIO
import UniformTypeIdentifiers

// Draws the Saldo icon artwork: a near-black tile with a geometric white "S" and an
// indigo dot. make-icon.swift turns it into the app icon set.
// usage: swift scripts/draw-icon.swift <output.png>
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: draw-icon.swift <output.png>\n".utf8))
    exit(1)
}

let size = 1024
let canvas = CGFloat(size)
let space = CGColorSpaceCreateDeviceRGB()
guard
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("Unable to create bitmap context") }

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// macOS icon grid: 824 pt tile centred on 1024, continuous corners.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
context.setFillColor(rgb(0x191C1F))
context.fillPath()

// The S: three bars joined by rounded turns, drawn as one round-capped stroke.
// Coordinates are fractions of the canvas, y up.
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * canvas, y: y * canvas) }
let left: CGFloat = 0.355
let right: CGFloat = 0.645
let top: CGFloat = 0.685
let middle: CGFloat = 0.5
let bottom: CGFloat = 0.315
let turn = 0.0925 * canvas
let path = CGMutablePath()
path.move(to: point(right, top))
path.addArc(tangent1End: point(left, top), tangent2End: point(left, middle), radius: turn)
path.addArc(tangent1End: point(left, middle), tangent2End: point(right, middle), radius: turn)
path.addArc(tangent1End: point(right, middle), tangent2End: point(right, bottom), radius: turn)
path.addArc(tangent1End: point(right, bottom), tangent2End: point(left, bottom), radius: turn)
path.addLine(to: point(left + 0.02, bottom))
context.addPath(path)
context.setStrokeColor(rgb(0xFFFFFF))
context.setLineWidth(0.1 * canvas)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

// Accent dot where the top bar would continue: the one touch of brand colour.
let dot: CGFloat = 0.1 * canvas
context.setFillColor(rgb(0x494FDF))
context.fillEllipse(
    in: CGRect(x: 0.75 * canvas - dot / 2, y: top * canvas - dot / 2, width: dot, height: dot))

guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString,
        1, nil)
else { fatalError("Unable to write the icon") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to encode PNG") }
