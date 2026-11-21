import AppKit

/// 重启本 App（切换界面语言后用）。
///
/// 先退出、等进程结束后再打开：两个实例同时存在时，新实例注册不到全局快捷键（还被旧实例占着）。
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 路径和 PID 通过参数传入，不拼进脚本文本。
        process.arguments = ["-c", "while /bin/kill -0 \"$0\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$1\"",
                             String(pid), path]
        do {
            try process.run()
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        NSApp.terminate(nil)
    }
}
