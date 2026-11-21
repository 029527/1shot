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

    /// 选中图形的虚线框与编辑控制点。
    var selectedOutline: CGRect? {
        didSet {
            guard oldValue != selectedOutline else { return }
            for rect in [oldValue, selectedOutline].compactMap({ $0 }) { setNeedsDisplay(rect.insetBy(dx: -6, dy: -6)) }
        }
    }
    var editHandles: [CGPoint] = [] {
        didSet {
            guard oldValue != editHandles else { return }
            let r = OverlayView.handleRadius + 3
            for p in oldValue + editHandles { setNeedsDisplay(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
        }
    }

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
        var environment = environment
        environment.bounds = selection
        AnnotationRenderer.draw(shapes, inProgress: inProgress, in: context, environment: environment, dirtyRect: dirtyRect)
        context.restoreGState()

        // 选中图形的装饰不受选区裁剪。
        if let outline = selectedOutline {
            context.saveGState()
            context.setStrokeColor(OverlayView.accentColor.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(outline.insetBy(dx: -2, dy: -2))
            context.restoreGState()
        }
        for handle in editHandles {
            let r = OverlayView.handleRadius
            let rect = CGRect(x: handle.x - r, y: handle.y - r, width: r * 2, height: r * 2)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(OverlayView.accentColor.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect)
        }
    }
}
