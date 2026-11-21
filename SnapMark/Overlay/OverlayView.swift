import AppKit
import QuartzCore

/// 遮罩视图把所有输入事件交给控制器；坐标已换成 AppKit 全局坐标。
@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayView(_ view: OverlayView, mouseMovedTo point: CGPoint)
    func overlayView(_ view: OverlayView, mouseDownAt point: CGPoint, clickCount: Int, modifiers: NSEvent.ModifierFlags)
    func overlayView(_ view: OverlayView, mouseDraggedTo point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func overlayView(_ view: OverlayView, mouseUpAt point: CGPoint, modifiers: NSEvent.ModifierFlags)
    func overlayView(_ view: OverlayView, rightMouseDownAt point: CGPoint)
    func overlayView(_ view: OverlayView, keyDown event: NSEvent) -> Bool
    func overlayView(_ view: OverlayView, flagsChanged event: NSEvent)
    /// 处理 ⌘ 组合键命令；返回 false 表示交给系统（比如正在输入文字时的 ⌘C）。
    func overlayView(_ view: OverlayView, perform command: OverlayCommand) -> Bool
    func overlayViewDidPressEscape(_ view: OverlayView)
}

/// 遮罩上的 ⌘ 组合键命令。
enum OverlayCommand {
    /// ⌘C：完成。
    case finish
    /// ⌘S：另存为。
    case saveAs
    /// ⌘Z
    case undo
    /// ⇧⌘Z
    case redo

    init?(keyEquivalent event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return nil }
        switch (event.charactersIgnoringModifiers?.lowercased(), flags.contains(.shift)) {
        case ("c", false): self = .finish
        case ("s", false): self = .saveAs
        case ("z", false): self = .undo
        case ("z", true): self = .redo
        default: return nil
        }
    }
}

/// 一块屏幕上要画的选区装饰（屏幕本地坐标）。
struct OverlayChrome: Equatable {
    /// 不压暗的区域。
    var highlight: CGRect?
    /// 蓝色描边。
    var border: CGRect?
    var borderWidth: CGFloat = 1.5
    /// 控制点中心。
    var handles: [CGPoint] = []
    /// 尺寸标签文字，以及它依附的选区。
    var sizeText: String?
    var sizeAnchor: CGRect?
}

/// 遮罩视图：定格画面 + 压暗（选区内保持原亮度）+ 选区描边 / 控制点 / 尺寸标签 + 放大镜。
///
/// 除放大镜外都用 CALayer，拖动选区时只改 path 和 frame，不重绘整张图。
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?

    static let dimAlpha: CGFloat = 0.4
    static let accentColor = NSColor(srgbRed: 0.12, green: 0.53, blue: 1, alpha: 1)
    static let handleRadius: CGFloat = 4

    private let canvas = CanvasView()
    /// 标注画布挂在这里（只在选区所在屏幕上）。
    let annotationHost = PassthroughView()
    /// 工具栏、属性条、文字输入框挂在这里。
    let controlsHost = PassthroughView()
    let magnifier = MagnifierView(frame: CGRect(origin: .zero, size: MagnifierView.size))

    private(set) var chrome = OverlayChrome()
    private var scale: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)

        for host in [annotationHost, controlsHost] {
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            addSubview(host)
        }

        magnifier.isHidden = true
        addSubview(magnifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: 内容

    /// 显示新的定格画面。
    func show(image: CGImage, scale: CGFloat) {
        self.scale = scale
        canvas.setImage(image, scale: scale)
        update(chrome: OverlayChrome())
        magnifier.isHidden = true
    }

    /// 释放截图内存。
    func clear() {
        canvas.setImage(nil, scale: scale)
        update(chrome: OverlayChrome())
        magnifier.isHidden = true
        magnifier.content = nil
    }

    func update(chrome: OverlayChrome) {
        guard chrome != self.chrome || canvas.needsChromeLayout else { return }
        self.chrome = chrome
        canvas.render(chrome, scale: scale)
    }

    /// 显示放大镜；`cursor` 为本地坐标。传 nil 隐藏。
    func updateMagnifier(_ content: MagnifierView.Content?, cursor: CGPoint) {
        guard let content else {
            magnifier.isHidden = true
            return
        }
        magnifier.frame = MagnifierLayout.frame(cursor: cursor, size: MagnifierView.size, bounds: bounds)
        magnifier.content = content
        magnifier.isHidden = false
    }

    // MARK: 事件

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        ))
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.overlayView(self, mouseMovedTo: globalPoint(event))
    }

    override func mouseMoved(with event: NSEvent) {
        delegate?.overlayView(self, mouseMovedTo: globalPoint(event))
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.overlayView(self, mouseDownAt: globalPoint(event), clickCount: event.clickCount,
                              modifiers: event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.overlayView(self, mouseDraggedTo: globalPoint(event), modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.overlayView(self, mouseUpAt: globalPoint(event), modifiers: event.modifierFlags)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let command = OverlayCommand(keyEquivalent: event),
           delegate?.overlayView(self, perform: command) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // 主菜单「编辑」里的 ⌘C / ⌘Z 也可能先走到这里（响应链）。
    @objc func copy(_ sender: Any?) { _ = delegate?.overlayView(self, perform: .finish) }
    @objc func undo(_ sender: Any?) { _ = delegate?.overlayView(self, perform: .undo) }
    @objc func redo(_ sender: Any?) { _ = delegate?.overlayView(self, perform: .redo) }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayView(self, rightMouseDownAt: globalPoint(event))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            handleEscape()
            return
        }
        if delegate?.overlayView(self, keyDown: event) == true { return }
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        delegate?.overlayView(self, flagsChanged: event)
    }

    func handleEscape() {
        delegate?.overlayViewDidPressEscape(self)
    }
}

