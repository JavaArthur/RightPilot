import Foundation
import Darwin

public enum FileCreator {
    public static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), name.utf8.count <= 255 else { throw PilotError.invalid("名称不能为空，且不能包含 /、:、控制字符或超过 255 字节。") }
    }
    public static func suggestedName(in directory: URL, stem: String, suffix: String? = nil) -> String {
        for index in 1...10_000 {
            let name = stem + (index == 1 ? "" : " \(index)") + (suffix.map { "." + $0 } ?? "")
            if !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) { return name }
        }
        return UUID().uuidString + (suffix.map { "." + $0 } ?? "")
    }
    @discardableResult public static func create(in directory: URL, name: String, template: Template?) throws -> URL {
        try validateName(name)
        guard directory.isFileURL else { throw PilotError.invalid("只能在本地文件夹中创建文件。") }
        _ = try Paths.directory(directory.path)
        let url = directory.appendingPathComponent(name)
        if let template {
            return try write(template.contents, in: directory, name: name)
        } else {
            guard mkdir(url.path, mode_t(0o755)) == 0 else { throw failure(errno, name: name) }
        }
        return url
    }
    @discardableResult public static func write(_ data: Data, in directory: URL, name: String) throws -> URL {
        try validateName(name)
        guard directory.isFileURL else { throw PilotError.invalid("只能在本地目录写入文件。") }
        _ = try Paths.directory(directory.path)
        let url = directory.appendingPathComponent(name)
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o644))
        guard fd >= 0 else { throw failure(errno, name: name) }
        var completed = false
        defer { Darwin.close(fd); if !completed { Darwin.unlink(url.path) } }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw failure(errno, name: name) }; offset += n
            }
        }
        guard fsync(fd) == 0 else { throw failure(errno, name: name) }
        completed = true
        return url
    }
    private static func failure(_ code: Int32, name: String) -> Error {
        if code == EEXIST { return PilotError.invalid("“\(name)”已存在，请换一个名称；原文件没有改动。") }
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "无法创建“\(name)”：\(String(cString: strerror(code)))"])
    }
}
