import AppKit

/// 协调多块屏幕的遮罩窗口：提前创建并复用；截图时铺满所有屏幕，
/// 把输入事件交给 `SelectionModel`，再把结果画到每块屏幕上。
@MainActor
final class OverlayController {
    /// 截图会话结束（完成或取消，包括另存为面板关闭）后回调。
    var onDismiss: (() -> Void)?

    /// 遮罩正在显示。
    private(set) var isPresenting = false
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private(set) var capture: CaptureResult?
    var model: SelectionModel?
    private var previousApp: NSRunningApplication?

    /// 最近一次的光标位置（AppKit 全局坐标）。
    private(set) var mouse: CGPoint = .zero

    // 工具栏与标注
    let toolbar = ToolbarView(groups: [
        [.rectangle, .ellipse, .arrow, .pen, .text, .mosaic],
        [.undo, .redo],
        [.save, .cancel, .done],
    ])
    let annotations = AnnotationController()

    // 放大镜状态
    private var colorFormat: ColorFormat = .hex
    private var shiftTogglePending = false
    private var magnifierFeedback: String?
    private var feedbackResetWork: DispatchWorkItem?
    private var currentColor: PixelColor?

    init() {
        toolbar.delegate = self
        toolbar.isHidden = true
        annotations.onChange = { [weak self] in self?.annotationsChanged() }
    }

    // MARK: 窗口准备

