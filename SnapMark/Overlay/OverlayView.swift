import AppKit
import QuartzCore

@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayViewDidPressEscape(_ view: OverlayView)
    func overlayView(_ view: OverlayView, rightMouseDownAt localPoint: CGPoint)
}

/// 遮罩视图：显示定格画面，整体压暗，选区内保持原亮度。
///
/// 画面和压暗层都用 CALayer，拖动选区时只需改 path，不重绘整张图。
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()

    /// 压暗程度。
    static let dimAlpha: CGFloat = 0.4

    /// 选区（本地坐标）；nil 表示整屏压暗。
    var selection: CGRect? {
        didSet { updateDimPath() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        imageLayer.contentsGravity = .resize
        imageLayer.actions = Self.noAnimations
        imageLayer.magnificationFilter = .nearest

        dimLayer.fillColor = NSColor.black.withAlphaComponent(Self.dimAlpha).cgColor
        dimLayer.fillRule = .evenOdd
        dimLayer.actions = Self.noAnimations

        layer?.addSublayer(imageLayer)
        layer?.addSublayer(dimLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let noAnimations: [String: CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
        "path": NSNull(), "frame": NSNull(), "hidden": NSNull(),
    ]

    // MARK: 配置

    /// 显示新的定格画面。
    func show(image: CGImage, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contentsScale = scale
        imageLayer.contents = image
        selection = nil
        layoutLayers()
        CATransaction.commit()
    }

    /// 释放截图内存。
    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        selection = nil
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutLayers()
        CATransaction.commit()
    }

    private func layoutLayers() {
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        updateDimPath()
    }

    private func updateDimPath() {
        let path = CGMutablePath()
        path.addRect(bounds)
        if let selection, !selection.isEmpty {
            path.addRect(selection)
        }
        dimLayer.path = path
    }

    // MARK: 事件

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            handleEscape()
            return
        }
        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayView(self, rightMouseDownAt: convert(event.locationInWindow, from: nil))
    }

    func handleEscape() {
        delegate?.overlayViewDidPressEscape(self)
    }
}

/// 常用的虚拟键码。
enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
