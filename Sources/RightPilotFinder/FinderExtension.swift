import AppKit
import FinderSync
import OSLog

@objc(RightPilotFinder)
final class RightPilotFinder: FIFinderSync {
    private var configuration = Configuration()
    private let registry = MenuRequestRegistry()
    private let log = Logger(subsystem: "cn.aichanning.RightPilot.Finder", category: "extension")
    override init() {
        super.init()
        if let text = UserDefaults.standard.string(forKey: "menuSnapshot"), let c = try? PilotIPC.decode(text) { configuration = c }
        updateRoots()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(receiveConfiguration(_:)), name: Notification.Name(PilotIPC.config), object: nil, suspensionBehavior: .deliverImmediately)
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(PilotIPC.requestConfig), object: nil, userInfo: nil, deliverImmediately: true)
        log.notice("Finder extension initialized")
    }
    @objc private func volumesChanged() { updateRoots() }
    private func updateRoots() {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/")] + volumes)
    }
    @objc private func receiveConfiguration(_ note: Notification) {
        guard let text = note.object as? String, let config = try? PilotIPC.decode(text) else { return }
        configuration = config
        UserDefaults.standard.set(text, forKey: "menuSnapshot")
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(PilotIPC.acknowledge), object: "1", userInfo: nil, deliverImmediately: true)
        log.notice("Menu configuration synchronized")
    }
    override var toolbarItemName: String { "RightPilot" }
    override var toolbarItemToolTip: String { "新建文件、复制路径和常用目录" }
    override var toolbarItemImage: NSImage { NSImage(systemSymbolName: "cursorarrow.and.square.on.square.dashed", accessibilityDescription: "RightPilot") ?? NSImage() }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let context = MenuContext(target: controller.targetedURL(), selected: controller.selectedItemURLs() ?? [], background: menuKind == .contextualMenuForContainer) { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        let content = MenuRenderer.make(MenuPolicy.entries(context: context, configuration: configuration), target: self, selector: #selector(performAction(_:)), registry: registry)
        let menu = NSMenu(); let item = NSMenuItem(title: "RightPilot", action: nil, keyEquivalent: ""); item.submenu = content; menu.addItem(item)
        return menu
    }
    @objc private func performAction(_ sender: NSMenuItem) {
        guard let request = registry.request(for: sender.tag) else { log.error("Missing menu action tag: \(sender.tag)"); return }
        log.notice("Dispatching action \(request.action.rawValue, privacy: .public)")
        do {
            let url = try request.url()
            // Pin delivery to our containing application, not whichever app claimed the URL scheme.
            let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let options = NSWorkspace.OpenConfiguration(); options.activates = false
            NSWorkspace.shared.open([url], withApplicationAt: host, configuration: options) { _, error in
                if let error { self.log.error("Action delivery failed: \(error.localizedDescription, privacy: .public)") }
            }
        } catch {
            log.error("Invalid action: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }
}
