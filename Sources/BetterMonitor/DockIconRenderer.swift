import AppKit
import Foundation

@MainActor
enum DockIconRenderer {
    private static var originalIcon: NSImage?

    static func update(mode: DockIconMode, snapshot: MonitorSnapshot, history: MonitorHistory) {
        let application: NSApplication? = NSApp
        guard let application else { return }

        if originalIcon == nil {
            originalIcon = application.applicationIconImage?.copy() as? NSImage
        }

        guard mode != .appIcon else {
            application.applicationIconImage = originalIcon
            return
        }

        application.applicationIconImage = render(mode: mode, snapshot: snapshot, history: history)
    }

    private static func render(mode: DockIconMode, snapshot: MonitorSnapshot, history: MonitorHistory) -> NSImage {
        let size = NSSize(width: 128, height: 128)
        return NSImage(size: size, flipped: false) { rect in
            drawBackground(in: rect)
            switch mode {
            case .appIcon:
                break
            case .cpuUsage:
                drawCPUUsage(snapshot.summary.cpu, in: rect)
            case .cpuHistory:
                drawHistory(values: history.values(for: .cpu), color: .controlAccentColor, label: "CPU", in: rect)
            case .networkUsage:
                drawHistory(values: history.networkBytesPerSecond, color: .systemGreen, label: "NET", in: rect)
            case .diskActivity:
                drawHistory(values: history.diskBytesPerSecond, color: .systemPurple, label: "DISK", in: rect)
            }
            return true
        }
    }

    private static func drawBackground(in rect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 24, yRadius: 24).fill()
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 5.5, dy: 5.5), xRadius: 24, yRadius: 24)
        border.lineWidth = 1
        border.stroke()
    }

    private static func drawCPUUsage(_ cpu: CPUSummary, in rect: NSRect) {
        let graphRect = rect.insetBy(dx: 20, dy: 22)
        let userHeight = graphRect.height * CGFloat((cpu.userPercent / 100).clampedPercent)
        let systemHeight = graphRect.height * CGFloat((cpu.systemPercent / 100).clampedPercent)
        let idleHeight = max(0, graphRect.height - userHeight - systemHeight)
        var y = graphRect.minY

        NSColor.systemGray.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: graphRect.minX, y: y, width: graphRect.width, height: idleHeight), xRadius: 8, yRadius: 8).fill()
        y += idleHeight
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: graphRect.minX, y: y, width: graphRect.width, height: userHeight)).fill()
        y += userHeight
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: graphRect.minX, y: y, width: graphRect.width, height: systemHeight)).fill()

        drawLabel("CPU", in: rect)
    }

    private static func drawHistory(values: [Double], color: NSColor, label: String, in rect: NSRect) {
        let graphRect = rect.insetBy(dx: 16, dy: 26)
        NSColor.textBackgroundColor.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: graphRect, xRadius: 10, yRadius: 10).fill()

        guard values.count > 1 else {
            drawLabel(label, in: rect)
            return
        }

        let maxValue = max(values.max() ?? 1, 1)
        let path = NSBezierPath()
        for index in values.indices {
            let progress = CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let x = graphRect.minX + graphRect.width * progress
            let y = graphRect.minY + graphRect.height * CGFloat(values[index] / maxValue)
            let point = NSPoint(x: x, y: y)
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        color.setStroke()
        path.lineWidth = 5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
        drawLabel(label, in: rect)
    }

    private static func drawLabel(_ label: String, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSString(string: label)
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.minY + 12),
            withAttributes: attributes
        )
    }
}
