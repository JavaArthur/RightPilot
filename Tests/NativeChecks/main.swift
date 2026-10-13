import AppKit

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
check("native menu renders six templates") { menu.items.first?.submenu?.items.count == 6 }
check("native menu preserves request snapshot") { let item = menu.items.first?.submenu?.items.first; let restored = NSMenuItem(); restored.tag = item?.tag ?? 0; let request = registry.request(for: restored.tag); return request?.paths == [directory.path] && request?.template == .text }
check("native menu callbacks point at target") { menu.items.last?.target === target && menu.items.last?.action == #selector(Target.run(_:)) }
check("native disabled context stays disabled") { let m = MenuRenderer.make(MenuPolicy.entries(context: MenuContext(target: nil, selected: [], background: true) { _ in false }, configuration: Configuration()), target: target, selector: #selector(Target.run(_:)), registry: registry); return m.items.first?.isEnabled == false && m.items.last?.isEnabled == true }
check("Terminal resolves installed app and exact directory") { let r = try NativeActions.terminalRequest(path: directory.path, terminal: .terminal); return r.directory.path == directory.path && Bundle(url: r.application)?.bundleIdentifier == "com.apple.Terminal" }
check("new JSON artifact readable by native Foundation") { let url = try FileCreator.create(in: directory, name: "native.json", template: .json); return (try JSONSerialization.jsonObject(with: Data(contentsOf: url))) is [String: Any] }
print("Native checks: \(passed) passed, \(failed) failed (no Finder-hosted UI assertions)")
exit(failed == 0 ? 0 : 1)
