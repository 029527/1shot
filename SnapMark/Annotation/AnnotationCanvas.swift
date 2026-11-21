import AppKit

/// 在遮罩上实时显示标注（屏幕本地坐标，铺满整块屏幕，只画选区内）。
final class AnnotationCanvasView: NSView {
    var shapes: [any AnnotationShape] = [] {
        didSet { invalidateSelection() }
    }

    /// 正在拖动绘制的图形。
    var inProgress: (any AnnotationShape)? {
        didSet { invalidateSelection() }
    }

    var selection: CGRect = .zero {
        didSet {
            if oldValue != selection {
                setNeedsDisplay(oldValue.insetBy(dx: -2, dy: -2))
                invalidateSelection()
            }
        }
    }

    var environment = AnnotationEnvironment()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func invalidateSelection() {
        // 只刷新选区，避免每次拖动都重绘整块屏幕。
        setNeedsDisplay(selection.insetBy(dx: -2, dy: -2))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, !selection.isEmpty else { return }
        context.saveGState()
        context.clip(to: selection)
        for shape in shapes where shape.bounds.intersects(dirtyRect) {
            shape.draw(in: context, environment: environment)
        }
        inProgress?.draw(in: context, environment: environment)
        context.restoreGState()
    }
}
