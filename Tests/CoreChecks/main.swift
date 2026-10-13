import Foundation
import Darwin
import RightPilotCore

var passed = 0
var failed = 0
func check(_ name: String, _ body: () throws -> Bool) {
    do { if try body() { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") } }
    catch { failed += 1; print("FAIL \(name): \(error)") }
}
func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
let root = FileManager.default.temporaryDirectory.appendingPathComponent("RightPilot-checks-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

for template in Template.allCases {
    check("create \(template.rawValue) with exact template bytes") {
        let url = try FileCreator.create(in: root, name: "sample." + template.suffix, template: template)
        return try Data(contentsOf: url) == template.contents
    }
}
check("JSON template parses") { let data = try Data(contentsOf: root.appendingPathComponent("sample.json")); return (try JSONSerialization.jsonObject(with: data)) is [String: Any] }
check("create folder") { let url = try FileCreator.create(in: root, name: "folder", template: nil); return try Paths.directory(url.path).path == url.path }
check("file collision preserves original") {
    let url = root.appendingPathComponent("sample.txt"); try Data("original".utf8).write(to: url)
    let rejected = rejects { _ = try FileCreator.create(in: root, name: "sample.txt", template: .json) }
    let contents = try String(contentsOf: url); return rejected && contents == "original"
}
check("folder collision preserves original") { rejects { _ = try FileCreator.create(in: root, name: "folder", template: nil) } }
check("dangling symlink is not followed") {
    let link = root.appendingPathComponent("link"); let target = root.appendingPathComponent("must-not-exist")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    return rejects { _ = try FileCreator.create(in: root, name: "link", template: .text) } && !FileManager.default.fileExists(atPath: target.path)
}
for name in ["", "  ", ".", "..", "../escape", "a/b", "a:b", "line\nname", String(repeating: "a", count: 256)] {
    check("reject invalid filename \(String(reflecting: name.prefix(20)))") { rejects { try FileCreator.validateName(name) } }
}
check("unicode and shell punctuation preserved literally") {
    let name = "中文 ' $(touch bad);.txt"
    let url = try FileCreator.create(in: root, name: name, template: .text)
    return FileManager.default.fileExists(atPath: url.path) && !FileManager.default.fileExists(atPath: root.appendingPathComponent("bad").path)
}
check("collision suggestion numbers filenames") { FileCreator.suggestedName(in: root, stem: "sample", suffix: "txt") == "sample 2.txt" }
check("reject nonexistent directory") { rejects { _ = try Paths.directory(root.appendingPathComponent("absent").path) } }
check("reject file used as directory") { rejects { _ = try Paths.directory(root.appendingPathComponent("sample.txt").path) } }
for path in ["relative/path", "/a/../b", "/nul\0value", "file:///tmp/x"] {
    check("reject invalid path \(String(reflecting: path))") { rejects { try Paths.validate(path) } }
}
check("shell escaping protects apostrophes and dollar expressions") { Paths.shellQuote("/tmp/a'b $(id)") == "'/tmp/a'\\''b $(id)'" }
check("multiselect raw paths preserve order") { try ClipboardText.render(["/a", "/b"], as: .path) == "/a\n/b" }
check("multiselect shell paths are separate arguments") { try ClipboardText.render(["/a b", "/c"], as: .shell) == "'/a b' '/c'" }
check("file URL percent encodes special characters") { try ClipboardText.render(["/tmp/a #中.txt"], as: .fileURL) == URL(fileURLWithPath: "/tmp/a #中.txt").absoluteString }
check("copy names") { try ClipboardText.render(["/a/中.txt", "/b/x"], as: .name) == "中.txt\nx" }
check("empty copy rejected") { rejects { _ = try ClipboardText.render([], as: .path) } }
check("URL roundtrip preserves ID and unusual filename") {
    let request = ActionRequest(action: .copyPath, paths: ["/tmp/空 格?#'\n.txt"])
    return try ActionRequest.decode(request.url()) == request
}
check("request IDs do not share a mailbox slot") { ActionRequest(action: .settings).id != ActionRequest(action: .settings).id }
for url in ["https://action?payload=abc", "rightpilot://wrong", "rightpilot://action?payload=bad", "rightpilot://action?payload=e30=&payload=e30=", "rightpilot://user@action?payload=e30="] {
    check("reject malformed action URL \(url)") { rejects { _ = try ActionRequest.decode(URL(string: url)!) } }
}
check("missing template rejected") { rejects { try ActionRequest(action: .createFile, paths: [root.path]).validate() } }
check("empty terminal context rejected") { rejects { try ActionRequest(action: .terminal).validate() } }
check("extraneous template rejected") { rejects { try ActionRequest(action: .settings, template: .text).validate() } }
check("oversized selection rejected") { rejects { try ActionRequest(action: .copyPath, paths: Array(repeating: "/tmp/x", count: 101)).validate() } }
check("oversized serialized paths rejected") { rejects { _ = try ActionRequest(action: .copyPath, paths: Array(repeating: "/" + String(repeating: "a", count: 400), count: 100)).url() } }
check("future action version rejected") { var r = ActionRequest(action: .settings); r.version = 2; return rejects { try r.validate() } }
let store = root.appendingPathComponent("config.json")
check("configuration roundtrip and IPC") {
    var config = Configuration.initial(home: root); config.terminal = .iterm; config.enabled.remove(.fileURL)
    try ConfigurationStore.save(config, to: store)
    return try ConfigurationStore.read(store, fallback: Configuration()) == config && PilotIPC.decode(PilotIPC.encode(config)) == config
}
check("corrupt config is preserved") {
    let data = Data("{broken".utf8); try data.write(to: store)
    let rejected = rejects { _ = try ConfigurationStore.read(store, fallback: Configuration()) }
    let current = try Data(contentsOf: store); return rejected && current == data
}
check("future config is rejected without changing file") {
    var config = Configuration(); config.version = 3
    let data = try JSONEncoder().encode(config); try data.write(to: store)
    let rejected = rejects { _ = try ConfigurationStore.read(store, fallback: Configuration()) }
    let current = try Data(contentsOf: store); return rejected && current == data
}
check("missing config uses fallback") { let fallback = Configuration.initial(home: root); return try ConfigurationStore.read(root.appendingPathComponent("missing.json"), fallback: fallback) == fallback }
check("duplicate favorite IDs rejected") { var c = Configuration(); let f = Favorite(name: "x", path: root.path); c.favorites = [f, f]; return rejects { try c.validate() } }
check("favorite count limit enforced") { var c = Configuration(); c.favorites = (1...31).map { Favorite(name: "\($0)", path: root.path) }; return rejects { try c.validate() } }
let folder = root.appendingPathComponent("folder")
let file = root.appendingPathComponent("sample.txt")
let isDir: (URL) -> Bool = { $0 == root || $0 == folder }
check("background ignores stale selection") { let c = MenuContext(target: root, selected: [file], background: true, isDirectory: isDir); return c.paths == [root.path] && c.directory == root.path }
check("single folder targets that folder") { let c = MenuContext(target: root, selected: [folder], background: false, isDirectory: isDir); return c.directory == folder.path }
check("single file targets containing folder") { let c = MenuContext(target: file, selected: [file], background: false, isDirectory: isDir); return c.directory == root.path }
check("mixed parent context disables directory actions") { let c = MenuContext(target: nil, selected: [file, URL(fileURLWithPath: "/other/x")], background: false, isDirectory: isDir); return c.directory == nil }
check("disabled features omitted from menu") { var c = Configuration(); c.enabled = []; let ctx = MenuContext(target: root, selected: [], background: true, isDirectory: isDir); let entries = MenuPolicy.entries(context: ctx, configuration: c); return entries.count == 1 && entries[0].action?.action == .settings }
check("no context disables file actions but leaves settings") {
    let entries = MenuPolicy.entries(context: MenuContext(target: nil, selected: [], background: true, isDirectory: isDir), configuration: Configuration())
    return entries.first(where: { $0.action?.action == .terminal })?.enabled == false && entries.last?.enabled == true
}
check("templates respect selected set") { var c = Configuration(); c.templates = [.json]; let items = MenuPolicy.entries(context: MenuContext(target: root, selected: [], background: true, isDirectory: isDir), configuration: c); return items.first?.children.count == 1 && items.first?.children.first?.action?.template == .json }
check("favorites requests use ID not an injected path") { var c = Configuration(); let f = Favorite(name: "常用", path: root.path); c.favorites = [f]; let items = MenuPolicy.entries(context: MenuContext(target: root, selected: [], background: true, isDirectory: isDir), configuration: c); let r = items.first(where: { $0.title == "常用目录" })?.children.first?.action; return r?.favoriteID == f.id && r?.paths.isEmpty == true }
check("exclusive creation permits one concurrent winner") {
    let lock = NSLock(); var wins = 0
    DispatchQueue.concurrentPerform(iterations: 20) { _ in
        if (try? FileCreator.create(in: root, name: "race.json", template: .json)) != nil { lock.lock(); wins += 1; lock.unlock() }
    }
    let data = try Data(contentsOf: root.appendingPathComponent("race.json")); return wins == 1 && data == Template.json.contents
}
check("v1 settings migration preserves disabled features and favorites") {
    var c = Configuration(); c.enabled = [.terminal, .favorites]; c.templates = [.json]
    c.favorites = [Favorite(name: "mine", path: root.path)]
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]; object["version"] = 1
    let migrated = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: object))
    return migrated.version == 2 && !migrated.enabled.contains(.copyPath) && migrated.enabled.contains(.visibility) && migrated.templates.contains(.rtf) && !migrated.templates.contains(.shell) && migrated.favorites == c.favorites
}
check("RTF has a real format header") { String(decoding: Template.rtf.contents, as: UTF8.self).hasPrefix("{\\rtf1") }
check("new operation protocol roundtrip") {
    for action in [Action.hideItems, .showItems, .hideContents, .showContents, .copyTo, .convertPNG, .convertJPEG, .sha256] {
        let r = ActionRequest(action: action, paths: [root.path]); if try ActionRequest.decode(r.url()) != r { return false }
    }; return true
}
check("SHA256 matches published abc test vector") {
    let url = try FileCreator.write(Data("abc".utf8), in: root, name: "abc")
    return try FileOperations.sha256(url.path) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}
