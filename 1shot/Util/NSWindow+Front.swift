import AppKit

extension NSWindow {
    /// 把窗口带到最前面并成为 key（菜单栏 App 没有被激活时，`makeKeyAndOrderFront` 可能被压在其他 App 后面）。
    @MainActor
    func bringToFront() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}
