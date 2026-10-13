import AppKit

// Original vector mark: a pointer selecting a short menu, with a teal active row.
// Shared by the app icon, Finder root and settings. No third-party image assets.
enum PilotArtwork {
    static func brand(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let transform = NSAffineTransform(); transform.scale(by: size / 1024); transform.concat()
        let outer = NSRect(x: 48, y: 48, width: 928, height: 928)
        let background = NSBezierPath(roundedRect: outer, xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.38, blue: 0.83, alpha: 1), ending: NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.40, alpha: 1))!.draw(in: background, angle: -70)
        for (y, width) in [(CGFloat(660), CGFloat(370)), (CGFloat(485), CGFloat(285)), (CGFloat(310), CGFloat(370))] {
            (y == 485 ? NSColor(calibratedRed: 0.22, green: 0.89, blue: 0.77, alpha: 1) : NSColor.white.withAlphaComponent(0.28)).setFill()
            NSBezierPath(roundedRect: NSRect(x: 435, y: y, width: width, height: 76), xRadius: 32, yRadius: 32).fill()
        }
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: 215, y: 770)); pointer.line(to: NSPoint(x: 215, y: 275))
        pointer.line(to: NSPoint(x: 330, y: 386)); pointer.line(to: NSPoint(x: 415, y: 203))
        pointer.line(to: NSPoint(x: 505, y: 245)); pointer.line(to: NSPoint(x: 417, y: 429))
        pointer.line(to: NSPoint(x: 576, y: 429)); pointer.close()
        NSColor.white.setFill(); pointer.fill()
        image.unlockFocus(); image.isTemplate = false
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
