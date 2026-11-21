import AppKit

/// 贴图的编辑模式：按空格在贴图旁边显示 / 隐藏截图工具栏，可以继续标注、复制、保存、识别文字。
///
/// 工具栏和属性条放在一个跟随贴图的子窗口里（贴图窗口本身只有图片大小）。
/// 标注画在贴图视图上，工具栏收起后仍然保留；复制、保存时与原图合成。
@MainActor
final class PinEditor: NSObject {
    static let toolbarGroups: [[ToolbarItem]] = [
        [.rectangle, .ellipse, .arrow, .pen, .highlighter, .text, .counter],
        [.mosaic, .spotlight, .watermark],
        [.undo, .redo],
        [.ocr],
        [.save, .cancel, .done],
    ]

    private weak var pin: PinWindow?
    let annotations = AnnotationController()
    let toolbar = ToolbarView(groups: PinEditor.toolbarGroups)

    private var panel: NSPanel?
    private let container = PassthroughView()
    private(set) var isToolbarVisible = false
    private var moveObserver: NSObjectProtocol?

    init(pin: PinWindow) {
        self.pin = pin
        super.init()
        toolbar.delegate = self
        toolbar.setToolTip(String(localized: "关闭贴图"), for: .cancel)
        toolbar.setToolTip(String(localized: "复制并收起工具栏（Enter）"), for: .done)
        toolbar.setToolTip(String(localized: "另存为（⌘S）"), for: .save)
        annotations.onChange = { [weak self] in self?.annotationsChanged() }
        attach()
    }

    // MARK: 显示 / 隐藏

    func toggleToolbar() {
        isToolbarVisible ? hideToolbar() : showToolbar()
    }

    func showToolbar() {
        guard let pin, !isToolbarVisible else { return }
        // 编辑时按原始大小，标注坐标与图片一一对应。
        pin.setZoom(1)
        attach()
        isToolbarVisible = true

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.parent == nil { pin.addChildWindow(panel, ordered: .above) }
        layout()
        panel.orderFront(nil)
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: pin, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        updateToolbarState()
        pin.pinView.updateCursor()
        Log.app.notice("贴图：显示工具栏")
    }

    func hideToolbar() {
        guard isToolbarVisible else { return }
        annotations.finishTextEditing()
        if let tool = annotations.tool { annotations.toggle(tool) }
        annotations.deselectShape()
        isToolbarVisible = false
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        if let panel {
            pin?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        pin?.pinView.updateCursor()
    }

    /// 贴图关闭时调用。
    func teardown() {
        hideToolbar()
        panel?.close()
        panel = nil
        annotations.reset()
    }

    // MARK: 合成

    var hasAnnotations: Bool { annotations.hasAnnotations }

    /// 原图 + 标注，按原图像素尺寸输出。没有标注时直接返回原图。
    func composedImage() -> CGImage? {
        guard let pin else { return nil }
        annotations.finishTextEditing()
        guard annotations.hasAnnotations else { return pin.image }
        return Self.compose(image: pin.image, size: pin.originalSize) { [annotations] context in
            annotations.draw(in: context)
        }
    }

    /// 在 `size`（pt）坐标系里先画原图、再画 `overlays`，输出原图像素尺寸。
    nonisolated static func compose(image: CGImage, size: CGSize, overlays: (CGContext) -> Void) -> CGImage? {
        guard size.width > 0, size.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: CGFloat(image.width) / size.width, y: CGFloat(image.height) / size.height)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        overlays(context)
        return context.makeImage()
    }

    // MARK: 鼠标（贴图视图本地坐标，与原始大小一致）

    /// 返回 true 表示由标注处理（不拖动窗口）。
    func mouseDown(at point: CGPoint, clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard isToolbarVisible else { return false }
        if annotations.isEditingText {
            annotations.finishTextEditing()
            return true
        }
        if clickCount == 2, annotations.tool == nil {
            _ = annotations.reeditText(at: point)
            return true
        }
        if annotations.tool != nil {
            return annotations.mouseDown(at: point, constrain: modifiers.contains(.shift))
        }
        return annotations.beginEdit(at: point)
    }

    func mouseDragged(to point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if annotations.isDrawing {
            _ = annotations.mouseDragged(to: point, constrain: modifiers.contains(.shift))
        } else if annotations.isEditingShape {
            _ = annotations.editDragged(to: point, constrain: modifiers.contains(.shift))
        }
    }

    func mouseUp(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if annotations.isDrawing {
            _ = annotations.mouseUp(at: point, constrain: modifiers.contains(.shift))
        } else if annotations.isEditingShape {
            _ = annotations.editEnded()
        }
    }

    func cursor(at point: CGPoint) -> NSCursor {
        guard isToolbarVisible else { return .openHand }
        if annotations.tool == .text { return .iBeam }
        if annotations.tool != nil { return .crosshair }
        return annotations.editCursor(at: point) ?? .openHand
    }

    // MARK: 键盘

