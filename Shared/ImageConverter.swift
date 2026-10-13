import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageConverter {
    enum Format { case png, jpeg
        var suffix: String { self == .png ? "png" : "jpg" }
        var type: CFString { (self == .png ? UTType.png.identifier : UTType.jpeg.identifier) as CFString }
    }
    static func convert(_ path: String, to format: Format) throws -> URL {
        try Paths.validate(path)
        let input = URL(fileURLWithPath: path)
        let info = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 100 * 1024 * 1024 else { throw PilotError.invalid("仅支持 100 MB 以内的普通图片文件。") }
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 40_000_000 / height else { throw PilotError.invalid("仅支持单帧且不超过 4000 万像素的图片；动画和多页图片保持原状。") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height), kCGImageSourceShouldCacheImmediately: true]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw PilotError.invalid("系统无法解码这张图片。") }
        if format == .jpeg {
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PilotError.invalid("无法创建 JPEG 画布。") }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let opaque = context.makeImage() else { throw PilotError.invalid("JPEG 合成失败。") }; image = opaque
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.type, 1, nil) else { throw PilotError.invalid("无法创建图片编码器。") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PilotError.invalid("图片编码失败，原文件没有改动。") }
        let directory = input.deletingLastPathComponent()
        let name = FileCreator.suggestedName(in: directory, stem: input.deletingPathExtension().lastPathComponent, suffix: format.suffix)
        return try FileCreator.write(output as Data, in: directory, name: name)
    }
}
