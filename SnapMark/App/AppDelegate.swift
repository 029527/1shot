import AppKit
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureService = CaptureService()
    private let overlay = OverlayController()
    private let settingsWindow = SettingsWindowController()
    private let historyWindow = HistoryWindowController()
    private var statusBar: StatusBarController?

    /// 截图流程进行中（从按下快捷键到遮罩关闭）。
    private var isCapturing = false

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        Preferences.registerDefaults()
        NSApp.mainMenu = MainMenu.make()

        statusBar = StatusBarController(actions: .init(
            capture: { [weak self] in self?.startCapture() },
            openSaveDirectory: { [weak self] in self?.openSaveDirectory() },
            openHistory: { [weak self] in self?.historyWindow.show() },
            openSettings: { [weak self] in self?.settingsWindow.show() }
        ))

        KeyboardShortcuts.onKeyDown(for: .captureScreen) { [weak self] in
            self?.startCapture()
        }

        overlay.onDismiss = { [weak self] in
            self?.isCapturing = false
        }
        overlay.preparePanels()

        // 有权限时才预取，避免一启动就触发系统授权弹窗。
        if PermissionChecker.hasScreenRecordingAccess {
            captureService.refreshContent()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        Log.app.notice("SnapMark 已启动，屏幕录制权限：\(PermissionChecker.hasScreenRecordingAccess, privacy: .public)")
    }

    // MARK: 截图

    func startCapture() {
        guard !isCapturing else {
            Log.capture.notice("截图进行中，忽略快捷键")
            return
        }

        let stopwatch = Stopwatch()

        guard PermissionChecker.hasScreenRecordingAccess else {
            PermissionChecker.presentScreenRecordingAlert()
            return
        }

        isCapturing = true
        Task { @MainActor in
            do {
                let result = try await captureService.captureAllScreens()
                // 等待截图期间用户可能已经插拔了显示器。
                guard isCapturing else { return }
                overlay.present(result, stopwatch: stopwatch)
            } catch {
                isCapturing = false
                Log.capture.error("截图失败：\(error.localizedDescription, privacy: .public)")
                presentError(error)
            }
        }
    }

    @objc private func screenParametersChanged() {
        Log.app.notice("显示器配置变化，刷新缓存")
        if overlay.isPresenting {
            overlay.dismiss()
        }
        overlay.preparePanels()
        if PermissionChecker.hasScreenRecordingAccess {
            captureService.refreshContent()
        }
    }

    // MARK: 菜单动作

    private func openSaveDirectory() {
        do {
            let url = try Preferences.ensureSaveDirectory()
            NSWorkspace.shared.open(url)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
