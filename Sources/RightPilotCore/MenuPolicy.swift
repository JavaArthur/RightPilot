import Foundation

public struct MenuContext {
    public var paths: [String]
    public var directory: String?
    public init(target: URL?, selected: [URL], background: Bool, isDirectory: (URL) -> Bool) {
        let selected = selected.filter(\.isFileURL)
        if background {
            paths = target.map { $0.isFileURL ? [$0.path] : [] } ?? []
            directory = target.flatMap { $0.isFileURL && isDirectory($0) ? $0.path : nil }
        } else {
            paths = selected.isEmpty ? (target.map { $0.isFileURL ? [$0.path] : [] } ?? []) : selected.map(\.path)
            if selected.count == 1, isDirectory(selected[0]) { directory = selected[0].path }
            else if let target, target.isFileURL, isDirectory(target) { directory = target.path }
            else {
                let parents = Set(paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path })
                directory = parents.count == 1 ? parents.first : nil
            }
        }
    }
}
public struct MenuEntry {
    public var title: String
    public var action: ActionRequest?
    public var children: [MenuEntry]
    public var enabled: Bool
    public init(_ title: String, action: ActionRequest? = nil, children: [MenuEntry] = [], enabled: Bool = true) { self.title = title; self.action = action; self.children = children; self.enabled = enabled }
}
public enum MenuPolicy {
    public static func entries(context: MenuContext, configuration c: Configuration) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        let directory = context.directory.map { [$0] } ?? []
        if c.enabled.contains(.newFile) {
            let children = Template.allCases.filter { c.templates.contains($0) }.map { MenuEntry($0.title + " (." + $0.suffix + ")", action: ActionRequest(action: .createFile, paths: directory, template: $0)) }
            if !children.isEmpty { entries.append(MenuEntry("新建文件", children: children, enabled: !directory.isEmpty)) }
        }
        if c.enabled.contains(.newFolder) { entries.append(MenuEntry("新建文件夹…", action: ActionRequest(action: .createFolder, paths: directory), enabled: !directory.isEmpty)) }
        for (feature, action) in [(Feature.copyPath, Action.copyPath), (.shellPath, .copyShellPath), (.fileURL, .copyFileURL), (.copyName, .copyName)] where c.enabled.contains(feature) {
            entries.append(MenuEntry(feature.title, action: ActionRequest(action: action, paths: context.paths), enabled: !context.paths.isEmpty && context.paths.count <= 100))
        }
        if c.enabled.contains(.terminal) { entries.append(MenuEntry("在 \(c.terminal.title) 打开", action: ActionRequest(action: .terminal, paths: directory), enabled: !directory.isEmpty)) }
        if c.enabled.contains(.favorites) {
            var children = c.favorites.map { MenuEntry($0.name, action: ActionRequest(action: .favorite, favoriteID: $0.id)) }
            children.append(MenuEntry("将此目录加入常用…", action: ActionRequest(action: .addFavorite, paths: directory), enabled: !directory.isEmpty))
            entries.append(MenuEntry("常用目录", children: children))
        }
        entries.append(MenuEntry("RightPilot 设置…", action: ActionRequest(action: .settings)))
        return entries
    }
}
