import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the bundled Montra artwork at every size the macOS asset catalog needs.
// Run from the project root: swift Scripts/make-icon.swift [output-folder]
let assets = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Montra/Resources/Assets.xcassets", isDirectory: true)
let input = assets.appendingPathComponent("MontraArtwork.imageset/artwork.png")
let output = CommandLine.arguments.dropFirst().first.map {
    URL(fileURLWithPath: $0, isDirectory: true)
} ?? assets.appendingPathComponent("AppIcon.appiconset", isDirectory: true)

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height else {
    throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: input])
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }

    // Keep the existing macOS icon inset and silhouette.
    let side = CGFloat(size)
    let inset = side * 0.085
    let rect = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let radius = rect.width * 0.2237
    context.interpolationQuality = .high
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(artwork, in: rect)

    let url = output.appendingPathComponent("icon_\(size).png")
    let data = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
    }
    try data.write(to: url, options: .atomic)
}
