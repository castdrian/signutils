import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let window = NSImage(contentsOfFile: arguments[1]),
    let source = window.representations.first
else {
    FileHandle.standardError.write(Data("usage: compose-mac-screenshot input.png output.png\n".utf8))
    exit(64)
}

let canvasSize = NSSize(width: 2880, height: 1800)
let image = NSImage(size: canvasSize)
image.lockFocus()
let gradient = NSGradient(
    starting: NSColor(displayP3Red: 0.20, green: 0.72, blue: 0.96, alpha: 1),
    ending: NSColor(displayP3Red: 0.24, green: 0.26, blue: 0.90, alpha: 1))
gradient?.draw(in: NSRect(origin: .zero, size: canvasSize), angle: -45)
let pixelSize = NSSize(width: source.pixelsWide, height: source.pixelsHigh)
let scale = min((canvasSize.width - 240) / pixelSize.width, (canvasSize.height - 200) / pixelSize.height)
let size = NSSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
let frame = NSRect(
    x: (canvasSize.width - size.width) / 2, y: (canvasSize.height - size.height) / 2, width: size.width,
    height: size.height)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 60
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
let clip = NSBezierPath(roundedRect: frame, xRadius: 26, yRadius: 26)
NSColor.white.setFill()
clip.fill()
NSShadow().set()
clip.addClip()
window.draw(in: frame)
image.unlockFocus()

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { exit(1) }
let output = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvasSize.width), pixelsHigh: Int(canvasSize.height), bitsPerSample: 8,
    samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
bitmap.draw(in: NSRect(origin: .zero, size: canvasSize))
NSGraphicsContext.restoreGraphicsState()
try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
