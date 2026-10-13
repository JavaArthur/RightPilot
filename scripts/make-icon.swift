import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let set = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixel = size * scale
        let image = NSImage(size: NSSize(width: pixel, height: pixel))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: pixel, height: pixel).insetBy(dx: Double(pixel) * 0.06, dy: Double(pixel) * 0.06)
        NSColor(calibratedRed: 0.12, green: 0.26, blue: 0.52, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: Double(pixel) * 0.19, yRadius: Double(pixel) * 0.19).fill()
        let symbol = NSImage(systemSymbolName: "cursorarrow.and.square.on.square.dashed", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: Double(pixel) * 0.56, weight: .medium))!
        let symbolRect = NSRect(x: Double(pixel) * 0.22, y: Double(pixel) * 0.20, width: Double(pixel) * 0.56, height: Double(pixel) * 0.56)
        NSColor.white.set(); symbol.draw(in: symbolRect)
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try data.write(to: set.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", set.path, "-o", destination.appendingPathComponent("AppIcon.icns").path]; try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: set)
