import AppKit
import UniformTypeIdentifiers

@MainActor
enum ProcessIconProvider {
    private static var iconCache: [Int32: NSImage] = [:]
    private static let fallbackIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .unixExecutable)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }()

    static func icon(for process: ProcessSnapshot) -> NSImage {
        if let cached = iconCache[process.pid] {
            return cached
        }

        let icon: NSImage
        if let application = NSRunningApplication(processIdentifier: process.pid),
           let applicationIcon = application.icon {
            icon = applicationIcon
        } else {
            icon = fallbackIcon.copy() as? NSImage ?? fallbackIcon
        }
        icon.size = NSSize(width: 18, height: 18)
        iconCache[process.pid] = icon
        return icon
    }
}
