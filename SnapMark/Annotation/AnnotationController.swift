import AppKit

/// 一次截图里的标注：当前工具与样式、标注文档、绘制中的图形、文字输入、属性条。
/// 所有坐标为选区所在屏幕的本地 pt 坐标。
@MainActor
final class AnnotationController {
    /// 标注增删、撤销重做、工具或样式变化后回调（控制器据此锁定选区、刷新工具栏）。
    var onChange: (() -> Void)?

    private(set) var tool: AnnotationTool?
    private(set) var document = AnnotationDocument()
    private var builder: ShapeBuilder?
    private var styles = StyleStore()

    let canvas = AnnotationCanvasView(frame: .zero)
    let stylePanel = StylePanelView(frame: .zero)
    private let textEditor = TextEditingController()

    private var selection: CGRect = .zero
    private var display: DisplayCapture?
    private var mosaicSource: MosaicSource?

    init() {
        stylePanel.delegate = self
        stylePanel.isHidden = true
        textEditor.onFinish = { [weak self] shape in self?.textFinished(shape) }
    }

    /// reset() 时丢弃正在输入的文字。
    private var isResetting = false

    private func textFinished(_ shape: TextShape?) {
        guard !isResetting else { return }
        if let shape { document.add(shape) }
        syncCanvas()
        onChange?()
    }

    var isEditingText: Bool { textEditor.isEditing }
    var isDrawing: Bool { builder != nil }
    var hasAnnotations: Bool { !document.isEmpty }

    var currentStyle: ToolStyle? {
        tool.map { styles.style(for: $0) }
    }

    // MARK: 会话

    func reset() {
        isResetting = true
        textEditor.finish()
        isResetting = false
        tool = nil
        builder = nil
        document.removeAll()
        mosaicSource = nil
        display = nil
        selection = .zero
        canvas.shapes = []
        canvas.inProgress = nil
        canvas.environment = AnnotationEnvironment()
        canvas.removeFromSuperview()
        stylePanel.isHidden = true
        stylePanel.removeFromSuperview()
    }

    /// 把画布挂到选区所在屏幕，并同步选区。
    func attach(to view: OverlayView, display: DisplayCapture, selection: CGRect) {
        if canvas.superview !== view.annotationHost {
            canvas.frame = view.annotationHost.bounds
            canvas.autoresizingMask = [.width, .height]
            view.annotationHost.addSubview(canvas)
        }
        if self.display?.displayID != display.displayID {
            self.display = display
            mosaicSource = nil
            canvas.environment = AnnotationEnvironment()
        }
        self.selection = selection
        canvas.selection = selection
    }

    /// 属性条放在工具栏旁边；没有选中工具时隐藏。
    func layoutStylePanel(in view: OverlayView, toolbarFrame: CGRect, placement: ToolbarLayout.Placement) {
        guard let tool else {
            stylePanel.isHidden = true
            return
        }
        if stylePanel.superview !== view.controlsHost {
            view.controlsHost.addSubview(stylePanel)
        }
        stylePanel.configure(tool: tool, style: styles.style(for: tool))
        let frame = ToolbarLayout.stylePanelFrame(size: stylePanel.frame.size, toolbar: toolbarFrame,
                                                  placement: placement, bounds: view.bounds)
        stylePanel.setFrameOrigin(frame.origin)
        stylePanel.isHidden = false
    }

    func hideStylePanel() {
        stylePanel.isHidden = true
    }

    // MARK: 工具

    /// 选择工具；再次选择同一个工具则取消选中。
    func toggle(_ newTool: AnnotationTool) {
        finishTextEditing()
        tool = tool == newTool ? nil : newTool
        if tool == .mosaic, let style = currentStyle {
            // 提前生成像素化图，避免第一笔卡顿。
            prepareMosaicSource()
            _ = mosaicSource?.pixelated(blockSize: style.mosaicBlockSize)
        }
        onChange?()
    }

    // MARK: 鼠标

