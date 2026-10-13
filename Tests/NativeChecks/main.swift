import AppKit
import ImageIO
import UniformTypeIdentifiers

var passed = 0
var failed = 0
func check(_ name: String, _ body: () throws -> Bool) {
    do { if try body() { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") } } catch { failed += 1; print("FAIL \(name): \(error)") }
}
final class Target: NSObject { @objc func run(_ sender: NSMenuItem) {} }
let target = Target()
let registry = MenuRequestRegistry()
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RightPilot-native-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let board = NSPasteboard(name: NSPasteboard.Name("RightPilot-checks-" + UUID().uuidString))
defer { board.releaseGlobally() }
check("native clipboard writes exact unicode text") { try NativeActions.copy([directory.path + "/中文 ' $.txt"], as: .path, to: board); return board.string(forType: .string) == directory.path + "/中文 ' $.txt" }
check("native shell clipboard writes quoted arguments") { try NativeActions.copy(["/a'b", "/c d"], as: .shell, to: board); return board.string(forType: .string) == "'/a'\\''b' '/c d'" }
check("native file URL clipboard") { try NativeActions.copy([directory.path], as: .fileURL, to: board); guard let text = board.string(forType: .string), let url = URL(string: text) else { return false }; return url.isFileURL && url.path == directory.path }
let context = MenuContext(target: directory, selected: [], background: true) { _ in true }
let menu = MenuRenderer.make(MenuPolicy.entries(context: context, configuration: Configuration()), target: target, selector: #selector(Target.run(_:)), registry: registry)
check("native menu renders ten templates") { menu.items.first?.submenu?.items.count == 10 }
check("native menu preserves request snapshot") { let item = menu.items.first?.submenu?.items.first; let restored = NSMenuItem(); restored.tag = item?.tag ?? 0; let request = registry.request(for: restored.tag); return request?.paths == [directory.path] && request?.template == .text }
check("native menu callbacks point at target") { menu.items.last?.target === target && menu.items.last?.action == #selector(Target.run(_:)) }
check("native disabled context stays disabled") { let m = MenuRenderer.make(MenuPolicy.entries(context: MenuContext(target: nil, selected: [], background: true) { _ in false }, configuration: Configuration()), target: target, selector: #selector(Target.run(_:)), registry: registry); return m.items.first?.isEnabled == false && m.items.last?.isEnabled == true }
check("Terminal resolves installed app and exact directory") { let r = try NativeActions.terminalRequest(path: directory.path, terminal: .terminal); return r.directory.path == directory.path && Bundle(url: r.application)?.bundleIdentifier == "com.apple.Terminal" }
check("new JSON artifact readable by native Foundation") { let url = try FileCreator.create(in: directory, name: "native.json", template: .json); return (try JSONSerialization.jsonObject(with: Data(contentsOf: url))) is [String: Any] }
check("all nonseparator menu items have icons") {
    func inspect(_ menu: NSMenu) -> Bool { menu.items.allSatisfy { $0.isSeparatorItem || ($0.image != nil && ($0.submenu.map(inspect) ?? true)) } }
    return inspect(menu)
}
check("all menu symbols resolve on this OS") { MenuIcon.allCases.allSatisfy { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil } }
check("brand renders PNG and compact menu size") { PilotArtwork.brand(size: 128).tiffRepresentation != nil && PilotArtwork.brand(size: 16).size.width == 16 }
check("RTF template decodes as rich text") { (try? NSAttributedString(data: Template.rtf.contents, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)) != nil }
let png = directory.appendingPathComponent("transparent.png")
check("PNG conversion preserves alpha and original bytes") {
    let context = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let image = context.makeImage()!; let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); guard CGImageDestinationFinalize(dest) else { return false }
    try (data as Data).write(to: png)
    let output = try ImageConverter.convert(png.path, to: .png)
    let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
    let result = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let original = try Data(contentsOf: png)
    return output != png && original == data as Data && result.width == 8 && result.height == 6 && result.alphaInfo != .none
}
check("JPEG flattens transparency to white") {
    let output = try ImageConverter.convert(png.path, to: .jpeg)
    let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    var pixels = [UInt8](repeating: 0, count: 8 * 6 * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let ctx = CGContext(data: bytes.baseAddress, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 6))
    }
    return pixels[0] > 245 && pixels[1] > 245 && pixels[2] > 245 && image.width == 8
}
check("invalid image reports failure without output") {
    let invalid = try FileCreator.write(Data("not an image".utf8), in: directory, name: "bad.png")
    do { _ = try ImageConverter.convert(invalid.path, to: .jpeg); return false } catch { return !FileManager.default.fileExists(atPath: directory.appendingPathComponent("bad.jpg").path) }
}
check("menu snapshot survives archiving with icon and tag") {
    let item = menu.items.first!.submenu!.items.first!
    let data = try NSKeyedArchiver.archivedData(withRootObject: item, requiringSecureCoding: false)
    let restored = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! NSMenuItem
    return restored.image != nil && registry.request(for: restored.tag)?.template == .text
}
check("image conversion applies EXIF orientation") {
    let context = CGContext(data: nil, width: 4, height: 8, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let data = NSMutableData(); let dest = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return false }
    let input = try FileCreator.write(data as Data, in: directory, name: "rotated.tiff")
    let output = try ImageConverter.convert(input.path, to: .png)
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
    return image.width == 8 && image.height == 4
}
check("animated image rejected without flattening frames") {
    let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let data = NSMutableData(); let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil)!
    CGImageDestinationAddImage(dest, context.makeImage()!, nil); CGImageDestinationAddImage(dest, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { return false }
    let input = try FileCreator.write(data as Data, in: directory, name: "animated.gif")
    do { _ = try ImageConverter.convert(input.path, to: .png); return false } catch { return !FileManager.default.fileExists(atPath: directory.appendingPathComponent("animated.png").path) }
}
print("Native checks: \(passed) passed, \(failed) failed (no Finder-hosted UI assertions)")
exit(failed == 0 ? 0 : 1)
