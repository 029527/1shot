import AppKit
import KeyboardShortcuts

/// 菜单栏图标与菜单：截图、打开保存目录、设置…、退出。
@MainActor
final class StatusBarController: NSObject {
    struct Actions {
        var capture: () -> Void
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
            let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnapMark")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "SnapMark 截图"
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let capture = NSMenuItem(title: "截图", action: #selector(captureClicked), keyEquivalent: "")
        capture.target = self
        capture.setShortcut(for: .captureScreen)
        menu.addItem(capture)

        let history = NSMenuItem(title: "截图历史…", action: #selector(historyClicked), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        let open = NSMenuItem(title: "打开保存目录", action: #selector(openSaveDirectoryClicked), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 SnapMark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    @objc private func captureClicked() {
        // 等菜单完全收起后再截图。
        DispatchQueue.main.async { [actions] in actions.capture() }
    }

    @objc private func historyClicked() {
        actions.openHistory()
    }

    @objc private func openSaveDirectoryClicked() {
        actions.openSaveDirectory()
    }

    @objc private func settingsClicked() {
        actions.openSettings()
    }
}
