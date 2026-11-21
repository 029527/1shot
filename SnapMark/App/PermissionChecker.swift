import AppKit
import CoreGraphics

/// 屏幕录制权限检查与引导。
enum PermissionChecker {
    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    /// 打开「系统设置 › 隐私与安全性 › 屏幕录制」。
    static func openScreenRecordingSettings() {
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(screenRecordingSettingsURL)
    }

    /// 弹窗说明原因，按钮直接打开「系统设置 › 隐私与安全性 › 屏幕录制」。
    @MainActor
    static func presentScreenRecordingAlert() {
        NSApp.activate()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要“屏幕录制”权限"
        alert.informativeText = """
        SnapMark 需要屏幕录制权限才能截取屏幕画面。截图只保存在你的电脑上，不会上传。

        请在「系统设置 › 隐私与安全性 › 屏幕录制」中打开 SnapMark 的开关。\
        如果打开后仍然无法截图，请退出并重新打开 SnapMark。
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            // 让 SnapMark 出现在「屏幕录制」列表里（首次调用时系统也可能弹出自己的提示）。
            openScreenRecordingSettings()
        }
    }
}
