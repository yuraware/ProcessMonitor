// Renders the app icon (a CPU glyph on a blue gradient) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
// swiftlint:disable force_unwrapping multiline_arguments
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let side = CGFloat(pixels)
    let inset = side * 0.08
    let rect = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.24, green: 0.62, blue: 1.00, alpha: 1),
        ending: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.60, alpha: 1)
    )!
    gradient.draw(in: shape, angle: -70)

    let config = NSImage.SymbolConfiguration(pointSize: side * 0.50, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let target = NSRect(
            x: (side - symbolSize.width) / 2, y: (side - symbolSize.height) / 2,
            width: symbolSize.width, height: symbolSize.height
        )
        // Draw the template symbol, then recolor it white using source-atop.
        let tinted = NSImage(size: symbolSize, flipped: false) { bounds in
            symbol.draw(in: bounds)
            NSColor.white.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: target)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    try render(pixels: size).write(to: outputURL.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: outputURL.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

print("Wrote iconset to \(outputURL.path)")

// swiftlint:enable force_unwrapping multiline_arguments
