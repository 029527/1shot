import AppKit

/// 管理所有贴到桌面上的图片。
@MainActor
final class PinManager {
    static let shared = PinManager()

    private var windows: [PinWindow] = []

    var count: Int { windows.count }

    /// 把图片贴到桌面。`frame` 为 AppKit 全局坐标（pt），通常就是截图时的选区，贴图出现在原位。
    @discardableResult
    func pin(_ image: CGImage, frame: CGRect, text: String? = nil) -> PinWindow {
        let window = PinWindow(image: image, frame: frame)
        window.text = text
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

    /// 贴一张 `size`（pt）大小的图片，以 `point` 为中心，保持在该屏幕可见区域内；太大时等比缩小。
    @discardableResult
    func pin(_ image: CGImage, size: CGSize, around point: CGPoint, text: String? = nil) -> PinWindow {
        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = Self.frame(for: size, around: point, in: screen)
        return pin(image, frame: frame, text: text)
    }

    /// 以 `point` 为中心放置，不超过可见区域的 80%，并整体放进可见区域。
    nonisolated static func frame(for size: CGSize, around point: CGPoint, in visible: CGRect) -> CGRect {
        let limit = CGSize(width: visible.width * 0.8, height: visible.height * 0.8)
        let ratio = min(1, limit.width / max(size.width, 1), limit.height / max(size.height, 1))
        let fitted = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        var origin = CGPoint(x: point.x - fitted.width / 2, y: point.y - fitted.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - fitted.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - fitted.height)
        return CGRect(origin: origin, size: fitted)
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
    /// 贴的是文字时保存原文，「复制」复制文字。
    var text: String?
    /// 原始尺寸（pt）。
    let originalSize: CGSize
    let pinView: PinView
    /// 编辑模式（空格打开）：第一次用到时创建。
    private(set) var editor: PinEditor?

    func toggleEditor() {
        if editor == nil { editor = PinEditor(pin: self) }
        editor?.toggleToolbar()
    }

    var isEditing: Bool { editor?.isToolbarVisible == true }

    /// 原图 + 标注（没有标注时就是原图）。
    var outputImage: CGImage { editor?.composedImage() ?? image }

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 5

    private(set) var zoom: CGFloat = 1

    init(image: CGImage, frame: CGRect) {
        self.image = image
        originalSize = frame.size
        pinView = PinView(frame: CGRect(origin: .zero, size: frame.size), originalSize: frame.size)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 拖动由 PinView 自己处理（编辑模式下拖动是画图）。
        isMovableByWindowBackground = false
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

    /// Esc：编辑中先逐级退出，否则关闭。
    override func cancelOperation(_ sender: Any?) {
        if let editor, editor.isToolbarVisible {
            editor.escape()
        } else {
            close()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        editor?.teardown()
        editor = nil
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
        // 编辑时固定原始大小。
        if isEditing, newZoom != 1 { return }
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
        if let text, editor?.hasAnnotations != true {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } else {
            PasteboardWriter.write(outputImage)
        }
        pinView.showZoomBadge(String(localized: "已复制"))
    }

    @objc func saveImage(_ sender: Any?) {
        let format = Preferences.imageFormat
        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileNamer.fileName(for: Date(), fileExtension: format.fileExtension)
        panel.directoryURL = try? Preferences.ensureSaveDirectory()
        panel.allowedContentTypes = [ImageFormat.png.utType, ImageFormat.jpg.utType]
        panel.canCreateDirectories = true
        NSApp.activate()
        let image = outputImage
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try FileSaver.write(image, format: ImageFormat(fileExtension: url.pathExtension), to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc func toggleEditorAction(_ sender: Any?) {
        toggleEditor()
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
        add(text == nil || editor?.hasAnnotations == true ? String(localized: "复制") : String(localized: "复制文字"), #selector(copyImage(_:)), "c")
        add(isEditing ? String(localized: "收起工具栏") : String(localized: "编辑标注"), #selector(toggleEditorAction(_:)), " ")
        add(String(localized: "另存为…"), #selector(saveImage(_:)), "s")
        menu.addItem(.separator())
        add(String(localized: "原始大小"), #selector(resetZoom(_:)), "0")
        let opacity = NSMenuItem(title: String(localized: "不透明度"), action: nil, keyEquivalent: "")
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
        add(String(localized: "关闭"), #selector(closePin(_:)), "w")
        if PinManager.shared.count > 1 {
            add(String(localized: "关闭全部贴图"), #selector(closeAllPins(_:)))
        }
        return menu
    }
}

/// 贴图内容视图。标注画布挂在 `annotationHost`（bounds 固定为原始尺寸，缩放时标注跟着缩放）。
final class PinView: NSView, AnnotationHost {
    var image: CGImage?
    weak var pinWindow: PinWindow?
    let originalSize: CGSize

    let annotationHost = PassthroughView()
    let controlsHost = PassthroughView()
    private let badge = NSTextField(labelWithString: "")
    private var badgeHide: DispatchWorkItem?
    /// 本次按下由标注处理（之后的拖动 / 松开也交给标注）。
    private var annotating = false

    init(frame frameRect: NSRect, originalSize: CGSize) {
        self.originalSize = originalSize
        super.init(frame: frameRect)
        wantsLayer = true
        for host in [annotationHost, controlsHost] {
            addSubview(host)
        }
        badge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 0, alpha: 0.65).cgColor
        badge.layer?.cornerRadius = 4
        badge.isHidden = true
        addSubview(badge)
        layoutHosts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutHosts()
    }

    /// 两个宿主铺满视图；标注宿主的坐标系固定为原始尺寸。
    private func layoutHosts() {
        annotationHost.frame = bounds
        annotationHost.bounds = CGRect(origin: .zero, size: originalSize)
        controlsHost.frame = bounds
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

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

    // MARK: 鼠标

    /// 事件位置换算到标注坐标（原始尺寸）。
    private func annotationPoint(_ event: NSEvent) -> CGPoint {
        annotationHost.convert(event.locationInWindow, from: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    override func mouseMoved(with event: NSEvent) { updateCursor() }

    func updateCursor() {
        guard let window, let editor = pinWindow?.editor, editor.isToolbarVisible else {
            NSCursor.arrow.set()
            return
        }
        let location = annotationHost.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        editor.cursor(at: location).set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if let editor = pinWindow?.editor,
           editor.mouseDown(at: annotationPoint(event), clickCount: event.clickCount, modifiers: event.modifierFlags) {
            annotating = true
            updateCursor()
            return
        }
        annotating = false
        if event.clickCount == 2, pinWindow?.isEditing != true {
            pinWindow?.close()
            return
        }
        window?.performDrag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard annotating else { return }
        pinWindow?.editor?.mouseDragged(to: annotationPoint(event), modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        guard annotating else { return }
        annotating = false
        pinWindow?.editor?.mouseUp(at: annotationPoint(event), modifiers: event.modifierFlags)
        updateCursor()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = pinWindow?.makeContextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window = pinWindow, !window.isEditing else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0 else { return }
        window.setZoom(window.zoom * (1 + delta), anchor: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        guard let window = pinWindow, !window.isEditing else { return }
        window.setZoom(window.zoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }

    // MARK: 键盘

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option])
        // 空格：显示 / 隐藏工具栏。
        if event.keyCode == KeyCode.space, plain {
            pinWindow?.toggleEditor()
            return
        }
        if let editor = pinWindow?.editor, editor.keyDown(event) {
            return
        }
        if event.keyCode == KeyCode.escape {
            pinWindow?.close()
            return
        }
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        pinWindow?.editor?.constrainChanged(event.modifierFlags.contains(.shift))
        super.flagsChanged(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 正在输入文字时交给输入框（⌘C / ⌘Z 作用于文字）。
        if window?.firstResponder is NSTextView { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        switch (key, shift) {
        case ("c", false): pinWindow?.copyImage(nil)
        case ("s", false): pinWindow?.saveImage(nil)
        case ("w", false): pinWindow?.close()
        case ("0", false): pinWindow?.resetZoom(nil)
        case ("z", _):
            guard let editor = pinWindow?.editor else { return false }
            editor.undo(redo: shift)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
