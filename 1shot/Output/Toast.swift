import AppKit

/// 选区附近显示 1.5 秒后自动消失的提示。
@MainActor
final class Toast {
    static let shared = Toast()

    static let duration: TimeInterval = 1.5

    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.88).cgColor
        background.layer?.cornerRadius = 10
        panel.contentView = background

        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        return panel
    }

    /// `anchor` 为选区的 AppKit 全局坐标，提示显示在选区中央（保持在所在屏幕内）。
    func show(_ message: String, near anchor: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        label.stringValue = "✓ " + message
        let textWidth = ceil(label.intrinsicContentSize.width)
        let size = CGSize(width: max(120, textWidth + 36), height: 40)

        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) {
            let bounds = screen.frame
            origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
            origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)

        hideWork?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        })
    }
}
