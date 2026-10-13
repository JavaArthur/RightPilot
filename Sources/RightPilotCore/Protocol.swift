import Foundation

public enum Action: String, Codable { case createFile, createFolder, copyPath, copyShellPath, copyFileURL, copyName, terminal, favorite, addFavorite, settings, hideItems, showItems, hideContents, showContents, copyTo, convertPNG, convertJPEG, sha256 }
public struct ActionRequest: Codable, Equatable {
    public var version = 1
    public var id: UUID
    public var action: Action
    public var paths: [String]
    public var template: Template?
    public var favoriteID: UUID?
    public init(action: Action, paths: [String] = [], template: Template? = nil, favoriteID: UUID? = nil) {
        self.id = UUID(); self.action = action; self.paths = paths; self.template = template; self.favoriteID = favoriteID
    }
    public func validate() throws {
        guard version == 1, paths.count <= 100 else { throw PilotError.invalid("不支持的操作或一次选择超过 100 个文件。") }
        for path in paths { try Paths.validate(path) }
        switch action {
        case .createFile: guard paths.count == 1, template != nil else { throw PilotError.invalid("新建文件参数不完整。") }
        case .createFolder, .terminal, .addFavorite, .hideContents, .showContents: guard paths.count == 1 else { throw PilotError.invalid("请选择一个目录。") }
        case .copyPath, .copyShellPath, .copyFileURL, .copyName, .hideItems, .showItems, .copyTo, .convertPNG, .convertJPEG, .sha256: guard !paths.isEmpty else { throw PilotError.invalid("没有可操作的文件。") }
        case .favorite: guard favoriteID != nil, paths.isEmpty else { throw PilotError.invalid("常用目录参数不完整。") }
        case .settings: guard paths.isEmpty else { throw PilotError.invalid("无效的设置请求。") }
        }
        if action != .createFile && template != nil { throw PilotError.invalid("此操作不接受模板。") }
        if action != .favorite && favoriteID != nil { throw PilotError.invalid("此操作不接受目录标识。") }
    }
    public func url() throws -> URL {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 24_000 else { throw PilotError.invalid("选中的路径过多，请分批操作。") }
        var c = URLComponents(); c.scheme = "rightpilot"; c.host = "action"
        c.queryItems = [URLQueryItem(name: "payload", value: data.base64EncodedString())]
        guard let url = c.url else { throw PilotError.invalid("无法生成操作请求。") }; return url
    }
    public static func decode(_ url: URL) throws -> ActionRequest {
        guard url.absoluteString.utf8.count <= 40_000, let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "rightpilot", c.host == "action", c.path.isEmpty, c.fragment == nil, c.user == nil, c.password == nil, c.port == nil,
              let items = c.queryItems, items.count == 1, items[0].name == "payload", let value = items[0].value, let data = Data(base64Encoded: value), data.count <= 24_000 else { throw PilotError.invalid("无效的 RightPilot 操作链接。") }
        let request = try JSONDecoder().decode(ActionRequest.self, from: data); try request.validate(); return request
    }
}
public enum CopyFormat { case path, shell, fileURL, name }
public enum ClipboardText {
    public static func render(_ paths: [String], as format: CopyFormat) throws -> String {
        guard !paths.isEmpty else { throw PilotError.invalid("没有可复制的路径。") }
        for p in paths { try Paths.validate(p) }
        return paths.map { path in
            switch format { case .path: return path; case .shell: return Paths.shellQuote(path); case .fileURL: return URL(fileURLWithPath: path).absoluteString; case .name: return URL(fileURLWithPath: path).lastPathComponent }
        }.joined(separator: format == .shell ? " " : "\n")
    }
}
public enum PilotIPC {
    public static let config = "cn.aichanning.RightPilot.config.v1"
    public static let requestConfig = "cn.aichanning.RightPilot.requestConfig.v1"
    public static let acknowledge = "cn.aichanning.RightPilot.ack.v1"
    public static func encode(_ configuration: Configuration) throws -> String {
        try configuration.validate(); return String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self)
    }
    public static func decode(_ text: String) throws -> Configuration {
        guard text.utf8.count <= 180_000 else { throw PilotError.invalid("配置过大。") }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(text.utf8)); try config.validate(); return config
    }
}
