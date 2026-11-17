import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift GenerateIcon.swift /path/to/AppIcon.icns")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ rgb: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255,
            alpha: 1)
}

func drawIcon(size: Int) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 179, cornerHeight: 179, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 32, color: CGColor(gray: 0, alpha: 0.28))
    context.setFillColor(color(0x171b1a))
    context.addPath(shape)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [color(0x2d3430), color(0x111413)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 245, y: 930), end: CGPoint(x: 785, y: 115), options: [])
    context.setStrokeColor(color(0x444b46))
    context.setLineWidth(9)
    context.addPath(shape)
    context.strokePath()
    context.restoreGState()

    let heights: [CGFloat] = [116, 220, 360, 250, 142]
    context.setFillColor(color(0xc4fc6b))
    for (index, height) in heights.enumerated() {
        let width: CGFloat = 59
        let bar = CGRect(x: 512 - width / 2 + CGFloat(index - 2) * 106,
                         y: 512 - height / 2, width: width, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        context.fillPath()
    }
    return context.makeImage()!
}

func iconChunk(kind: String, payload: Data) -> Data {
    var result = Data(kind.utf8)
    var length = UInt32(payload.count + 8).bigEndian
    withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
    result.append(payload)
    return result
}

// ICNS stores each 1x and 2x representation as a PNG in its own typed chunk.
let sizes = [("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64), ("ic07", 128),
             ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
var representations = Data()
for (kind, size) in sizes {
    let bytes = NSMutableData()
    let png = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(png, drawIcon(size: size), nil)
    precondition(CGImageDestinationFinalize(png), "Could not render \(kind)")
    representations.append(iconChunk(kind: kind, payload: bytes as Data))
}
try iconChunk(kind: "icns", payload: representations).write(to: destination, options: .atomic)
