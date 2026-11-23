import AppKit
import KeyboardShortcuts

/// 菜单栏图标与菜单：截图、截图并复制、贴图、截图历史、打开保存目录、设置…、退出。
@MainActor
final class StatusBarController: NSObject {
    struct Actions {
        var capture: () -> Void
        var captureAndCopy: () -> Void
        var pinClipboard: () -> Void
        var checkForUpdates: () -> Void
        var openSaveDirectory: () -> Void
        var openHistory: () -> Void
        var openSettings: () -> Void
    }

    private let statusItem: NSStatusItem
    private let actions: Actions
    private var visibilityObservation: NSKeyValueObservation?

    init(actions: Actions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        // 允许按住 ⌘ 把图标拖出菜单栏移除。系统按 autosaveName 记住位置和是否隐藏，
        // 隐藏后再次打开 1shot 会恢复（见 AppDelegate.applicationShouldHandleReopen）。
        statusItem.autosaveName = "1shotStatusItem"
        statusItem.behavior = .removalAllowed
        visibilityObservation = statusItem.observe(\.isVisible, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue == true, change.newValue == false else { return }
            DispatchQueue.main.async { self?.iconWasRemoved() }
        }

        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.accessibilityDescription = "1shot"
            button.image = image
            button.toolTip = String(localized: "1shot 截图")
        }
        statusItem.menu = makeMenu()
    }

    /// 恢复被用户拖走的菜单栏图标。
    func showIcon() {
        guard !statusItem.isVisible else { return }
        statusItem.isVisible = true
        Log.app.notice("菜单栏图标已恢复")
    }

    /// 用户把图标拖出了菜单栏：告诉他们快捷键仍可用，以及怎么找回图标。
    private func iconWasRemoved() {
        Log.app.notice("用户移除了菜单栏图标")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "菜单栏图标已隐藏")
        alert.informativeText = String(localized: "1shot 仍在后台运行，截图快捷键照常可用。要恢复图标，在启动台或「应用程序」文件夹里再次打开 1shot。")
        alert.addButton(withTitle: String(localized: "好"))
        alert.addButton(withTitle: String(localized: "恢复图标"))
        if alert.runModal() == .alertSecondButtonReturn {
            showIcon()
        }
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

        let update = NSMenuItem(title: String(localized: "检查更新…"), action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        let open = NSMenuItem(title: String(localized: "打开保存目录"), action: #selector(openSaveDirectoryClicked), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: String(localized: "设置…"), action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "退出 1shot"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func checkForUpdatesClicked() {
        DispatchQueue.main.async { [actions] in actions.checkForUpdates() }
    }

    @objc private func settingsClicked() {
        // 等菜单完全收起后再执行：菜单还在收起时激活 App 会失败，窗口会被压在其他 App 后面。
        DispatchQueue.main.async { [actions] in actions.openSettings() }
    }
}
