import AppKit

enum NativeActions {
    static func copy(_ paths: [String], as format: CopyFormat, to board: NSPasteboard = .general) throws {
        let text = try ClipboardText.render(paths, as: format)
        board.clearContents()
        guard board.setString(text, forType: .string) else { throw PilotError.invalid("无法写入剪贴板。") }
    }
    static func terminalRequest(path: String, terminal: TerminalChoice) throws -> (directory: URL, application: URL) {
        let folder = try Paths.directory(path)
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else { throw PilotError.invalid("未安装 \(terminal.title)，请在设置中选择 Terminal。") }
        return (folder, application)
    }
    static func openTerminal(path: String, terminal: TerminalChoice, completion: @escaping (Error?) -> Void) throws {
        let request = try terminalRequest(path: path, terminal: terminal)
        let options = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([request.directory], withApplicationAt: request.application, configuration: options) { _, error in completion(error) }
    }
}
