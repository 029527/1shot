import AppKit

/// 管理所有贴到桌面上的图片。
@MainActor
final class PinManager {
    static let shared = PinManager()

    private var windows: [PinWindow] = []

    var count: Int { windows.count }

    /// 把图片贴到桌面。`frame` 为 AppKit 全局坐标（pt），通常就是截图时的选区，贴图出现在原位。
    @discardableResult
    func pin(_ image: CGImage, frame: CGRect) -> PinWindow {
        let window = PinWindow(image: image, frame: frame)
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            windows.removeAll { $0 === window }
        }
        windows.append(window)
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(window.contentView)
        Log.app.notice("贴图：\(image.width, privacy: .public) × \(image.height, privacy: .public) px，共 \(self.windows.count, privacy: .public) 张")
        return window
    }

    /// 贴一张已有图片（截图历史里用），放在屏幕中央附近。
    func pin(_ image: CGImage, scale: CGFloat) {
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(windows.count % 10) * 24
        let origin = CGPoint(x: screen.midX - size.width / 2 + offset, y: screen.midY - size.height / 2 - offset)
        pin(image, frame: CGRect(origin: origin, size: size))
    }

    func closeAll() {
        for window in windows { window.close() }
        windows.removeAll()
    }
}

/// 贴图窗口：置顶显示，可拖动、滚轮 / 触控板缩放，双击或 Esc 关闭，右键菜单。
final class PinWindow: NSPanel {
    var onClose: (() -> Void)?

    let image: CGImage
    /// 原始尺寸（pt）。
    let originalSize: CGSize
    private let pinView: PinView

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 5

    private(set) var zoom: CGFloat = 1

    init(image: CGImage, frame: CGRect) {
        self.image = image
        originalSize = frame.size
        pinView = PinView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none

        pinView.image = image
        pinView.pinWindow = self
        contentView = pinView
        initialFirstResponder = pinView
    }

    /// Esc 关闭。
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }

    override func becomeKey() {
        super.becomeKey()
        pinView.needsDisplay = true
    }

    override func resignKey() {
        super.resignKey()
        pinView.needsDisplay = true
    }

    // MARK: 缩放

    /// 以 `anchor`（窗口内坐标）为中心缩放到 `newZoom`。
    func setZoom(_ newZoom: CGFloat, anchor: CGPoint? = nil) {
        let clamped = min(max(newZoom, Self.minZoom), Self.maxZoom)
        guard clamped != zoom else { return }
        let old = frame
        let size = CGSize(width: (originalSize.width * clamped).rounded(), height: (originalSize.height * clamped).rounded())
        let anchor = anchor ?? CGPoint(x: old.width / 2, y: old.height / 2)
        let rx = old.width > 0 ? anchor.x / old.width : 0.5
        let ry = old.height > 0 ? anchor.y / old.height : 0.5
        let origin = CGPoint(x: old.minX + anchor.x - size.width * rx, y: old.minY + anchor.y - size.height * ry)
        zoom = clamped
        setFrame(CGRect(origin: origin, size: size), display: true)
        pinView.showZoomBadge("\(Int((clamped * 100).rounded()))%")
    }

    // MARK: 动作

    @objc func copyImage(_ sender: Any?) {
        PasteboardWriter.write(image)
        pinView.showZoomBadge("已复制")
    }

    @objc func saveImage(_ sender: Any?) {
        let format = Preferences.imageFormat
        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileNamer.fileName(for: Date(), fileExtension: format.fileExtension)
        panel.directoryURL = try? Preferences.ensureSaveDirectory()
        panel.allowedContentTypes = [ImageFormat.png.utType, ImageFormat.jpg.utType]
        panel.canCreateDirectories = true
        NSApp.activate()
        panel.begin { [image] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try FileSaver.write(image, format: ImageFormat(fileExtension: url.pathExtension), to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc func resetZoom(_ sender: Any?) {
        setZoom(1)
    }

    @objc func setOpacity(_ sender: NSMenuItem) {
        alphaValue = CGFloat(sender.tag) / 100
    }

    @objc func closePin(_ sender: Any?) {
        close()
    }

    @objc func closeAllPins(_ sender: Any?) {
        PinManager.shared.closeAll()
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("复制", #selector(copyImage(_:)), "c")
        add("另存为…", #selector(saveImage(_:)), "s")
        menu.addItem(.separator())
        add("原始大小", #selector(resetZoom(_:)), "0")
        let opacity = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for percent in [100, 80, 60, 40] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = self
            item.state = Int((alphaValue * 100).rounded()) == percent ? .on : .off
            opacityMenu.addItem(item)
        }
        opacity.submenu = opacityMenu
        menu.addItem(opacity)
        menu.addItem(.separator())
        add("关闭", #selector(closePin(_:)), "w")
        if PinManager.shared.count > 1 {
            add("关闭全部贴图", #selector(closeAllPins(_:)))
        }
        return menu
    }
}

/// 贴图内容视图。
final class PinView: NSView {
    var image: CGImage?
    weak var pinWindow: PinWindow?

    private let badge = NSTextField(labelWithString: "")
    private var badgeHide: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        badge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 0, alpha: 0.65).cgColor
        badge.layer?.cornerRadius = 4
        badge.isHidden = true
        addSubview(badge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = (pinWindow?.zoom ?? 1) == 1 ? .none : .high
        context.draw(image, in: bounds)
        // 细边框：区分贴图与背后内容；窗口为 key 时用蓝色。
        let isKey = window?.isKeyWindow == true
        (isKey ? OverlayView.accentColor : NSColor(white: 0.5, alpha: 0.6)).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    func showZoomBadge(_ text: String) {
        badge.stringValue = " \(text) "
        badge.sizeToFit()
        badge.frame.size.width += 8
        badge.frame.origin = CGPoint(x: (bounds.width - badge.frame.width) / 2, y: (bounds.height - badge.frame.height) / 2)
        badge.isHidden = false
        badgeHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.badge.isHidden = true }
        badgeHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            pinWindow?.close()
            return
        }
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = pinWindow?.makeContextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window = pinWindow else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0 else { return }
        window.setZoom(window.zoom * (1 + delta), anchor: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        guard let window = pinWindow else { return }
        window.setZoom(window.zoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            pinWindow?.close()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c": pinWindow?.copyImage(nil)
        case "s": pinWindow?.saveImage(nil)
        case "w": pinWindow?.close()
        case "0": pinWindow?.resetZoom(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
