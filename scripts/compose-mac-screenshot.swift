import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3,
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
    let window = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("usage: compose-mac-screenshot input.png output.png\n".utf8))
    exit(64)
}

let width = 2880
let height = 1800
let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
guard
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { exit(1) }

let colors = [
    CGColor(colorSpace: colorSpace, components: [0.20, 0.72, 0.96, 1])!,
    CGColor(colorSpace: colorSpace, components: [0.24, 0.26, 0.90, 1])!,
]
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1])!
context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: CGFloat(width), y: 0), options: [])

let scale = min(CGFloat(width - 240) / CGFloat(window.width), CGFloat(height - 200) / CGFloat(window.height))
let size = CGSize(width: CGFloat(window.width) * scale, height: CGFloat(window.height) * scale)
let frame = CGRect(
    x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2, width: size.width,
    height: size.height)
let rounded = CGPath(roundedRect: frame, cornerWidth: 26, cornerHeight: 26, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: CGColor(gray: 0, alpha: 0.4))
context.addPath(rounded)
context.setFillColor(CGColor(gray: 0.1, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(rounded)
context.clip()
context.draw(window, in: frame)
context.restoreGState()

guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
