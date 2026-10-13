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
    var working = false
    var progressWindow: NSPanel?
    let worker = DispatchQueue(label: "cn.aichanning.RightPilot.operations", qos: .userInitiated)
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
        guard !draining, !working else { return }; draining = true
        DispatchQueue.main.async {
            while !self.requests.isEmpty && !self.working {
                let request = self.requests.removeFirst()
                do { try self.perform(request) } catch { self.showError(error) }
            }
            self.draining = false
        }
    }
    func perform(_ request: ActionRequest) throws {
        try request.validate()
        switch request.action {
        case .hideItems, .showItems, .hideContents, .showContents:
            let contents = request.action == .hideContents || request.action == .showContents
            let hidden = request.action == .hideItems || request.action == .hideContents
            let paths = try contents ? FileOperations.immediateChildren(of: request.paths[0]) : request.paths
            guard !paths.isEmpty else { throw PilotError.invalid("没有可处理的项目。") }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(); alert.messageText = "\(hidden ? "隐藏" : "取消隐藏") \(paths.count) 个项目？"
            alert.informativeText = (contents ? "仅处理当前目录的直接子项，不递归。\n" : "仅修改所选项目的隐藏标记。\n") + paths.prefix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n") + "\n\n不删除文件，不重命名点号文件；符号链接会跳过。可用“取消隐藏当前目录中的项目”恢复。"
            alert.addButton(withTitle: hidden ? "隐藏" : "取消隐藏"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            beginWork("正在更新隐藏标记") { (FileOperations.setHidden(paths, hidden: hidden), nil) }
        case .copyTo:
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.prompt = "复制到这里"; panel.message = "复制 \(request.paths.count) 个项目；遇到同名文件将跳过，原文件保持不变。"
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            beginWork("正在复制") { (FileOperations.copy(request.paths, to: destination), nil) }
        case .convertPNG, .convertJPEG:
            let format: ImageConverter.Format = request.action == .convertPNG ? .png : .jpeg
            beginWork("正在转换图片") {
                var result = BatchOutcome()
                for path in request.paths {
                    do { result.succeeded.append(try ImageConverter.convert(path, to: format).path) }
                    catch { result.failures.append("\(URL(fileURLWithPath: path).lastPathComponent)：\(error.localizedDescription)") }
                }
                return (result, nil)
            }
        case .sha256:
            beginWork("正在计算 SHA-256") {
                var result = BatchOutcome(); var lines: [String] = []
                for path in request.paths {
                    do { let digest = try FileOperations.sha256(path); lines.append(request.paths.count == 1 ? digest : digest + "  " + path); result.succeeded.append(path) }
                    catch { result.failures.append("\(URL(fileURLWithPath: path).lastPathComponent)：\(error.localizedDescription)") }
                }
                return (result, lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }
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
    func beginWork(_ title: String, task: @escaping () throws -> (BatchOutcome, String?)) {
        working = true
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "完成后会显示处理结果，原文件不会被覆盖。")
        label.frame = NSRect(x: 18, y: 20, width: 320, height: 22); panel.contentView?.addSubview(label)
        let spinner = NSProgressIndicator(frame: NSRect(x: 164, y: 51, width: 22, height: 22)); spinner.style = .spinning; spinner.startAnimation(nil); panel.contentView?.addSubview(spinner)
        panel.center(); panel.orderFrontRegardless(); progressWindow = panel
        worker.async {
            let result = Result { try task() }
            DispatchQueue.main.async {
                self.progressWindow?.close(); self.progressWindow = nil
                switch result {
                case .success(let (outcome, clipboard)):
                    if let clipboard { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(clipboard, forType: .string) }
                    let alert = NSAlert(); alert.messageText = clipboard == nil ? "处理完成" : "SHA-256 已复制"
                    alert.informativeText = outcome.summary; alert.addButton(withTitle: "好")
                    NSApp.activate(ignoringOtherApps: true); alert.runModal()
                case .failure(let error): self.showError(error)
                }
                self.working = false; self.drain()
            }
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