    /// 为当前所有屏幕创建（或复用）遮罩窗口。启动时和显示器变化时调用。
    func preparePanels() {
        var alive = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            alive.insert(displayID)
            if let panel = panels[displayID] {
                panel.setFrame(screen.frame, display: false)
            } else {
                let panel = makePanel(frame: screen.frame)
                panels[displayID] = panel
                warmUp(panel)
            }
        }
        for (displayID, panel) in panels where !alive.contains(displayID) {
            panel.orderOut(nil)
            panel.close()
            panels[displayID] = nil
        }
        Log.overlay.notice("遮罩窗口已就绪：\(self.panels.count, privacy: .public) 块屏幕")
    }

    private func makePanel(frame: CGRect) -> OverlayPanel {
        let panel = OverlayPanel(frame: frame)
        panel.overlayView.delegate = self
        return panel
    }

    /// 让窗口服务器提前分配好窗口资源，首次截图更快。
    private func warmUp(_ panel: OverlayPanel) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    // MARK: 显示 / 关闭

    /// 显示定格遮罩。`stopwatch` 从按下快捷键开始计时。
    func present(_ capture: CaptureResult, stopwatch: Stopwatch) {
        let beforePresent = stopwatch.elapsedMs
        self.capture = capture
        isPresenting = true
        shiftTogglePending = false
        magnifierFeedback = nil

        let current = NSRunningApplication.current
        if let front = NSWorkspace.shared.frontmostApplication, front != current {
            previousApp = front
        } else {
            previousApp = nil
        }

        mouse = NSEvent.mouseLocation
        var model = SelectionModel(
            screens: capture.displays.map(\.geometry),
            windowFrames: capture.windows.selectableFrames(converter: capture.converter)
        )
        model.begin(at: mouse)
        self.model = model
        sessionDidBegin()

        var keyPanel: OverlayPanel?
        for display in capture.displays {
            let panel: OverlayPanel
            if let existing = panels[display.displayID] {
                panel = existing
            } else {
                panel = makePanel(frame: display.geometry.frame)
                panels[display.displayID] = panel
            }
            panel.setFrame(display.geometry.frame, display: false)
            panel.overlayView.show(image: display.image, scale: display.geometry.scale)
            if display.geometry.frame.contains(mouse) || keyPanel == nil {
                keyPanel = panel
            }
        }
        render()
        for display in capture.displays {
            panels[display.displayID]?.orderFrontRegardless()
        }

        NSApp.activate()
        keyPanel?.makeKeyAndOrderFront(nil)
        keyPanel?.makeFirstResponder(keyPanel?.overlayView)
        updateCursor()

        let ordered = stopwatch.elapsedMs
        let t = capture.timings
        Log.overlay.notice("""
        遮罩已显示：窗口列表 \(t.windowListMs, format: .fixed(precision: 1), privacy: .public) ms，\
        显示器信息 \(t.contentMs, format: .fixed(precision: 1), privacy: .public) ms，\
        截图 \(t.screenshotMs, format: .fixed(precision: 1), privacy: .public) ms（\(capture.displays.count, privacy: .public) 块屏），\
        铺遮罩 \(ordered - beforePresent, format: .fixed(precision: 1), privacy: .public) ms，\
        快捷键→遮罩 共 \(ordered, format: .fixed(precision: 1), privacy: .public) ms
        """)

        // 下一轮 runloop：CA 事务已提交给窗口服务器，作为「可见」时间点。
        DispatchQueue.main.async {
            Log.overlay.notice("快捷键→遮罩可见：\(stopwatch.elapsedMs, format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    /// 取消截图：关闭遮罩，把焦点还给之前的 App。
    func dismiss() {
        guard isPresenting else { return }
        hidePanels()
        endSession()
    }

    /// 隐藏遮罩并释放截图（会话可能还没结束，比如另存为面板还开着）。
    private func hidePanels() {
        guard isPresenting else { return }
        isPresenting = false
        sessionWillEnd()

        for panel in panels.values {
            panel.orderOut(nil)
            panel.overlayView.clear()
        }
        toolbar.isHidden = true
        toolbar.removeFromSuperview()
        capture = nil
        model = nil
        feedbackResetWork?.cancel()
        feedbackResetWork = nil
        NSCursor.arrow.set()
    }

    private func endSession() {
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
        onDismiss?()
    }

    // MARK: 完成 / 另存为

    /// 选区所在屏幕的截图与选区（本地坐标）。
    var activeSelection: (display: DisplayCapture, local: CGRect, global: CGRect)? {
        guard let capture, let model, let selection = model.selection,
              let index = model.selectionScreenIndex, capture.displays.indices.contains(index)
        else { return nil }
        let display = capture.displays[index]
        return (display, display.geometry.localRect(fromGlobal: selection), selection)
    }

    /// 合成最终图片（截图 + 所有标注）。
    private func composeImage() -> (image: CGImage, anchor: CGRect)? {
        guard let active = activeSelection else { return nil }
        let image = ImageExporter.compose(
            image: active.display.image,
            geometry: active.display.geometry,
            selection: active.local,
            drawOverlays: { [weak self] context in self?.drawAnnotations(in: context) }
        )
        guard let image else { return nil }
        return (image, active.global)
    }

    /// 完成：合成 → 剪贴板 / 保存 → 关闭遮罩 → 提示。
    func finish() {
        commitPendingEdits()
        guard let (image, anchor) = composeImage() else { return }
        model?.finish()
        Log.overlay.notice("完成：\(image.width, privacy: .public) × \(image.height, privacy: .public) px")
        hidePanels()
        endSession()
        OutputPipeline.deliver(image, anchor: anchor)
    }

    /// 另存为：关闭遮罩后弹出保存面板，同时复制到剪贴板。
    func saveAs() {
        commitPendingEdits()
        guard let (image, anchor) = composeImage() else { return }
        model?.finish()
        hidePanels()
        OutputPipeline.saveAs(image, anchor: anchor) { [weak self] in
            self?.endSession()
        }
    }

    // MARK: 绘制

    /// 根据模型状态更新所有屏幕上的选区装饰、工具栏和放大镜。
    func render() {
        guard let capture, let model else { return }

        let isHovering = model.state == .hovering
        let highlight = model.highlightedRect
        let activeIndex = isHovering ? model.hoverScreenIndex : model.selectionScreenIndex
        let mouseScreen = model.screenIndex(containing: mouse)
        let showMagnifier = isMagnifierVisible

        for (index, display) in capture.displays.enumerated() {
            guard let view = panels[display.displayID]?.overlayView else { continue }
            let geometry = display.geometry

            var chrome = OverlayChrome()
            if index == activeIndex, let highlight {
                let local = geometry.localRect(fromGlobal: highlight)
                chrome.highlight = local
                chrome.border = local
                chrome.borderWidth = isHovering ? 3 : 1.5
                if model.state == .selected, !model.isLocked {
                    chrome.handles = SelectionHandle.allCases.map { $0.point(in: local) }
                }
                let pixelSize = geometry.integralPixelRect(fromLocal: local).size
                chrome.sizeText = SizeLabel.text(for: pixelSize)
                chrome.sizeAnchor = local
            }
            view.update(chrome: chrome)

            if showMagnifier, index == mouseScreen {
                let local = geometry.localPoint(fromGlobal: mouse)
                view.updateMagnifier(magnifierContent(display: display, localCursor: local), cursor: local)
            } else {
                view.updateMagnifier(nil, cursor: .zero)
            }
        }

        layoutControls()
    }

    /// 工具栏（以及 M3 的属性条、标注画布）挂到选区所在屏幕，并按选区定位。
    private func layoutControls() {
        guard let model, let active = activeSelection,
              let view = panels[active.display.displayID]?.overlayView else {
            toolbar.isHidden = true
            annotations.hideStylePanel()
            return
        }

        annotations.attach(to: view, display: active.display, selection: active.local)

        let showToolbar = (model.state == .selected || model.state == .annotating)
            && !model.isAdjusting && model.state != .dragging
        if toolbar.superview !== view.controlsHost {
            view.controlsHost.addSubview(toolbar)
        }
        if showToolbar {
            let layout = ToolbarLayout.frame(size: toolbar.frame.size, selection: active.local, bounds: view.bounds)
            toolbar.setFrameOrigin(layout.frame.origin)
            toolbar.isHidden = false
            annotations.layoutStylePanel(in: view, toolbarFrame: layout.frame, placement: layout.placement)
        } else {
            toolbar.isHidden = true
            annotations.hideStylePanel()
        }
    }

    private func magnifierContent(display: DisplayCapture, localCursor: CGPoint) -> MagnifierView.Content? {
        let raw = display.geometry.pixelPoint(fromLocal: localCursor)
        let pixel = CGPoint(
            x: min(max(raw.x.rounded(.down), 0), CGFloat(display.image.width - 1)),
            y: min(max(raw.y.rounded(.down), 0), CGFloat(display.image.height - 1))
        )
        guard let sample = PixelSampler.sample(display.image, centerPixel: pixel) else { return nil }
        currentColor = sample.center
        return MagnifierView.Content(sample: sample, pixel: pixel, format: colorFormat, feedback: magnifierFeedback)
    }

    private var isMagnifierVisible: Bool {
        guard let model else { return false }
        return !model.isLocked && (model.state == .hovering || model.state == .dragging || model.isAdjusting)
    }

    /// 光标是否在工具栏 / 属性条上。
    private var isMouseOverControls: Bool {
        guard let host = toolbar.superview, let window = host.window else { return false }
        let local = host.convert(window.convertPoint(fromScreen: mouse), from: nil)
        return host.subviews.contains { !$0.isHidden && $0.frame.contains(local) }
    }

    func updateCursor() {
        guard let model else { return }
        if isMouseOverControls {
            NSCursor.arrow.set()
            return
        }
        if let custom = annotationCursor() {
            custom.set()
            return
        }
        cursor(for: model.cursorKind(at: mouse)).set()
    }

    private func cursor(for kind: SelectionModel.CursorKind) -> NSCursor {
        switch kind {
        case .crosshair: return .crosshair
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resize(let handle):
            if #available(macOS 15.0, *) {
                return NSCursor.frameResize(position: handle.frameResizePosition, directions: .all)
            }
            switch handle {
            case .left, .right: return .resizeLeftRight
            case .top, .bottom: return .resizeUpDown
            default: return .crosshair
            }
        }
    }

    // MARK: 放大镜动作

    private func copyColor() {
        guard isMagnifierVisible, let color = currentColor else { return }
        let value = color.string(in: colorFormat)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        Log.overlay.notice("已复制颜色 \(value, privacy: .public)")

        magnifierFeedback = "已复制 \(value)"
        feedbackResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.magnifierFeedback = nil
            self?.render()
        }
        feedbackResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        render()
    }

    // MARK: 标注

    private func sessionDidBegin() {
        annotations.reset()
        updateToolbarState()
    }

    private func sessionWillEnd() {
        annotations.reset()
    }

    private func commitPendingEdits() {
        annotations.finishTextEditing()
    }

    private func drawAnnotations(in context: CGContext) {
        annotations.draw(in: context)
    }

    /// 选中绘图工具时，选区内显示十字（文字工具为 I 形）。
    private func annotationCursor() -> NSCursor? {
        guard let tool = annotations.tool, let model, let selection = model.selection,
              selection.contains(mouse), model.handle(at: mouse) == nil else { return nil }
        return tool == .text ? .iBeam : .crosshair
    }

    /// 有了至少一个标注就锁定选区；撤销到没有标注时解锁。
    private func annotationsChanged() {
        guard model != nil else { return }
        if annotations.hasAnnotations {
            if model?.isLocked == false { model?.lock() }
        } else {
            model?.unlock()
        }
        updateToolbarState()
        render()
        updateCursor()
    }

    private func updateToolbarState() {
        toolbar.selectedTool = annotations.tool?.toolbarItem
        toolbar.setEnabled(annotations.document.canUndo, for: .undo)
        toolbar.setEnabled(annotations.document.canRedo, for: .redo)
    }

    private func localPoint(_ global: CGPoint) -> CGPoint? {
        activeSelection.map { $0.display.geometry.localPoint(fromGlobal: global) }
    }

    /// 绘图工具是否接管这次按下（选区内、不在控制点上）。
    private func annotationShouldHandleMouseDown(at point: CGPoint) -> Bool {
        guard annotations.tool != nil, let model, let selection = model.selection,
              model.state == .selected || model.state == .annotating else { return false }
        return selection.contains(point) && model.handle(at: point) == nil
    }
}

