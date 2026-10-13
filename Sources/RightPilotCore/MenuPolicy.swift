import Foundation

public struct MenuContext {
    public var paths: [String]
    public var directory: String?
    public var files: [String]
    public var background: Bool
    public init(target: URL?, selected: [URL], background: Bool, isDirectory: (URL) -> Bool) {
        self.background = background
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
        files = background ? [] : paths.filter { !isDirectory(URL(fileURLWithPath: $0)) }
    }
}
public enum MenuIcon: String, CaseIterable {
    case document, folder, path, terminal, favorite, addFavorite, settings, shell, link, name, hide, show, copyTo, image, checksum, tools
    public var symbol: String {
        switch self {
        case .document: return "doc.badge.plus"; case .folder: return "folder.badge.plus"; case .path: return "doc.on.clipboard"
        case .terminal: return "terminal"; case .favorite: return "heart.fill"; case .addFavorite: return "folder.badge.plus"; case .settings: return "gearshape"
        case .shell: return "chevron.left.forwardslash.chevron.right"; case .link: return "link"; case .name: return "textformat.abc"
        case .hide: return "eye.slash"; case .show: return "eye"; case .copyTo: return "doc.on.doc"; case .image: return "photo"; case .checksum: return "number"; case .tools: return "wrench.and.screwdriver"
        }
    }
}
public struct MenuEntry {
    public var title: String
    public var action: ActionRequest?
    public var children: [MenuEntry]
    public var enabled: Bool
    public var icon: MenuIcon
    public var isSeparator: Bool { title.isEmpty && action == nil && children.isEmpty }
    public init(_ title: String, action: ActionRequest? = nil, children: [MenuEntry] = [], enabled: Bool = true, icon: MenuIcon = .document) { self.title = title; self.action = action; self.children = children; self.enabled = enabled; self.icon = icon }
}
public enum MenuPolicy {
    public static func entries(context: MenuContext, configuration c: Configuration) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        let directory = context.directory.map { [$0] } ?? []
        let validSelection = !context.paths.isEmpty && context.paths.count <= 100
        if c.enabled.contains(.newFile) {
            let children = Template.allCases.filter { c.templates.contains($0) }.map { MenuEntry($0.title + " (." + $0.suffix + ")", action: ActionRequest(action: .createFile, paths: directory, template: $0)) }
            if !children.isEmpty { entries.append(MenuEntry("新建文件", children: children, enabled: !directory.isEmpty)) }
        }
        if c.enabled.contains(.newFolder) { entries.append(MenuEntry("新建文件夹…", action: ActionRequest(action: .createFolder, paths: directory), enabled: !directory.isEmpty, icon: .folder)) }
        if c.enabled.contains(.copyPath) { entries.append(MenuEntry("复制路径", action: ActionRequest(action: .copyPath, paths: context.paths), enabled: validSelection, icon: .path)) }
        var copies: [MenuEntry] = []
        for (feature, action, icon) in [(Feature.shellPath, Action.copyShellPath, MenuIcon.shell), (.fileURL, .copyFileURL, .link), (.copyName, .copyName, .name)] where c.enabled.contains(feature) {
            copies.append(MenuEntry(feature.title, action: ActionRequest(action: action, paths: context.paths), enabled: validSelection, icon: icon))
        }
        if !copies.isEmpty { entries.append(MenuEntry("更多复制", children: copies, enabled: validSelection, icon: .copyTo)) }
        if c.enabled.contains(.terminal) { entries.append(MenuEntry("在 \(c.terminal.title) 打开", action: ActionRequest(action: .terminal, paths: directory), enabled: !directory.isEmpty, icon: .terminal)) }
        if c.enabled.contains(.favorites) {
            var children = c.favorites.map { MenuEntry($0.name, action: ActionRequest(action: .favorite, favoriteID: $0.id), icon: .favorite) }
            children.append(MenuEntry("将此目录加入常用…", action: ActionRequest(action: .addFavorite, paths: directory), enabled: !directory.isEmpty, icon: .addFavorite))
            entries.append(MenuEntry("常用目录", children: children, icon: .favorite))
        }
        var tools: [MenuEntry] = []
        if c.enabled.contains(.copyTo) { tools.append(MenuEntry("复制到目录…", action: ActionRequest(action: .copyTo, paths: context.paths), enabled: validSelection && !context.background, icon: .copyTo)) }
        if c.enabled.contains(.visibility) {
            if !context.background {
                tools.append(MenuEntry("隐藏所选项目…", action: ActionRequest(action: .hideItems, paths: context.paths), enabled: validSelection, icon: .hide))
                tools.append(MenuEntry("取消隐藏所选项目…", action: ActionRequest(action: .showItems, paths: context.paths), enabled: validSelection, icon: .show))
            }
            tools.append(MenuEntry("隐藏当前目录中的项目…", action: ActionRequest(action: .hideContents, paths: directory), enabled: !directory.isEmpty, icon: .hide))
            tools.append(MenuEntry("取消隐藏当前目录中的项目…", action: ActionRequest(action: .showContents, paths: directory), enabled: !directory.isEmpty, icon: .show))
        }
        if c.enabled.contains(.checksum) { tools.append(MenuEntry("复制 SHA-256", action: ActionRequest(action: .sha256, paths: context.files), enabled: !context.files.isEmpty && context.files.count <= 100, icon: .checksum)) }
        if !tools.isEmpty { entries.append(MenuEntry("文件操作", children: tools, icon: .tools)) }
        if c.enabled.contains(.imageConversion) {
            let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
            let images = context.files.filter { extensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            entries.append(MenuEntry("图片转换", children: [
                MenuEntry("转换为 PNG", action: ActionRequest(action: .convertPNG, paths: images), icon: .image),
                MenuEntry("转换为 JPEG（白色背景）", action: ActionRequest(action: .convertJPEG, paths: images), icon: .image)
            ], enabled: !images.isEmpty && images.count <= 100 && images.count == context.paths.count, icon: .image))
        }
        if !entries.isEmpty { entries.append(MenuEntry("")) }
        entries.append(MenuEntry("RightPilot 设置…", action: ActionRequest(action: .settings), icon: .settings))
        return entries
    }
}
