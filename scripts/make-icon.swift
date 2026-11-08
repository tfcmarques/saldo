import AppKit
import ImageIO
import UniformTypeIdentifiers

// Builds the Saldo icon set from the artwork drawn by draw-icon.swift.
// usage: make-icon.swift <source.png> <output.iconset> [in-app.png]
// Desktop icons fill the canvas with the tile colour so Finder does not plate it on white.
// The optional in-app image keeps a transparent margin for the sidebar mark.
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(
        Data("usage: make-icon.swift <source.png> <output.iconset> [in-app.png]\n".utf8))
    exit(1)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
let inAppURL = arguments.count > 3 ? URL(fileURLWithPath: arguments[3]) : nil
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let original = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fatalError("Unable to read \(sourceURL.path)") }

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo)
    else { fatalError("Unable to create bitmap context") }
    context.interpolationQuality = .high
    return context
}

// Bounds of the pixels that are clearly opaque, ignoring any faint shadow in the source.
func solidBounds(of image: CGImage) -> CGRect {
    let context = makeContext(image.width, image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
        fatalError("No pixel data")
    }
    var minX = image.width
    var minY = image.height
    var maxX = 0
    var maxY = 0
    for y in 0..<image.height {
        for x in 0..<image.width where data[y * context.bytesPerRow + x * 4 + 3] > 128 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = solidBounds(of: original)
guard let tile = original.cropping(to: bounds) else { fatalError("Unable to crop artwork") }

func backdropColor(of image: CGImage) -> CGColor {
    let context = makeContext(image.width, image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
        return CGColor(red: 0.05, green: 0.28, blue: 0.22, alpha: 1)
    }
    var red = 0
    var green = 0
    var blue = 0
    var count = 0
    let step = max(1, image.width / 48)
    for y in stride(from: 0, to: image.height, by: step) {
        for x in stride(from: 0, to: image.width, by: step) {
            let index = y * context.bytesPerRow + x * 4
            guard data[index + 3] > 200 else { continue }
            let r = Int(data[index])
            let g = Int(data[index + 1])
            let b = Int(data[index + 2])
            // The tile is the dark colour around the white mark.
            guard max(r, g, b) < 90 else { continue }
            red += r
            green += g
            blue += b
            count += 1
        }
    }
    guard count > 0 else { return CGColor(red: 0.05, green: 0.28, blue: 0.22, alpha: 1) }
    return CGColor(
        red: CGFloat(red) / CGFloat(count) / 255,
        green: CGFloat(green) / CGFloat(count) / 255,
        blue: CGFloat(blue) / CGFloat(count) / 255,
        alpha: 1)
}

let green = backdropColor(of: tile)

func render(pixels: Int, fillsCanvas: Bool) -> CGImage {
    let size = CGFloat(pixels)
    let context = makeContext(pixels, pixels)
    let scale: CGFloat
    if fillsCanvas {
        context.setFillColor(green)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        // Cover the square, including the artwork's rounded transparent corners.
        scale = size / min(bounds.width, bounds.height) * 1.06
    } else {
        scale = size * 0.805 / max(bounds.width, bounds.height)
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.014,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    }
    let width = bounds.width * scale
    let height = bounds.height * scale
    let target = CGRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height)
    context.draw(tile, in: target)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Unable to write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Unable to encode PNG") }
}

for base in [16, 32, 128, 256, 512] {
    writePNG(
        render(pixels: base, fillsCanvas: true),
        to: iconsetURL.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(
        render(pixels: base * 2, fillsCanvas: true),
        to: iconsetURL.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if let inAppURL { writePNG(render(pixels: 512, fillsCanvas: false), to: inAppURL) }