// MARK: - 事件

extension OverlayController: OverlayViewDelegate {
    func overlayView(_ view: OverlayView, mouseMovedTo point: CGPoint) {
        guard model != nil else { return }
        mouse = point
        model?.mouseMoved(to: point)
        render()
        updateCursor()
    }

    func overlayView(_ view: OverlayView, mouseDownAt point: CGPoint, clickCount: Int,
                     modifiers: NSEvent.ModifierFlags) {
        guard model != nil else { return }
        shiftTogglePending = false
        mouse = point

        // 正在输入文字：点击别处结束输入。
        if annotations.isEditingText {
            _ = annotations.mouseDown(at: localPoint(point) ?? point, constrain: false)
            render()
            updateCursor()
            return
        }

        // 双击选区（未选中绘图工具时）：完成。
        if clickCount == 2, annotations.tool == nil, let selection = model?.selection, selection.contains(point),
           model?.state == .selected || model?.state == .annotating {
            finish()
            return
        }

        if annotationShouldHandleMouseDown(at: point), let local = localPoint(point) {
            _ = annotations.mouseDown(at: local, constrain: modifiers.contains(.shift))
            render()
            updateCursor()
            return
        }

        model?.mouseDown(at: point)
        render()
        updateCursor()
    }

    func overlayView(_ view: OverlayView, mouseDraggedTo point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard model != nil else { return }
        mouse = point
        if annotations.isDrawing, let local = localPoint(point) {
            _ = annotations.mouseDragged(to: local, constrain: modifiers.contains(.shift))
            return
        }
        model?.mouseDragged(to: point)
        render()
        updateCursor()
    }