check("SHA256 rejects folders and symlinks") {
    let link = root.appendingPathComponent("hash-link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    return rejects { _ = try FileOperations.sha256(root.path) } && rejects { _ = try FileOperations.sha256(link.path) }
}
check("hidden flag roundtrip preserves content and unrelated flags") {
    let url = try FileCreator.write(Data("keep".utf8), in: root, name: "visibility.txt")
    var before = stat(); lstat(url.path, &before)
    let hide = FileOperations.setHidden([url.path], hidden: true)
    var hidden = stat(); lstat(url.path, &hidden)
    let show = FileOperations.setHidden([url.path], hidden: false)
    var after = stat(); lstat(url.path, &after)
    let content = try String(contentsOf: url)
    return hide.succeeded.count == 1 && show.succeeded.count == 1 && hidden.st_flags & UInt32(UF_HIDDEN) != 0 && after.st_flags == before.st_flags && content == "keep"
}
check("visibility skips symlinks and dotfiles") {
    let dot = try FileCreator.write(Data(), in: root, name: ".keep")
    let link = root.appendingPathComponent("hash-link")
    let result = FileOperations.setHidden([dot.path, link.path], hidden: true)
    return result.succeeded.isEmpty && result.failures.count == 2
}
check("directory visibility lists direct children only") {
    let nested = try FileCreator.create(in: folder, name: "nested", template: .text)
    let children = try FileOperations.immediateChildren(of: root.path)
    let canonical = Set(children.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
    return canonical.contains(folder.resolvingSymlinksInPath().path) && !canonical.contains(nested.resolvingSymlinksInPath().path)
}
check("copy preserves source and refuses collision") {
    let source = root.appendingPathComponent("abc")
    let first = FileOperations.copy([source.path], to: folder)
    let second = FileOperations.copy([source.path], to: folder)
    let sourceData = try Data(contentsOf: source); let targetData = try Data(contentsOf: folder.appendingPathComponent("abc"))
    return first.succeeded.count == 1 && second.failures.count == 1 && sourceData == targetData
}
check("copy refuses directory into itself") { FileOperations.copy([root.path], to: folder).failures.count == 1 }
check("mixed copy success reports partial failure") { let r = FileOperations.copy([root.appendingPathComponent("sample.json").path, root.appendingPathComponent("nonexistent").path], to: folder); return r.succeeded.count == 1 && r.failures.count == 1 }
check("image menu rejects mixed nonimage selection") {
    let ctx = MenuContext(target: root, selected: [root.appendingPathComponent("a.png"), file], background: false, isDirectory: isDir)
    return MenuPolicy.entries(context: ctx, configuration: Configuration()).first(where: { $0.title == "图片转换" })?.enabled == false
}
check("background visibility targets directory not stale selection") {
    let ctx = MenuContext(target: root, selected: [file], background: true, isDirectory: isDir)
    let tools = MenuPolicy.entries(context: ctx, configuration: Configuration()).first(where: { $0.title == "文件操作" })!.children
    return tools.first(where: { $0.action?.action == .hideItems }) == nil && tools.first(where: { $0.action?.action == .showContents })?.action?.paths == [root.path]
}
print("Core checks: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
