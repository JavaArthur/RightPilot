import SwiftUI
import FinderSync

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.and.square.on.square.dashed").font(.system(size: 32)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RightPilot").font(.system(size: 25, weight: .semibold))
                    Text("让 Finder 里的日常操作更顺手").foregroundStyle(.secondary)
                }
                Spacer()
                Text("1.0").foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            TabView {
                general.tabItem { Label("开始使用", systemImage: "sparkles") }
                menu.tabItem { Label("右键菜单", systemImage: "list.bullet") }
                favorites.tabItem { Label("常用目录", systemImage: "folder") }
            }.padding(16)
            if let problem = model.problem {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(problem).textSelection(.enabled)
                    Spacer()
                    Button("关闭") { model.problem = nil }
                }.padding(14).background(Color.orange.opacity(0.08))
            }
        }.frame(width: 680, height: 580)
        .onAppear { model.refreshStatus() }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.extensionEnabled ? "Finder 扩展已启用" : "先启用 Finder 扩展", systemImage: model.extensionEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.headline).foregroundStyle(model.extensionEnabled ? .green : .primary)
                    Text("点击下方按钮，在系统设置的 Finder 扩展中打开 RightPilot。然后在 Finder 文件夹空白处或文件上点击右键，选择 RightPilot。").foregroundStyle(.secondary)
                    HStack {
                        Button("打开扩展设置") { FIFinderSyncController.showExtensionManagementInterface() }
                        Button("刷新状态") { model.refreshStatus(); model.broadcast() }
                    }
                    if let sync = model.lastSync { Text("扩展最近同步：\(sync.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                    else { Text("尚未收到扩展同步回执。启用后请打开一个 Finder 文件夹。").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Toggle("登录后启动 RightPilot", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
            Toggle("新建后在 Finder 中选中文件", isOn: Binding(get: { model.configuration.revealCreated }, set: { value in model.change { $0.revealCreated = value } })).disabled(model.readOnly)
            Picker("默认终端", selection: Binding(get: { model.configuration.terminal }, set: { value in model.change { $0.terminal = value } })) {
                ForEach(TerminalChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }.frame(width: 250).disabled(model.readOnly)
            Text("新文件不会覆盖已有文件。所有处理在本机完成。Terminal 默认可用；选择 iTerm2 前请先安装它。").font(.callout).foregroundStyle(.secondary)
            Text("保持菜单栏应用运行可及时同步设置。若目录访问被 macOS 拒绝，可从菜单栏的“选择目录进行操作”重新选择目录。").font(.callout).foregroundStyle(.secondary)
            Spacer()
        }.padding(12)
    }
    private var menu: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 12) {
                Text("显示的操作").font(.headline)
                ForEach(Feature.allCases, id: \.self) { feature in
                    Toggle(feature.title, isOn: Binding(get: { model.configuration.enabled.contains(feature) }, set: { yes in model.change { if yes { $0.enabled.insert(feature) } else { $0.enabled.remove(feature) } } }))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("新建文件类型").font(.headline)
                ForEach(Template.allCases, id: \.self) { type in
                    Toggle(type.title + " (." + type.suffix + ")", isOn: Binding(get: { model.configuration.templates.contains(type) }, set: { yes in model.change { if yes { $0.templates.insert(type) } else { $0.templates.remove(type) } } }))
                }
                Text("Shell 文件只创建文本，不自动执行，也不添加执行权限。").font(.caption).foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
            }
            Spacer()
        }.padding(16).disabled(model.readOnly)
    }
    private var favorites: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("按顺序显示在右键菜单中，最多 30 个。").foregroundStyle(.secondary); Spacer(); Button("添加目录…", action: model.chooseFavorite).disabled(model.readOnly) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(model.configuration.favorites.enumerated()), id: \.element.id) { index, favorite in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                FavoriteNameField(name: favorite.name) { value in model.change { c in if let i = c.favorites.firstIndex(where: { $0.id == favorite.id }) { c.favorites[i].name = value } } }
                                Text(favorite.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(favorite.path)
                            }
                            Button { if let folder = try? Paths.directory(favorite.path) { NSWorkspace.shared.open(folder) } else { model.problem = "目录不存在：\(favorite.path)" } } label: { Image(systemName: "arrow.up.forward.square") }.help("在 Finder 中打开")
                            Button { model.change { $0.favorites.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("上移")
                            Button { model.change { $0.favorites.removeAll { $0.id == favorite.id } } } label: { Image(systemName: "minus") }.help("移出常用目录，不删除文件")
                        }.padding(10).background(Color.primary.opacity(0.035)).cornerRadius(8)
                    }
                }
            }.disabled(model.readOnly)
            Spacer(minLength: 0)
        }.padding(12)
    }
}

private struct FavoriteNameField: View {
    let name: String
    let save: (String) -> Void
    @State private var draft: String
    init(name: String, save: @escaping (String) -> Void) { self.name = name; self.save = save; _draft = State(initialValue: name) }
    var body: some View {
        HStack {
            TextField("名称", text: $draft).onSubmit { save(draft) }
            if draft != name { Button { save(draft) } label: { Image(systemName: "checkmark") }.help("保存名称") }
        }.onChange(of: name) { draft = $0 }
    }
}
