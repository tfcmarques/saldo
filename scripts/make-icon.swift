import AppKit
import ImageIO
import UniformTypeIdentifiers

// Builds the Saldo icon set from the artwork in design/saldo-icon-source.png.
// usage: make-icon.swift <source.png> <output.iconset> [in-app.png]
// The artwork is cropped to its solid tile and rescaled to the macOS icon grid (80% of the canvas).
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

func render(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let context = makeContext(pixels, pixels)
    let scale = size * 0.805 / max(bounds.width, bounds.height)
    let width = bounds.width * scale
    let height = bounds.height * scale
    let target = CGRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height)
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.014,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
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
        render(pixels: base), to: iconsetURL.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(
        render(pixels: base * 2),
        to: iconsetURL.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if let inAppURL { writePNG(render(pixels: 512), to: inAppURL) }
