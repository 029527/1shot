import AppKit

/// 协调多块屏幕的遮罩窗口：提前创建并复用；截图时铺满所有屏幕，
/// 把输入事件交给 `SelectionModel`，再把结果画到每块屏幕上。
@MainActor
final class OverlayController {
    /// 遮罩关闭（完成或取消）后回调。
    var onDismiss: (() -> Void)?

    private(set) var isPresenting = false
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var capture: CaptureResult?
    private var model: SelectionModel?
    private var previousApp: NSRunningApplication?

    /// 最近一次的光标位置（AppKit 全局坐标）。
    private var mouse: CGPoint = .zero

    // 放大镜状态
    private var colorFormat: ColorFormat = .hex
    private var shiftTogglePending = false
    private var magnifierFeedback: String?
    private var feedbackResetWork: DispatchWorkItem?
    private var currentColor: PixelColor?

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

    /// 关闭遮罩，把焦点还给之前的 App。
    func dismiss() {
        guard isPresenting else { return }
        isPresenting = false

        for panel in panels.values {
            panel.orderOut(nil)
            panel.overlayView.clear()
        }
        capture = nil
        model = nil
        feedbackResetWork?.cancel()
        feedbackResetWork = nil
        NSCursor.arrow.set()

        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil

        onDismiss?()
    }

    // MARK: 绘制

    /// 根据模型状态更新所有屏幕上的选区装饰和放大镜。
    private func render() {
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

    private func updateCursor() {
        guard let model else { return }
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

    func overlayView(_ view: OverlayView, mouseDownAt point: CGPoint, clickCount: Int) {
        guard model != nil else { return }
        shiftTogglePending = false
        mouse = point
        model?.mouseDown(at: point)
        render()
        updateCursor()
    }

    func overlayView(_ view: OverlayView, mouseDraggedTo point: CGPoint) {
        guard model != nil else { return }
        mouse = point
        model?.mouseDragged(to: point)
        render()
        updateCursor()
    }

    func overlayView(_ view: OverlayView, mouseUpAt point: CGPoint) {
        guard model != nil else { return }
        mouse = point
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
        case KeyCode.leftArrow: model?.nudge(dx: -step, dy: 0)
        case KeyCode.rightArrow: model?.nudge(dx: step, dy: 0)
        case KeyCode.upArrow: model?.nudge(dx: 0, dy: step)
        case KeyCode.downArrow: model?.nudge(dx: 0, dy: -step)
        case KeyCode.c where event.modifierFlags.isDisjoint(with: [.command, .control, .option]):
            copyColor()
            return true
        default:
            return false
        }
        render()
        return true
    }

    func overlayView(_ view: OverlayView, flagsChanged event: NSEvent) {
        // 单独按一下 ⇧（中间没有按别的键）切换颜色格式；⇧ + 方向键不切换。
        let shiftDown = event.modifierFlags.contains(.shift)
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

    func overlayViewDidPressEscape(_ view: OverlayView) {
        Log.overlay.notice("Esc：退出截图")
        dismiss()
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
