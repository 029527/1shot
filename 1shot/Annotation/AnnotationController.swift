import AppKit

/// 一次截图里的标注：当前工具与样式、标注文档、绘制中的图形、文字输入、属性条。
/// 所有坐标为选区所在屏幕的本地 pt 坐标。
/// 能承载标注的视图：标注画布挂在 `annotationHost`，文字输入框、属性条挂在 `controlsHost`。
@MainActor
protocol AnnotationHost: NSView {
    var annotationHost: PassthroughView { get }
    var controlsHost: PassthroughView { get }
}

/// 标注底下的原图：`bounds` 为原图铺满的范围（宿主本地 pt），`scale` 为像素 / pt。
struct AnnotationSource {
    let id: AnyHashable
    let image: CGImage
    let bounds: CGRect
    let scale: CGFloat
}

@MainActor
final class AnnotationController {
    /// 标注增删、撤销重做、工具或样式变化后回调（控制器据此锁定选区、刷新工具栏）。
    var onChange: (() -> Void)?

    private(set) var tool: AnnotationTool?
    private(set) var document = AnnotationDocument()
    private var builder: ShapeBuilder?
    private var styles: StyleStore

    let canvas = AnnotationCanvasView(frame: .zero)
    let stylePanel = StylePanelView(frame: .zero)
    private let textEditor = TextEditingController()

    private var selection: CGRect = .zero
    private var source: AnnotationSource?
    private var mosaicSource: MosaicSource?

    // 选中已有图形再编辑
    private(set) var selectedShapeID: UUID?
    private var editDrag: EditDrag?
    /// 重新编辑文字前的快照（结束输入时合并成一步撤销）。
    private var textEditSnapshot: [any AnnotationShape]?
    /// 选中水印工具时的快照：期间的修改（输入、调不透明度、换颜色）合并成一步撤销。
    private var watermarkSnapshot: [any AnnotationShape]?

    private struct EditDrag {
        var start: CGPoint
        var original: any AnnotationShape
        /// nil 表示整体移动。
        var handle: Int?
        var snapshot: [any AnnotationShape]
        var changed = false
    }

    var selectedShape: (any AnnotationShape)? {
        selectedShapeID.flatMap { document.shape(id: $0) }
    }

    var isEditingShape: Bool { editDrag != nil }

    /// `styles`：测试时传入独立的 UserDefaults，避免改到真实设置。
    init(styles: StyleStore = StyleStore()) {
        self.styles = styles
        stylePanel.delegate = self
        stylePanel.isHidden = true
        textEditor.onFinish = { [weak self] shape in self?.textFinished(shape) }
    }

    /// reset() 时丢弃正在输入的文字。
    private var isResetting = false

    private func textFinished(_ shape: TextShape?) {
        guard !isResetting else { return }
        if let snapshot = textEditSnapshot {
            // 重新编辑：替换原文字（清空则删除），合并成一步撤销。
            textEditSnapshot = nil
            if let shape { document.appendWithoutUndo(shape) }
            document.commitEdit(from: snapshot)
        } else if let shape {
            document.add(shape)
        }
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
        selectedShapeID = nil
        editDrag = nil
        textEditSnapshot = nil
        watermarkSnapshot = nil
        document.removeAll()
        mosaicSource = nil
        source = nil
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
        attach(to: view, source: AnnotationSource(
            id: AnyHashable(display.displayID), image: display.image,
            bounds: display.geometry.localBounds, scale: display.geometry.scale
        ), selection: selection)
    }

    /// 把画布挂到任意宿主（遮罩、贴图窗口），`source` 是标注底下的原图（马赛克取样用）。
    func attach(to view: AnnotationHost, source: AnnotationSource, selection: CGRect) {
        let host = view.annotationHost
        if canvas.superview !== host {
            canvas.frame = host.bounds
            canvas.autoresizingMask = [.width, .height]
            host.addSubview(canvas)
        }
        if self.source?.id != source.id {
            self.source = source
            mosaicSource = nil
            canvas.environment = AnnotationEnvironment()
        }
        self.selection = selection
        canvas.selection = selection
        if let watermark = currentWatermark, watermark.area != selection {
            var updated = watermark
            updated.area = selection
            document.updateWithoutUndo(id: watermark.id, with: updated)
            syncCanvas()
        }
    }

    /// 属性条放在工具栏旁边；没有选中工具时隐藏。
    /// 选中已有图形时显示该图形的样式，修改作用于该图形。
    func layoutStylePanel(in view: OverlayView, toolbarFrame: CGRect, placement: ToolbarLayout.Placement) {
        guard configureStylePanel(in: view.controlsHost) else { return }
        let frame = ToolbarLayout.stylePanelFrame(size: stylePanel.frame.size, toolbar: toolbarFrame,
                                                  placement: placement, bounds: view.bounds)
        stylePanel.setFrameOrigin(frame.origin)
    }