    /// 在选区内按下：开始画图形或开始输入文字。返回是否已处理。
    func mouseDown(at point: CGPoint, constrain: Bool) -> Bool {
        if textEditor.isEditing {
            // 点击别处结束输入（这次点击不再做别的）。
            finishTextEditing()
            return true
        }
        guard let tool, selection.contains(point), let style = currentStyle else { return false }

        if tool == .text {
            if let host = canvas.superview?.superview as? OverlayView {
                textEditor.begin(at: point, in: host.controlsHost, selection: selection, style: style)
            }
            return true
        }
        if tool == .mosaic { prepareMosaicSource() }

        var builder = ShapeBuilder(tool: tool, style: style, start: clamp(point), counterNumber: nextCounterNumber)
        builder.update(to: clamp(point), constrain: constrain)
        self.builder = builder
        canvas.inProgress = builder.makeShape()
        return true
    }

    func mouseDragged(to point: CGPoint, constrain: Bool) -> Bool {
        guard builder != nil else { return false }
        builder?.update(to: clamp(point), constrain: constrain)
        canvas.inProgress = builder?.makeShape()
        return true
    }

    func mouseUp(at point: CGPoint, constrain: Bool) -> Bool {
        guard var builder else { return false }
        builder.update(to: clamp(point), constrain: constrain)
        self.builder = nil
        canvas.inProgress = nil
        if let shape = builder.makeShape() {
            document.add(shape)
            syncCanvas()
            onChange?()
        }
        return true
    }

    /// 绘制中按下 / 松开 ⇧：立即更新约束。
    func constrainChanged(_ constrain: Bool) {
        guard var builder else { return }
        builder.update(to: builder.current, constrain: constrain)
        self.builder = builder
        canvas.inProgress = builder.makeShape()
    }

    // MARK: 撤销 / 重做

    func undo() {
        finishTextEditing()
        if document.undo() {
            syncCanvas()
            onChange?()
        }
    }

    func redo() {
        finishTextEditing()
        if document.redo() {
            syncCanvas()
            onChange?()
        }
    }

    // MARK: 文字

    func finishTextEditing() {
        if textEditor.isEditing { textEditor.finish() }
    }

    /// 输入中的 ⌘Z / ⇧⌘Z 交给输入框自己的撤销。
    func undoInTextField(redo: Bool) {
        guard let manager = textEditor.textView?.undoManager else { return }
        if redo { manager.redo() } else { manager.undo() }
    }

    // MARK: 导出

    /// 在屏幕本地 pt 坐标系里绘制所有标注（导出用）。
    func draw(in context: CGContext) {
        let environment = canvas.environment
        for shape in document.shapes {
            shape.draw(in: context, environment: environment)
        }
    }

    /// 下一个序号：现有序号的最大值 + 1（撤销后自动接上）。
    var nextCounterNumber: Int {
        (document.shapes.compactMap { ($0 as? CounterShape)?.number }.max() ?? 0) + 1
    }

    // MARK: 内部

    private func syncCanvas() {
        canvas.shapes = document.shapes
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, selection.minX), selection.maxX),
                y: min(max(point.y, selection.minY), selection.maxY))
    }

    private func prepareMosaicSource() {
        guard mosaicSource == nil, let display else { return }
        let source = MosaicSource(image: display.image, localBounds: display.geometry.localBounds,
                                  scale: display.geometry.scale)
        mosaicSource = source
        canvas.environment = AnnotationEnvironment(mosaic: source)
    }
}

extension AnnotationController: StylePanelDelegate {
    func stylePanel(_ panel: StylePanelView, didSelect size: SizeLevel) {
        guard let tool, var style = currentStyle else { return }
        style.size = size
        styles.setStyle(style, for: tool)
        if tool == .text { textEditor.update(style: style) }
        onChange?()
    }

    func stylePanel(_ panel: StylePanelView, didSelectColorAt index: Int) {
        guard let tool, var style = currentStyle else { return }
        style.colorIndex = index
        styles.setStyle(style, for: tool)
        if tool == .text { textEditor.update(style: style) }
        onChange?()
    }
}
