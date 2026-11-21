import AppKit
import KeyboardShortcuts
import SwiftUI

/// 设置界面（M0 先只放快捷键，其余选项在 M4 补齐）。
struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("截图快捷键：", name: .captureScreen)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

/// 用 AppKit 窗口承载 SwiftUI 设置界面。
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "SnapMark 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