    /// 把属性条放进 `host` 并按当前工具 / 选中图形配置。返回是否需要显示（位置由调用方决定）。
    @discardableResult
    func configureStylePanel(in host: NSView) -> Bool {
        let panelTool: AnnotationTool
        let panelStyle: ToolStyle
        if let shape = selectedShape {
            panelTool = shape.tool
            panelStyle = shape.style
        } else if let tool {
            panelTool = tool
            panelStyle = styles.style(for: tool)
        } else {
            stylePanel.isHidden = true
            return false
        }
        if stylePanel.superview !== host {
            host.addSubview(stylePanel)
        }
        stylePanel.configure(tool: panelTool, style: panelStyle)
        stylePanel.isHidden = false
        return true
    }

    func hideStylePanel() {
        stylePanel.isHidden = true
    }

    // MARK: 工具

    /// 选择工具；再次选择同一个工具则取消选中。
    func toggle(_ newTool: AnnotationTool) {
        finishTextEditing()
        selectedShapeID = nil
        endWatermarkEditing()
        syncCanvas()
        tool = tool == newTool ? nil : newTool
        if tool == .mosaic, let style = currentStyle {
            // 提前生成像素化 / 模糊图，避免第一笔卡顿。
            prepareMosaicSource()
            warmUpMosaic(style)
        }
        if tool == .watermark {
            watermarkSnapshot = document.snapshot
            if let existing = currentWatermark {
                // 已有水印：属性条显示它的文字、不透明度、颜色，直接修改它。
                var style = styles.style(for: .watermark)
                style.colorIndex = existing.style.colorIndex
                style.options.text = existing.text
                style.options.amount = existing.opacity
                styles.setStyle(style, for: .watermark)
            } else if let style = currentStyle {
                applyWatermark(style)
            }
        }
        onChange?()
    }

    /// 选着某个工具时可以点选的已有标注：同一种工具画的（最上层优先）。
    /// 马赛克画笔例外：在已有马赛克上继续涂抹很常见，不拦截。
    func editableShape(at point: CGPoint, for tool: AnnotationTool) -> (any AnnotationShape)? {
        if tool == .mosaic, currentStyle?.options.mosaicMode == .brush { return nil }
        return document.shapes.last { shape in
            guard shape.tool == tool, shape.hitTest(point, tolerance: 4) else { return false }
            if tool == .mosaic, let mosaic = shape as? MosaicShape, case .stroke = mosaic.region { return false }
            return true
        }
    }

    #if DEBUG
    /// 测试用：直接放入一个图形（记撤销）。
    func debugAppend(_ shape: any AnnotationShape) {
        document.add(shape)
        syncCanvas()
    }
    #endif

    // MARK: 水印（整张图一个）

    var currentWatermark: WatermarkShape? {
        document.shapes.lazy.compactMap { $0 as? WatermarkShape }.first
    }

    /// 按样式更新水印：文字为空时去掉。不记撤销（结束时合并）。
    private func applyWatermark(_ style: ToolStyle) {
        let text = String(style.options.text.prefix(WatermarkShape.maxLength))
        if let existing = currentWatermark {
            if text.isEmpty {
                document.removeWithoutUndo(id: existing.id)
            } else {
                document.updateWithoutUndo(id: existing.id, with: existing.restyled(style))
            }
        } else if !text.isEmpty {
            document.appendWithoutUndo(WatermarkShape(text: text, color: style.color, opacity: style.options.amount,
                                                      area: selection))
        }
        syncCanvas()
    }

    /// 离开水印工具：有改动就记一步撤销。
    private func endWatermarkEditing() {
        guard let snapshot = watermarkSnapshot else { return }
        watermarkSnapshot = nil
        let before = snapshot.compactMap { $0 as? WatermarkShape }.first
        let after = currentWatermark
        let changed = before?.text != after?.text || before?.color != after?.color
            || before?.opacity != after?.opacity || (before == nil) != (after == nil)
        if changed { document.commitEdit(from: snapshot) }
    }

    private func warmUpMosaic(_ style: ToolStyle) {
        if style.options.mosaicEffect == .pixelate {
            _ = mosaicSource?.pixelated(blockSize: style.mosaicBlockSize)
        } else {
            _ = mosaicSource?.blurred(radius: MosaicShape.blurRadius(amount: style.options.amount))
        }
    }

