import Foundation
import CryptoKit
import Darwin

public struct BatchOutcome {
    public var succeeded: [String] = []
    public var failures: [String] = []
    public init() {}
    public var summary: String {
        "成功 \(succeeded.count) 项，失败 \(failures.count) 项。" + (failures.isEmpty ? "" : "\n\n" + failures.prefix(8).joined(separator: "\n"))
    }
}
public enum FileOperations {
    public static func immediateChildren(of directory: String) throws -> [String] {
        let root = try Paths.directory(directory)
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])
        guard urls.count <= 1000 else { throw PilotError.invalid("目录项目超过 1000 个，请分批选择项目操作。") }
        return urls.map(\.path).sorted()
    }
    public static func setHidden(_ paths: [String], hidden: Bool) -> BatchOutcome {
        var outcome = BatchOutcome()
        for path in paths {
            do {
                try Paths.validate(path)
                var info = stat()
                guard lstat(path, &info) == 0 else { throw posix() }
                guard info.st_mode & S_IFMT != S_IFLNK else { throw PilotError.invalid("跳过符号链接，不修改其目标。") }
                guard URL(fileURLWithPath: path).lastPathComponent.first != "." else { throw PilotError.invalid("点号文件保持原状；本功能不会重命名文件。") }
                let flags = hidden ? info.st_flags | UInt32(UF_HIDDEN) : info.st_flags & ~UInt32(UF_HIDDEN)
                guard lchflags(path, flags) == 0 else { throw posix() }
                outcome.succeeded.append(path)
            } catch { outcome.failures.append("\(URL(fileURLWithPath: path).lastPathComponent)：\(error.localizedDescription)") }
        }
        return outcome
    }
    public static func copy(_ paths: [String], to directory: URL) -> BatchOutcome {
        var result = BatchOutcome()
        for path in paths {
            do {
                try Paths.validate(path); _ = try Paths.directory(directory.path)
                let source = URL(fileURLWithPath: path)
                let destination = directory.appendingPathComponent(source.lastPathComponent)
                let sourceReal = source.resolvingSymlinksInPath().standardizedFileURL.path
                let destinationReal = destination.resolvingSymlinksInPath().standardizedFileURL.path
                guard destinationReal != sourceReal, !destinationReal.hasPrefix(sourceReal + "/") else { throw PilotError.invalid("不能复制到自身或其子目录。") }
                // Foundation refuses existing destinations, including dangling symlinks.
                try FileManager.default.copyItem(at: source, to: destination)
                result.succeeded.append(destination.path)
            } catch { result.failures.append("\(URL(fileURLWithPath: path).lastPathComponent)：\(error.localizedDescription)") }
        }
        return result
    }
    public static func sha256(_ path: String) throws -> String {
        try Paths.validate(path)
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw posix() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { Darwin.close(fd); throw PilotError.invalid("SHA-256 只支持普通文件，不读取链接、目录或设备。") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        var after = stat()
        guard fstat(fd, &after) == 0, after.st_size == info.st_size, after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { throw PilotError.invalid("计算期间文件发生变化，请重试。") }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func posix() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
