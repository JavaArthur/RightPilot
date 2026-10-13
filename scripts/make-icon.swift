import AppKit
@main struct MakeIcon {
static func main() throws {
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let source = destination.appendingPathComponent("AppIcon.png")
guard NSImage(contentsOf: source) != nil else { fatalError("Missing or invalid AppIcon.png") }
let set = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixel = size * scale
        let image = PilotArtwork.brand(size: CGFloat(pixel), sourceURL: source)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixel, height: pixel))
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: set.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", set.path, "-o", destination.appendingPathComponent("AppIcon.icns").path]; try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: set)

}
}