    /// 属性条里的文字输入框正在输入（快捷键交给输入框）。
    var isTypingInStylePanel: Bool { stylePanel.isEditingText }

    // MARK: 鼠标

    /// 在选区内按下：开始画图形或开始输入文字。返回是否已处理。
    func mouseDown(at point: CGPoint, constrain: Bool) -> Bool {
        if textEditor.isEditing {
            // 点击别处结束输入（这次点击不再做别的）。
            finishTextEditing()
            return true
        }
        guard let tool, selection.contains(point), let style = currentStyle else { return false }
        // 水印作用于整张图，点击画布不做事（也不让遮罩开始重新框选）。
        if tool.isDocumentLevel { return true }

        // 选中的标注的控制点：拖动改大小。
        if let shape = selectedShape, let index = handleIndex(of: shape, at: point) {
            editDrag = EditDrag(start: point, original: shape, handle: index, snapshot: document.snapshot)
            return true
        }
        // 点中同类的已有标注：选中它再编辑，而不是再画一个。
        if let hit = editableShape(at: point, for: tool) {
            if tool == .text, hit is TextShape {
                return reeditText(at: point)
            }
            selectedShapeID = hit.id
            editDrag = EditDrag(start: point, original: hit, handle: nil, snapshot: document.snapshot)
            syncCanvas()
            onChange?()
            return true
        }
        // 点在空白处：取消选中，开始画新的。
        if selectedShapeID != nil {
            selectedShapeID = nil
            syncCanvas()
            onChange?()
        }

        if tool == .text {
            if let host = canvas.superview?.superview as? AnnotationHost {
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

    // MARK: 选中已有图形再编辑（没有选中绘图工具时）

    /// 按下：点在已选图形的控制点上 → 拖控制点；点在某个图形上 → 选中并开始移动；
    /// 点在空白处 → 取消选中并返回 false（交给选区处理）。
    func beginEdit(at point: CGPoint) -> Bool {
        guard tool == nil else { return false }
        if let shape = selectedShape, let index = handleIndex(of: shape, at: point) {
            editDrag = EditDrag(start: point, original: shape, handle: index, snapshot: document.snapshot)
            return true
        }
        if let hit = document.shape(at: point, tolerance: 4) {
            selectedShapeID = hit.id
            editDrag = EditDrag(start: point, original: hit, handle: nil, snapshot: document.snapshot)
            syncCanvas()
            onChange?()
            return true
        }
        if selectedShapeID != nil {
            deselectShape()
        }
        return false
    }

    func editDragged(to point: CGPoint, constrain: Bool) -> Bool {
        guard var drag = editDrag else { return false }
        let p = clamp(point)
        let updated: any AnnotationShape
        if let handle = drag.handle {
            updated = drag.original.dragging(handle: handle, to: p, constrain: constrain)
        } else {
            updated = drag.original.moved(by: p.x - drag.start.x, p.y - drag.start.y)
        }
        document.updateWithoutUndo(id: drag.original.id, with: updated)
        drag.changed = true
        editDrag = drag
        syncCanvas()
        return true
    }

    func editEnded() -> Bool {
        guard let drag = editDrag else { return false }
        editDrag = nil
        if drag.changed {
            document.commitEdit(from: drag.snapshot)
            onChange?()
        }
        return true
    }

    func deselectShape() {
        guard selectedShapeID != nil else { return }
        selectedShapeID = nil
        syncCanvas()
        onChange?()
    }

    /// Delete / Backspace：删除选中的图形。
    func deleteSelectedShape() -> Bool {
        guard let id = selectedShape?.id else { return false }
        document.remove(id: id)
        selectedShapeID = nil
        syncCanvas()
        onChange?()
        return true
    }

    /// 方向键：移动选中的图形。
    func nudgeSelectedShape(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let shape = selectedShape else { return false }
        document.replace(id: shape.id, with: shape.moved(by: dx, dy))
        syncCanvas()
        onChange?()
        return true
    }

    /// 双击文字：重新编辑。
    func reeditText(at point: CGPoint) -> Bool {
        guard tool == nil || tool == .text, let text = document.shape(at: point, tolerance: 4) as? TextShape,
              let host = canvas.superview?.superview as? AnnotationHost else { return false }
        editDrag = nil
        textEditSnapshot = document.snapshot
        document.removeWithoutUndo(id: text.id)
        selectedShapeID = nil
        syncCanvas()
        textEditor.begin(topLeft: text.topLeft, text: text.text, in: host.controlsHost, selection: selection,
                         style: text.style)
        onChange?()
        return true
    }

    /// 没有选中工具时的光标：控制点 → 十字，图形上 → 手形。
    func editCursor(at point: CGPoint) -> NSCursor? {
        if let drag = editDrag { return drag.handle == nil ? .closedHand : .crosshair }
        if let shape = selectedShape, handleIndex(of: shape, at: point) != nil { return .crosshair }
        if let tool {
            // 选着工具：悬停在同类标注上提示可以选中（文字显示 I 形光标）。
            guard let hit = editableShape(at: point, for: tool) else { return nil }
            return hit is TextShape ? .iBeam : .openHand
        }
        if document.shape(at: point, tolerance: 4) != nil { return .openHand }
        return nil
    }

    private func handleIndex(of shape: any AnnotationShape, at point: CGPoint) -> Int? {
        shape.editHandles.indices.first { hypot(shape.editHandles[$0].x - point.x, shape.editHandles[$0].y - point.y) <= 7 }
    }

    // MARK: 撤销 / 重做

    func undo() {
        finishTextEditing()
        endWatermarkEditing()
        if document.undo() {
            syncCanvas()
            onChange?()
        }
        // 仍在水印工具里：从撤销后的状态重新开始记录。
        if tool == .watermark { watermarkSnapshot = document.snapshot }
    }

    func redo() {
        finishTextEditing()
        endWatermarkEditing()
        if document.redo() {
            syncCanvas()
            onChange?()
        }
        // 仍在水印工具里：从撤销后的状态重新开始记录。
        if tool == .watermark { watermarkSnapshot = document.snapshot }
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
        var environment = canvas.environment
        environment.bounds = selection
        AnnotationRenderer.draw(document.shapes, in: context, environment: environment)
    }

    /// 下一个序号：现有序号的最大值 + 1（撤销后自动接上）。
    var nextCounterNumber: Int {
        (document.shapes.compactMap { ($0 as? CounterShape)?.number }.max() ?? 0) + 1
    }

    // MARK: 内部

    private func syncCanvas() {
        canvas.shapes = document.shapes
        if let id = selectedShapeID, document.shape(id: id) == nil {
            selectedShapeID = nil
        }
        let selected = selectedShape
        canvas.selectedOutline = selected?.bounds
        canvas.editHandles = selected?.editHandles ?? []
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, selection.minX), selection.maxX),
                y: min(max(point.y, selection.minY), selection.maxY))
    }

