import AppKit

// The user-selected Click artwork is shared by the host and Finder extension.
enum PilotArtwork {
    static func brand(size: CGFloat, sourceURL: URL? = nil) -> NSImage {
        let url = sourceURL ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png")
        let source = url.flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "RightPilot")!
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        if url != nil {
            // A consistent native silhouette keeps the generated texture inside the tile.
            NSBezierPath(roundedRect: NSRect(x: size * 0.06, y: size * 0.06, width: size * 0.88, height: size * 0.88), xRadius: size * 0.19, yRadius: size * 0.19).addClip()
        }
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
    static func menu(_ icon: MenuIcon) -> NSImage {
        let color: NSColor
        switch icon {
        case .document, .folder: color = .systemGreen
        case .favorite, .addFavorite: color = .systemPink
        case .path, .link, .copyTo: color = .systemTeal
        case .terminal, .shell, .settings: color = .systemIndigo
        case .hide, .show: color = .systemGray
        case .image: color = .systemPurple
        case .name, .checksum, .tools: color = .systemOrange
        }
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        color.setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 16, height: 16), xRadius: 4, yRadius: 4).fill()
        if let symbol = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil) {
            let tinted = NSImage(size: NSSize(width: 12, height: 12))
            tinted.lockFocus(); symbol.draw(in: NSRect(x: 0, y: 0, width: 12, height: 12))
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 12, height: 12).fill(using: .sourceIn)
            tinted.unlockFocus(); tinted.draw(in: NSRect(x: 2, y: 2, width: 12, height: 12))
        }
        image.unlockFocus(); image.isTemplate = false; return image
    }
}
