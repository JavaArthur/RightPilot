import SwiftUI
import AppKit
import FinderSync
import ServiceManagement

final class AppModel: ObservableObject {
    @Published private(set) var configuration: Configuration
    @Published var problem: String?
    @Published var extensionEnabled = false
    @Published var lastSync: Date?
    @Published var loginEnabled = false
    @Published var readOnly = false
    let configURL: URL
    init(configURL: URL) {
        self.configURL = configURL
        let initial = Configuration.initial(home: FileManager.default.homeDirectoryForCurrentUser)
        do { configuration = try ConfigurationStore.read(configURL, fallback: initial) }
        catch { configuration = initial; problem = "无法读取配置：\(error.localizedDescription) 原文件已保留，保存已暂停。"; readOnly = true }
        refreshStatus()
    }
    func change(_ body: (inout Configuration) -> Void) {
        guard !readOnly else { return }
        var next = configuration; body(&next)
        do { try ConfigurationStore.save(next, to: configURL); configuration = next; broadcast() }
        catch { problem = error.localizedDescription }
    }
    func refreshStatus() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func broadcast() {
        guard let text = try? PilotIPC.encode(configuration) else { return }
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(PilotIPC.config), object: text, userInfo: nil, deliverImmediately: true)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { problem = "开机启动设置失败：\(error.localizedDescription)" }
        refreshStatus()
    }
    func addFavorite(_ path: String, name: String? = nil) {
        do {
            let folder = try Paths.directory(path)
            guard !configuration.favorites.contains(where: { $0.path == folder.path }) else { problem = "这个目录已经在常用目录中。"; return }
            let name = name ?? folder.lastPathComponent
            change { $0.favorites.append(Favorite(name: name.isEmpty ? folder.path : name, path: folder.path)) }
        } catch { problem = error.localizedDescription }
    }
    func chooseFavorite() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "加入常用"
        if panel.runModal() == .OK, let url = panel.url { addFavorite(url.path) }
    }
}
