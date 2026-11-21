import AppKit

/// 协调多块屏幕的遮罩窗口：提前创建并复用，截图时铺满所有屏幕。
@MainActor
final class OverlayController {
    /// 遮罩关闭（完成或取消）后回调。
    var onDismiss: (() -> Void)?

    private(set) var isPresenting = false
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var capture: CaptureResult?
    private var previousApp: NSRunningApplication?

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
                let panel = OverlayPanel(frame: screen.frame)
                panel.overlayView.delegate = self
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

        let current = NSRunningApplication.current
        if let front = NSWorkspace.shared.frontmostApplication, front != current {
            previousApp = front
        } else {
            previousApp = nil
        }

        let mouse = NSEvent.mouseLocation
        var keyPanel: OverlayPanel?

        for display in capture.displays {
            let panel: OverlayPanel
            if let existing = panels[display.displayID] {
                panel = existing
            } else {
                panel = OverlayPanel(frame: display.geometry.frame)
                panel.overlayView.delegate = self
                panels[display.displayID] = panel
            }
            panel.setFrame(display.geometry.frame, display: false)
            panel.overlayView.show(image: display.image, scale: display.geometry.scale)
            panel.orderFrontRegardless()

            if display.geometry.frame.contains(mouse) || keyPanel == nil {
                keyPanel = panel
            }
        }

        NSApp.activate()
        keyPanel?.makeKeyAndOrderFront(nil)
        keyPanel?.makeFirstResponder(keyPanel?.overlayView)
        NSCursor.crosshair.set()

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

        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil

        onDismiss?()
    }
}

extension OverlayController: OverlayViewDelegate {
    func overlayViewDidPressEscape(_ view: OverlayView) {
        Log.overlay.notice("Esc：退出截图")
        dismiss()
    }

    func overlayView(_ view: OverlayView, rightMouseDownAt localPoint: CGPoint) {
        // M0 还没有选区：右键直接退出截图。
        Log.overlay.notice("右键：退出截图")
        dismiss()
    }
}
