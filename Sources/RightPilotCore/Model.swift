import Foundation

public enum PilotError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
public enum Template: String, Codable, CaseIterable {
    case text, markdown, json, yaml, python, shell, rtf, csv, html, xml
    public var title: String {
        switch self { case .text: return "文本文档"; case .markdown: return "Markdown"; case .json: return "JSON"; case .yaml: return "YAML"; case .python: return "Python"; case .shell: return "Shell 脚本"; case .rtf: return "富文本文档"; case .csv: return "CSV 表格"; case .html: return "HTML 网页"; case .xml: return "XML" }
    }
    public var suffix: String {
        switch self { case .text: return "txt"; case .markdown: return "md"; case .json: return "json"; case .yaml: return "yaml"; case .python: return "py"; case .shell: return "sh"; case .rtf: return "rtf"; case .csv: return "csv"; case .html: return "html"; case .xml: return "xml" }
    }
    public var contents: Data {
        let value: String
        switch self { case .json: value = "{}\n"; case .yaml: value = "# YAML\n"; case .python: value = "#!/usr/bin/env python3\n"; case .shell: value = "#!/bin/sh\n"; case .rtf: value = "{\\rtf1\\ansi\\deff0 {\\fonttbl {\\f0 Helvetica;}}\\f0\\fs24 \n}"; case .csv: value = "column1,column2\n"; case .html: value = "<!doctype html>\n<html lang=\"zh-CN\"><head><meta charset=\"utf-8\"><title>Untitled</title></head><body></body></html>\n"; case .xml: value = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>\n"; default: value = "" }
        return Data(value.utf8)
    }
}
public enum Feature: String, Codable, CaseIterable {
    case newFile, newFolder, copyPath, shellPath, fileURL, copyName, terminal, favorites, visibility, copyTo, imageConversion, checksum
    public var title: String {
        switch self { case .newFile: return "新建文件"; case .newFolder: return "新建文件夹"; case .copyPath: return "复制路径"; case .shellPath: return "复制 Shell 路径"; case .fileURL: return "复制文件链接"; case .copyName: return "复制文件名"; case .terminal: return "在终端打开"; case .favorites: return "常用目录"; case .visibility: return "隐藏／取消隐藏"; case .copyTo: return "复制到指定目录"; case .imageConversion: return "图片格式转换"; case .checksum: return "文件 SHA-256" }
    }
}
public enum TerminalChoice: String, Codable, CaseIterable {
    case terminal, iterm
    public var title: String { self == .terminal ? "Terminal" : "iTerm2" }
    public var bundleID: String { self == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2" }
}
public struct Favorite: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String
    public init(id: UUID = UUID(), name: String, path: String) { self.id = id; self.name = name; self.path = path }
}
public struct Configuration: Codable, Equatable {
    public var version = 2
    public var enabled: Set<Feature> = Set(Feature.allCases)
    public var templates: Set<Template> = Set(Template.allCases)
    public var favorites: [Favorite] = []
    public var terminal: TerminalChoice = .terminal
    public var revealCreated = true
    public init() {}
    private enum CodingKeys: String, CodingKey { case version, enabled, templates, favorites, terminal, revealCreated }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decode(Int.self, forKey: .version)
        guard [1, 2].contains(storedVersion) else { throw PilotError.invalid("配置版本不受支持，原文件已保留。") }
        version = 2
        enabled = try c.decode(Set<Feature>.self, forKey: .enabled)
        templates = try c.decode(Set<Template>.self, forKey: .templates)
        favorites = try c.decode([Favorite].self, forKey: .favorites)
        terminal = try c.decode(TerminalChoice.self, forKey: .terminal)
        revealCreated = try c.decode(Bool.self, forKey: .revealCreated)
        if storedVersion == 1 {
            enabled.formUnion([.visibility, .copyTo, .imageConversion, .checksum])
            templates.formUnion([.rtf, .csv, .html, .xml])
        }
        try validate()
    }
    public static func initial(home: URL) -> Configuration {
        var c = Configuration()
        c.favorites = [("桌面", "Desktop"), ("下载", "Downloads"), ("文稿", "Documents")].map { Favorite(name: $0.0, path: home.appendingPathComponent($0.1).path) }
        return c
    }
    public func validate() throws {
        guard version == 2 else { throw PilotError.invalid("配置版本不受支持，原文件已保留。") }
        guard favorites.count <= 30, Set(favorites.map(\.id)).count == favorites.count else { throw PilotError.invalid("常用目录最多 30 个，且标识不能重复。") }
        for f in favorites {
            guard !f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, f.name.count <= 80 else { throw PilotError.invalid("目录名称需要 1–80 个字符。") }
            try Paths.validate(f.path)
        }
    }
}
public enum ConfigurationStore {
    public static func read(_ url: URL, fallback: Configuration) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        let value = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        try value.validate(); return value
    }
    public static func save(_ value: Configuration, to url: URL) throws {
        try value.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
public enum Paths {
    public static func validate(_ path: String) throws {
        guard path.hasPrefix("/"), path.utf8.count <= 4096, !path.utf8.contains(0), !path.split(separator: "/").contains("..") else { throw PilotError.invalid("路径必须是有效的本机绝对路径。") }
    }
    public static func directory(_ path: String) throws -> URL {
        try validate(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { throw PilotError.invalid("目录不存在或无法访问：\(path)") }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    public static func shellQuote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