    private func prepareMosaicSource() {
        guard mosaicSource == nil, let source else { return }
        let mosaic = MosaicSource(image: source.image, localBounds: source.bounds, scale: source.scale)
        mosaicSource = mosaic
        canvas.environment = AnnotationEnvironment(mosaic: mosaic)
    }
}

extension AnnotationController: StylePanelDelegate {
    func stylePanel(_ panel: StylePanelView, didSelect size: SizeLevel) {
        if let shape = selectedShape {
            var style = shape.style
            style.size = size
            restyleSelected(style)
            return
        }
        guard let tool, var style = currentStyle else { return }
        style.size = size
        styles.setStyle(style, for: tool)
        if tool == .text { textEditor.update(style: style) }
        onChange?()
    }

    func stylePanel(_ panel: StylePanelView, didSelectColorAt index: Int) {
        if let shape = selectedShape {
            var style = shape.style
            style.colorIndex = index
            restyleSelected(style)
            return
        }
        guard let tool, var style = currentStyle else { return }
        style.colorIndex = index
        styles.setStyle(style, for: tool)
        if tool == .text { textEditor.update(style: style) }
        if tool == .watermark { applyWatermark(style) }
        onChange?()
    }

    func stylePanel(_ panel: StylePanelView, didChange options: ToolOptions) {
        if let shape = selectedShape {
            var style = shape.style
            let size = style.size
            style.options = options
            style.size = size
            restyleSelected(style)
            return
        }
        guard let tool, var style = currentStyle else { return }
        style.options = options
        styles.setStyle(style, for: tool)
        if tool == .watermark { applyWatermark(style) }
        if tool == .mosaic { warmUpMosaic(style) }
        onChange?()
    }

    private func restyleSelected(_ style: ToolStyle) {
        guard let shape = selectedShape else { return }
        let updated = shape.restyled(style)
        document.replace(id: shape.id, with: updated)
        // 选着同一种工具：之后画的也用这个样式。
        if let tool, tool == shape.tool {
            var toolStyle = styles.style(for: tool)
            toolStyle.size = style.size
            toolStyle.colorIndex = style.colorIndex
            let text = toolStyle.options.text
            toolStyle.options = style.options
            toolStyle.options.text = text
            styles.setStyle(toolStyle, for: tool)
        }
        syncCanvas()
        onChange?()
    }
}
