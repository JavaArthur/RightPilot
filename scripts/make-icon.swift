import AppKit
@main struct MakeIcon {
static func main() throws {
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let set = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixel = size * scale
        let image = PilotArtwork.brand(size: CGFloat(pixel))
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try data.write(to: set.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", set.path, "-o", destination.appendingPathComponent("AppIcon.icns").path]; try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: set)

}
}
