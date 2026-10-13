import AppKit

// Finder reconstructs NSMenuItems across its process boundary; arbitrary
// representedObject instances do not survive. Tags refer to immutable snapshots.
final class MenuRequestRegistry {
    private var next = 1
    private var requests: [Int: ActionRequest] = [:]
    func insert(_ request: ActionRequest) -> Int {
        let tag = next; next += 1; requests[tag] = request
        if tag > 4096 { requests.removeValue(forKey: tag - 4096) }
        return tag
    }
    func request(for tag: Int) -> ActionRequest? { requests[tag] }
}
enum MenuRenderer {
    static func make(_ entries: [MenuEntry], target: AnyObject, selector: Selector, registry: MenuRequestRegistry) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for entry in entries {
            if entry.isSeparator { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: entry.title, action: entry.action == nil ? nil : selector, keyEquivalent: "")
            item.isEnabled = entry.enabled
            item.target = target
            item.image = PilotArtwork.menu(entry.icon)
            if let request = entry.action { item.tag = registry.insert(request) }
            if !entry.children.isEmpty { item.submenu = make(entry.children, target: target, selector: selector, registry: registry) }
            menu.addItem(item)
        }
        return menu
    }
}