    /// 工具栏显示时的按键。返回是否已处理。
    func keyDown(_ event: NSEvent) -> Bool {
        guard isToolbarVisible else { return false }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        if annotations.selectedShape != nil {
            switch event.keyCode {
            case KeyCode.delete, KeyCode.forwardDelete: return annotations.deleteSelectedShape()
            case KeyCode.leftArrow: return annotations.nudgeSelectedShape(dx: -step, dy: 0)
            case KeyCode.rightArrow: return annotations.nudgeSelectedShape(dx: step, dy: 0)
            case KeyCode.upArrow: return annotations.nudgeSelectedShape(dx: 0, dy: step)
            case KeyCode.downArrow: return annotations.nudgeSelectedShape(dx: 0, dy: -step)
            default: break
            }
        }
        switch event.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            copyAndHide()
            return true
        case KeyCode.escape:
            escape()
            return true
        default:
            if event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
               let characters = event.charactersIgnoringModifiers, let tool = AnnotationTool(shortcut: characters) {
                annotations.toggle(tool)
                return true
            }
            return false
        }
    }

    /// Esc：结束输入 → 取消工具 → 取消选中图形 → 收起工具栏。
    func escape() {
        if annotations.isEditingText {
            annotations.finishTextEditing()
        } else if let tool = annotations.tool {
            annotations.toggle(tool)
        } else if annotations.selectedShape != nil {
            annotations.deselectShape()
        } else {
            hideToolbar()
        }
    }

    func undo(redo: Bool) {
        if annotations.isEditingText {
            annotations.undoInTextField(redo: redo)
        } else if redo {
            annotations.redo()
        } else {
            annotations.undo()
        }
    }

    func constrainChanged(_ constrain: Bool) {
        annotations.constrainChanged(constrain)
    }

    // MARK: 内部

    private func attach() {
        guard let pin else { return }
        let size = pin.originalSize
        annotations.attach(to: pin.pinView, source: AnnotationSource(
            id: AnyHashable(ObjectIdentifier(pin)), image: pin.image,
            bounds: CGRect(origin: .zero, size: size),
            scale: CGFloat(pin.image.width) / max(size.width, 1)
        ), selection: CGRect(origin: .zero, size: size))
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        container.frame = .zero
        container.addSubview(toolbar)
        panel.contentView = container
        return panel
    }

    /// 工具栏放在贴图下方右对齐；下方放不下放上方，再放不下放贴图内部。属性条在工具栏外侧。
    private func layout() {
        guard isToolbarVisible, let pin, let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(pin.frame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? pin.frame
        let (toolbarFrame, placement) = ToolbarLayout.frame(size: toolbar.frame.size, selection: pin.frame,
                                                            bounds: screen)
        var union = toolbarFrame
        var styleFrame: CGRect?
        if annotations.configureStylePanel(in: container) {
            let frame = ToolbarLayout.stylePanelFrame(size: annotations.stylePanel.frame.size, toolbar: toolbarFrame,
                                                      placement: placement, bounds: screen)
            styleFrame = frame
            union = union.union(frame)
        }
        // 留出阴影的位置。
        let margin: CGFloat = 12
        let panelFrame = union.insetBy(dx: -margin, dy: -margin)
        panel.setFrame(panelFrame, display: false)
        container.frame = CGRect(origin: .zero, size: panelFrame.size)
        toolbar.setFrameOrigin(CGPoint(x: toolbarFrame.minX - panelFrame.minX, y: toolbarFrame.minY - panelFrame.minY))
        if let styleFrame {
            annotations.stylePanel.setFrameOrigin(CGPoint(x: styleFrame.minX - panelFrame.minX,
                                                          y: styleFrame.minY - panelFrame.minY))
        }
    }

    private func annotationsChanged() {
        updateToolbarState()
        layout()
        pin?.pinView.updateCursor()
    }

    private func updateToolbarState() {
        toolbar.selectedTool = annotations.tool?.toolbarItem
        toolbar.setEnabled(annotations.document.canUndo, for: .undo)
        toolbar.setEnabled(annotations.document.canRedo, for: .redo)
    }

    private func copyAndHide() {
        pin?.copyImage(nil)
        hideToolbar()
    }

    private func recognizeText() {
        guard let pin else { return }
        annotations.finishTextEditing()
        let image = pin.image
        let anchor = pin.frame
        let stopwatch = Stopwatch()
        Task { @MainActor in
            do {
                let lines = try await TextRecognizer.recognize(image)
                let text = TextRecognizer.layout(lines)
                Log.app.notice("贴图文字识别：\(lines.count, privacy: .public) 行，\(stopwatch.elapsedMs, format: .fixed(precision: 0), privacy: .public) ms")
                guard !text.isEmpty else {
                    Toast.shared.show(String(localized: "没有识别到文字"), near: anchor)
                    return
                }
                OCRResultWindowController.copy(text)
                OCRResultWindowController.shared.show(text: text, near: anchor)
            } catch {
                Toast.shared.show(String(localized: "文字识别失败：\(error.localizedDescription)"), near: anchor)
            }
        }
    }
}

extension PinEditor: ToolbarViewDelegate {
    func toolbar(_ toolbar: ToolbarView, didClick item: ToolbarItem) {
        switch item {
        case .undo: undo(redo: false)
        case .redo: undo(redo: true)
        case .ocr: recognizeText()
        case .save: pin?.saveImage(nil)
        case .cancel: pin?.close()
        case .done: copyAndHide()
        default:
            if let tool = AnnotationTool(item: item) { annotations.toggle(tool) }
        }
        // 点工具栏不应让贴图失去焦点（键盘快捷键继续作用于贴图）。
        pin?.makeKey()
    }
}

/// 无边框面板默认不能成为 key；工具栏里的水印输入框需要键盘焦点。
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
