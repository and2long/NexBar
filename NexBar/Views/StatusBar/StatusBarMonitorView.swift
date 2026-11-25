import AppKit
import Foundation

final class StatusBarMonitorView: NSView {
    private var cpuUsage: Double = 0
    private var uploadRate: Double = 0
    private var downloadRate: Double = 0
    private var showCPU: Bool = true
    private var showNetwork: Bool = true

    private let cpuBlockWidth: CGFloat = 30
    private let dividerSpacing: CGFloat = 7
    private let networkBlockWidth: CGFloat = 48

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let NSStatusBarButton handle clicks and native pressed/active highlight.
        nil
    }

    var requiredWidth: CGFloat {
        var width: CGFloat = 0
        if showCPU {
            width += cpuBlockWidth
        }
        if showCPU && showNetwork {
            width += dividerSpacing
        }
        if showNetwork {
            width += networkBlockWidth
        }
        return max(30, width)
    }

    func update(
        cpuUsage: Double,
        uploadRate: Double,
        downloadRate: Double,
        showCPU: Bool,
        showNetwork: Bool
    ) {
        self.cpuUsage = cpuUsage
        self.uploadRate = uploadRate
        self.downloadRate = downloadRate
        self.showCPU = showCPU
        self.showNetwork = showNetwork
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let height = bounds.height
        let topRowY = max(1, (height - 20) / 2)
        let bottomRowY = topRowY + 10
        var cursorX: CGFloat = 0

        let primaryColor = NSColor.labelColor

        let leftAlign = NSMutableParagraphStyle()
        leftAlign.alignment = .left
        leftAlign.lineBreakMode = .byClipping

        let centerAlign = NSMutableParagraphStyle()
        centerAlign.alignment = .center
        centerAlign.lineBreakMode = .byClipping

        if showCPU {
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7.5, weight: .semibold),
                .foregroundColor: primaryColor,
                .paragraphStyle: centerAlign
            ]

            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: primaryColor,
                .paragraphStyle: centerAlign
            ]

            let cpuValueRect = NSRect(x: cursorX, y: topRowY - 0.5, width: cpuBlockWidth, height: 11.5)
            let cpuLabelRect = NSRect(x: cursorX, y: topRowY + 10.5, width: cpuBlockWidth, height: 9.5)

            (ByteRateFormatter.percentString(cpuUsage) as NSString).draw(in: cpuValueRect, withAttributes: valueAttrs)
            ("CPU" as NSString).draw(in: cpuLabelRect, withAttributes: labelAttrs)

            cursorX += cpuBlockWidth
        }

        if showCPU && showNetwork {
            let dividerX = cursorX + floor(dividerSpacing / 2)
            let dividerRect = NSRect(x: dividerX, y: topRowY + 3, width: 0.75, height: 14)
            NSColor.separatorColor.withAlphaComponent(0.55).setFill()
            NSBezierPath(rect: dividerRect).fill()
            cursorX += dividerSpacing
        }

        if showNetwork {
            let netFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
            let upAttrs: [NSAttributedString.Key: Any] = [
                .font: netFont,
                .foregroundColor: primaryColor,
                .paragraphStyle: leftAlign
            ]
            let downAttrs: [NSAttributedString.Key: Any] = [
                .font: netFont,
                .foregroundColor: primaryColor,
                .paragraphStyle: leftAlign
            ]

            let upText = "↑ \(ByteRateFormatter.compactRate(uploadRate))" as NSString
            let downText = "↓ \(ByteRateFormatter.compactRate(downloadRate))" as NSString

            let upRect = NSRect(x: cursorX, y: topRowY - 0.5, width: networkBlockWidth, height: 10.5)
            let downRect = NSRect(x: cursorX, y: bottomRowY - 0.5, width: networkBlockWidth, height: 10.5)

            upText.draw(in: upRect, withAttributes: upAttrs)
            downText.draw(in: downRect, withAttributes: downAttrs)
        }
    }
}