    func overlayView(_ view: OverlayView, mouseUpAt point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard model != nil else { return }
        mouse = point
        if annotations.isDrawing, let local = localPoint(point) {
            _ = annotations.mouseUp(at: local, constrain: modifiers.contains(.shift))
            updateCursor()
            return
        }
        model?.mouseUp(at: point)
        render()
        updateCursor()
    }

    func overlayView(_ view: OverlayView, rightMouseDownAt point: CGPoint) {
        guard model != nil else { return }
        mouse = point
        switch model?.rightClick(at: point) {
        case .cancel:
            Log.overlay.notice("右键：退出截图")
            dismiss()
        case .resetToHovering:
            Log.overlay.notice("右键：取消选区")
            render()
            updateCursor()
        case .ignored, .none:
            break
        }
    }

    func overlayView(_ view: OverlayView, keyDown event: NSEvent) -> Bool {
        guard model != nil else { return false }
        shiftTogglePending = false

        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if model?.selection != nil, model?.state == .selected || model?.state == .annotating {
                finish()
            }
            return true
        case KeyCode.leftArrow: model?.nudge(dx: -step, dy: 0)
        case KeyCode.rightArrow: model?.nudge(dx: step, dy: 0)
        case KeyCode.upArrow: model?.nudge(dx: 0, dy: step)
        case KeyCode.downArrow: model?.nudge(dx: 0, dy: -step)
        case KeyCode.c where event.modifierFlags.isDisjoint(with: [.command, .control, .option]):
            copyColor()
            return true
        default:
            // 工具快捷键：R / O / A / P / T / M
            if event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
               model?.state == .selected || model?.state == .annotating,
               let characters = event.charactersIgnoringModifiers, let tool = AnnotationTool(shortcut: characters) {
                annotations.toggle(tool)
                return true
            }
            return false
        }
        render()
        return true
    }

    func overlayView(_ view: OverlayView, flagsChanged event: NSEvent) {
        // 单独按一下 ⇧（中间没有按别的键）切换颜色格式；⇧ + 方向键不切换。
        let shiftDown = event.modifierFlags.contains(.shift)
        annotations.constrainChanged(shiftDown)
        let isShiftKey = event.keyCode == 56 || event.keyCode == 60
        guard isShiftKey else {
            shiftTogglePending = false
            return
        }
        if shiftDown {
            shiftTogglePending = true
        } else if shiftTogglePending {
            shiftTogglePending = false
            colorFormat.toggle()
            render()
        }
    }

    func overlayView(_ view: OverlayView, perform command: OverlayCommand) -> Bool {
        guard let model else { return false }
        let hasSelection = model.selection != nil && (model.state == .selected || model.state == .annotating)
        switch command {
        case .finish:
            // 正在输入文字时 ⌘C 按复制文字处理。
            if annotations.isEditingText { return false }
            if hasSelection { finish() }
        case .saveAs:
            if hasSelection { saveAs() }
        case .undo, .redo:
            if annotations.isEditingText {
                annotations.undoInTextField(redo: command == .redo)
            } else if command == .undo {
                annotations.undo()
            } else {
                annotations.redo()
            }
        }
        return true
    }

    func overlayViewDidPressEscape(_ view: OverlayView) {
        if annotations.isEditingText {
            annotations.finishTextEditing()
            return
        }
        Log.overlay.notice("Esc：退出截图")
        dismiss()
    }
}

// MARK: - 工具栏

extension OverlayController: ToolbarViewDelegate {
    func toolbar(_ toolbar: ToolbarView, didClick item: ToolbarItem) {
        switch item {
        case .save: saveAs()
        case .cancel: dismiss()
        case .done: finish()
        case .undo: annotations.undo()
        case .redo: annotations.redo()
        default:
            if let tool = AnnotationTool(item: item) { annotations.toggle(tool) }
        }
    }
}

extension SelectionHandle {
    @available(macOS 15.0, *)
    var frameResizePosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: return .topLeft
        case .top: return .top
        case .topRight: return .topRight
        case .right: return .right
        case .bottomRight: return .bottomRight
        case .bottom: return .bottom
        case .bottomLeft: return .bottomLeft
        case .left: return .left
        }
    }
}
