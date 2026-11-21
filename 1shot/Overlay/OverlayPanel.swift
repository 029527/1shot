import AppKit

/// 每块屏幕一个的全屏遮罩窗口。提前创建、反复复用。
final class OverlayPanel: NSPanel {
    let overlayView: OverlayView

    init(frame: CGRect) {
        overlayView = OverlayView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isExcludedFromWindowsMenu = true

        contentView = overlayView
        initialFirstResponder = overlayView
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 无边框窗口也不要被系统挪到菜单栏下面。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Esc 在 NSPanel 里会走 cancelOperation，统一交给视图处理。
    override func cancelOperation(_ sender: Any?) {
        overlayView.handleEscape()
    }
}
