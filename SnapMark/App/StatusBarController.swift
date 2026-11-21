import AppKit
import KeyboardShortcuts

/// 菜单栏图标与菜单：截图、截图并复制、贴图、截图历史、打开保存目录、设置…、退出。
@MainActor
final class StatusBarController: NSObject {
    struct Actions {
        var capture: () -> Void
        var captureAndCopy: () -> Void
        var pinClipboard: () -> Void
        var openSaveDirectory: () -> Void
        var openHistory: () -> Void
        var openSettings: () -> Void
    }

    private let statusItem: NSStatusItem
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.accessibilityDescription = "SnapMark"
            button.image = image
            button.toolTip = String(localized: "SnapMark 截图")
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let capture = NSMenuItem(title: String(localized: "截图"), action: #selector(captureClicked), keyEquivalent: "")
        capture.target = self
        capture.setShortcut(for: .captureScreen)
        menu.addItem(capture)

        let quick = NSMenuItem(title: String(localized: "截图并复制"), action: #selector(captureAndCopyClicked), keyEquivalent: "")
        quick.target = self
        quick.setShortcut(for: .captureAndCopy)
        menu.addItem(quick)

        let pin = NSMenuItem(title: String(localized: "贴图（剪贴板）"), action: #selector(pinClicked), keyEquivalent: "")
        pin.target = self
        pin.setShortcut(for: .pinClipboard)
        menu.addItem(pin)

        menu.addItem(.separator())

        let history = NSMenuItem(title: String(localized: "截图历史…"), action: #selector(historyClicked), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        let open = NSMenuItem(title: String(localized: "打开保存目录"), action: #selector(openSaveDirectoryClicked), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "设置…"), action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "退出 SnapMark"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    @objc private func captureClicked() {
        // 等菜单完全收起后再截图。
        DispatchQueue.main.async { [actions] in actions.capture() }
    }

    @objc private func captureAndCopyClicked() {
        DispatchQueue.main.async { [actions] in actions.captureAndCopy() }
    }

    @objc private func pinClicked() {
        // 等菜单完全收起后再执行：菜单还在收起时激活 App 会失败，窗口会被压在其他 App 后面。
        DispatchQueue.main.async { [actions] in actions.pinClipboard() }
    }

    @objc private func historyClicked() {
        // 等菜单完全收起后再执行：菜单还在收起时激活 App 会失败，窗口会被压在其他 App 后面。
        DispatchQueue.main.async { [actions] in actions.openHistory() }
    }

    @objc private func openSaveDirectoryClicked() {
        // 等菜单完全收起后再执行：菜单还在收起时激活 App 会失败，窗口会被压在其他 App 后面。
        DispatchQueue.main.async { [actions] in actions.openSaveDirectory() }
    }

    @objc private func settingsClicked() {
        // 等菜单完全收起后再执行：菜单还在收起时激活 App 会失败，窗口会被压在其他 App 后面。
        DispatchQueue.main.async { [actions] in actions.openSettings() }
    }
}
