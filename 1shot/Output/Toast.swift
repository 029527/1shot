import AppKit

/// 选区附近短暂显示的提示。
///
/// - 完成类（已复制 / 已保存）：带「不再显示」按钮，点了之后关闭设置里的「显示完成提示」；
///   用户关掉后不再显示（设置里可以重新打开）。鼠标悬停时暂停消失，方便点按钮。
/// - 提醒类（保存失败、没有识别到文字等）：总是显示。
@MainActor
final class Toast {
    static let shared = Toast()

    enum Kind {
        case completion
        case notice
    }

    static let completionDuration: TimeInterval = 2.5
    static let noticeDuration: TimeInterval = 2

    private var panel: NSPanel?
    private let icon = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private let dismissButton = ToastButton(title: String(localized: "不再显示"), target: nil, action: nil)
    private var hideWork: DispatchWorkItem?
    private var duration: TimeInterval = 2
    private(set) var isHovered = false

    /// 完成提示（复制、保存成功）。用户关掉了「显示完成提示」时什么都不做。
    func showCompletion(_ message: String, near anchor: CGRect) {
        guard Preferences.showToast else { return }
        show(message, near: anchor, kind: .completion)
    }

    /// `anchor` 为选区的 AppKit 全局坐标，提示显示在选区中央（保持在所在屏幕内）。
    func show(_ message: String, near anchor: CGRect, kind: Kind = .notice) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let isCompletion = kind == .completion
        icon.stringValue = isCompletion ? "✓" : "⚠︎"
        label.stringValue = message
        dismissButton.isHidden = !isCompletion
        // 只有带按钮时才接收鼠标，否则点穿到下面的内容。
        panel.ignoresMouseEvents = !isCompletion
        duration = isCompletion ? Self.completionDuration : Self.noticeDuration

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = CGSize(width: max(120, ceil(panel.contentView?.fittingSize.width ?? 120)), height: 40)
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) {
            let bounds = screen.frame
            origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
            origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        isHovered = false
        scheduleHide(after: duration)
    }

    /// 「不再显示」：关闭完成提示，并告诉用户在哪里重新打开。
    func dontShowAgain() {
        Preferences.showToast = false
        Log.app.notice("用户关闭了完成提示")
        let anchor = panel?.frame ?? .zero
        show(String(localized: "已关闭完成提示，可在设置 › 通用中重新打开"), near: anchor, kind: .notice)
    }

    var isVisible: Bool { panel?.isVisible == true && (panel?.alphaValue ?? 0) > 0 }

    // MARK: 内部

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hide() {
        guard let panel, !isHovered else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        })
    }

    fileprivate func hoverChanged(_ hovered: Bool) {
        isHovered = hovered
        if hovered {
            hideWork?.cancel()
            panel?.animator().alphaValue = 1
        } else {
            scheduleHide(after: 1)
        }
    }

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
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none

        let background = ToastBackground()
        background.onHover = { [weak self] in self?.hoverChanged($0) }
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.88).cgColor
        background.layer?.cornerRadius = 10
        panel.contentView = background

        for field in [icon, label] {
            field.font = .systemFont(ofSize: 14, weight: .medium)
            field.textColor = .white
        }
        dismissButton.isBordered = false
        dismissButton.font = .systemFont(ofSize: 12)
        dismissButton.contentTintColor = NSColor(white: 1, alpha: 0.6)
        dismissButton.attributedTitle = NSAttributedString(string: dismissButton.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 1, alpha: 0.6),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)
        dismissButton.toolTip = String(localized: "以后不再显示复制、保存完成的提示")

        let stack = NSStackView(views: [icon, label, dismissButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.setCustomSpacing(14, after: label)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        return panel
    }

    @objc private func dismissClicked() {
        dontShowAgain()
    }
}

/// 提示背景：报告鼠标进出（悬停时暂停消失）。
private final class ToastBackground: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// 不是 key 窗口也能一次点中。
private final class ToastButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