/// 透明容器：自己不接收点击，只让子视图接收。
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// 只负责画图层，不接收事件。
private final class CanvasView: NSView {
    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let labelBackground = CALayer()
    private let labelText = CATextLayer()

    private(set) var needsChromeLayout = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest

        dimLayer.fillColor = NSColor.black.withAlphaComponent(OverlayView.dimAlpha).cgColor
        dimLayer.fillRule = .evenOdd

        borderLayer.fillColor = nil
        borderLayer.strokeColor = OverlayView.accentColor.cgColor

        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = OverlayView.accentColor.cgColor
        handlesLayer.lineWidth = 1.5

        labelBackground.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        labelBackground.cornerRadius = 4
        labelText.alignmentMode = .center
        labelText.truncationMode = .none
        labelBackground.addSublayer(labelText)

        for sublayer in [imageLayer, dimLayer, borderLayer, handlesLayer, labelBackground] {
            layer?.addSublayer(sublayer)
        }
        for sublayer in [imageLayer, dimLayer, borderLayer, handlesLayer, labelBackground, labelText] {
            sublayer.actions = Self.noAnimations
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let noAnimations: [String: CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "path": NSNull(),
        "frame": NSNull(), "hidden": NSNull(), "string": NSNull(), "lineWidth": NSNull(),
    ]

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        needsChromeLayout = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        dimLayer.frame = bounds
        borderLayer.frame = bounds
        handlesLayer.frame = bounds
        CATransaction.commit()
    }

    func setImage(_ image: CGImage?, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.contentsScale = scale
        imageLayer.contents = image
        CATransaction.commit()
    }

    func render(_ chrome: OverlayChrome, scale: CGFloat) {
        needsChromeLayout = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // 压暗：整屏减去高亮区域（even-odd）。
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let highlight = chrome.highlight, !highlight.isEmpty {
            dimPath.addRect(highlight)
        }
        dimLayer.frame = bounds
        dimLayer.path = dimPath

        // 描边画在区域内侧，整屏高亮时也看得见。
        if let border = chrome.border, !border.isEmpty {
            let inset = min(chrome.borderWidth / 2, border.width / 2, border.height / 2)
            borderLayer.lineWidth = chrome.borderWidth
            borderLayer.path = CGPath(rect: border.insetBy(dx: inset, dy: inset), transform: nil)
            borderLayer.isHidden = false
        } else {
            borderLayer.isHidden = true
        }

        // 控制点
        if chrome.handles.isEmpty {
            handlesLayer.isHidden = true
        } else {
            let path = CGMutablePath()
            let r = OverlayView.handleRadius
            for p in chrome.handles {
                path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            handlesLayer.path = path
            handlesLayer.isHidden = false
        }

        // 尺寸标签
        if let text = chrome.sizeText, let anchor = chrome.sizeAnchor {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            let attributed = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: NSColor.white,
            ])
            let textSize = attributed.size()
            let labelSize = CGSize(width: ceil(textSize.width) + 12, height: ceil(textSize.height) + 6)
            labelBackground.frame = SizeLabel.frame(labelSize: labelSize, selection: anchor, bounds: bounds)
            labelText.contentsScale = scale
            labelText.string = attributed
            labelText.frame = CGRect(x: 0, y: 3, width: labelSize.width, height: ceil(textSize.height))
            labelBackground.isHidden = false
        } else {
            labelBackground.isHidden = true
        }
    }
}

/// 常用的虚拟键码。
enum KeyCode {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let c: UInt16 = 8
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
