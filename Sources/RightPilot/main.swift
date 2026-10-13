import AppKit
import SwiftUI
import FinderSync

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var requests: [ActionRequest] = []
    var seen: [UUID] = []
    var draining = false
    var ready = false
    let registry = MenuRequestRegistry()
    init(configURL: URL) { model = AppModel(configURL: configURL); super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.and.square.on.square.dashed", accessibilityDescription: "RightPilot")
        let menu = NSMenu()
        menu.addItem(withTitle: "RightPilot 设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "选择目录进行操作…", action: #selector(chooseDirectory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 RightPilot", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(syncRequested(_:)), name: Notification.Name(PilotIPC.requestConfig), object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(syncAcknowledged(_:)), name: Notification.Name(PilotIPC.acknowledge), object: nil, suspensionBehavior: .deliverImmediately)
        model.broadcast()
        ready = true
        if CommandLine.arguments.contains("--settings") || !model.extensionEnabled { showSettings() }
        drain()
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshStatus(); model.broadcast() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    @objc func syncRequested(_ note: Notification) { model.broadcast() }
    @objc func syncAcknowledged(_ note: Notification) { model.lastSync = Date() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "RightPilot"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func chooseDirectory() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "打开操作菜单"
        if panel.runModal() == .OK, let folder = panel.url {
            let context = MenuContext(target: folder, selected: [], background: true) { _ in true }
            let menu = MenuRenderer.make(MenuPolicy.entries(context: context, configuration: model.configuration), target: self, selector: #selector(menuAction(_:)), registry: registry)
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
    @objc func menuAction(_ sender: NSMenuItem) {
        guard let request = registry.request(for: sender.tag) else { return }; enqueue(request)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do { enqueue(try ActionRequest.decode(url)) }
            catch { showError(error) }
        }
    }
    func enqueue(_ request: ActionRequest) {
        guard !seen.contains(request.id) else { return }
        guard requests.count < 100 else { showError(PilotError.invalid("待处理操作过多，请稍后再试。")); return }
        seen.append(request.id); if seen.count > 512 { seen.removeFirst() }
        requests.append(request); if ready { drain() }
    }
    func drain() {
        guard !draining else { return }; draining = true
        DispatchQueue.main.async {
            while !self.requests.isEmpty {
                let request = self.requests.removeFirst()
                do { try self.perform(request) } catch { self.showError(error) }
            }
            self.draining = false
        }
    }
    func perform(_ request: ActionRequest) throws {
        try request.validate()
        switch request.action {
        case .settings: showSettings()
        case .copyPath: try NativeActions.copy(request.paths, as: .path)
        case .copyShellPath: try NativeActions.copy(request.paths, as: .shell)
        case .copyFileURL: try NativeActions.copy(request.paths, as: .fileURL)
        case .copyName: try NativeActions.copy(request.paths, as: .name)
        case .terminal:
            try NativeActions.openTerminal(path: request.paths[0], terminal: model.configuration.terminal) { error in
                if let error { DispatchQueue.main.async { self.showError(error) } }
            }
        case .favorite:
            guard let favorite = model.configuration.favorites.first(where: { $0.id == request.favoriteID }) else { throw PilotError.invalid("这个常用目录已移除，请重新打开右键菜单。") }
            let folder = try Paths.directory(favorite.path)
            guard NSWorkspace.shared.open(folder) else { throw PilotError.invalid("Finder 无法打开此目录。") }
        case .addFavorite:
            _ = try Paths.directory(request.paths[0]); model.addFavorite(request.paths[0]); showSettings()
        case .createFile, .createFolder:
            let folder = try Paths.directory(request.paths[0])
            try create(folder: folder, template: request.template)
        }
    }
    func create(folder: URL, template: Template?) throws {
        NSApp.activate(ignoringOtherApps: true)
        let name = FileCreator.suggestedName(in: folder, stem: template == nil ? "新建文件夹" : "未命名", suffix: template?.suffix)
        let input = NSTextField(string: name); input.frame = NSRect(x: 0, y: 0, width: 380, height: 26)
        let alert = NSAlert(); alert.messageText = template == nil ? "新建文件夹" : "新建 \(template!.title)"
        alert.informativeText = "创建位置：\(folder.path)"; alert.accessoryView = input
        alert.addButton(withTitle: "创建"); alert.addButton(withTitle: "取消"); alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newURL = try FileCreator.create(in: folder, name: input.stringValue, template: template)
        if model.configuration.revealCreated { NSWorkspace.shared.activateFileViewerSelecting([newURL]) }
    }
    func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "操作未完成"; alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好"); alert.runModal()
    }
}

let configArgument = CommandLine.arguments.firstIndex(of: "--config").flatMap { index -> String? in
    index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : nil
}
let configURL = configArgument.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RightPilot/config.json")
let app = NSApplication.shared
let delegate = AppDelegate(configURL: configURL)
app.setActivationPolicy(.accessory); app.delegate = delegate; app.run()
