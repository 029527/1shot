import AppKit

/// 工具栏上的按钮。
enum ToolbarItem: CaseIterable, Hashable {
    case rectangle, ellipse, arrow, pen, highlighter, text, counter, mosaic
    case undo, redo
    case longScreenshot, ocr, pin
    case save, cancel, done

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .counter: return "1.circle"
        case .text: return "t.square"
        case .mosaic: return "checkerboard.rectangle"
        case .longScreenshot: return "arrow.up.and.down.text.horizontal"
        case .ocr: return "text.viewfinder"
        case .pin: return "pin"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .save: return "square.and.arrow.down"
        case .cancel: return "xmark"
        case .done: return "checkmark"
        }
    }

    var title: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .highlighter: return "荧光笔"
        case .counter: return "序号"
        case .text: return "文字"
        case .mosaic: return "马赛克"
        case .longScreenshot: return "长截图"
        case .ocr: return "识别文字"
        case .pin: return "贴图到桌面"
        case .undo: return "撤销"
        case .redo: return "重做"
        case .save: return "保存"
        case .cancel: return "取消"
        case .done: return "完成"
        }
    }

    /// 悬停提示里显示的快捷键。
    var shortcutHint: String {
        switch self {
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .arrow: return "A"
        case .pen: return "P"
        case .highlighter: return "H"
        case .counter: return "N"
        case .text: return "T"
        case .mosaic: return "M"
        case .longScreenshot: return "⌘L"
        case .ocr: return "⌘R"
        case .pin: return "⌘T"
        case .undo: return "⌘Z"
        case .redo: return "⇧⌘Z"
        case .save: return "⌘S"
        case .cancel: return "Esc"
        case .done: return "Enter"
        }
    }

    var toolTip: String { "\(title)（\(shortcutHint)）" }

    var isDrawingTool: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .pen, .highlighter, .text, .counter, .mosaic: return true
        default: return false
        }
    }
}

@MainActor
protocol ToolbarViewDelegate: AnyObject {
    func toolbar(_ toolbar: ToolbarView, didClick item: ToolbarItem)
}

/// 选区下方的工具栏。
final class ToolbarView: NSView {
    static let buttonSize: CGFloat = 30
    static let padding: CGFloat = 5
    static let separatorWidth: CGFloat = 11

    weak var delegate: ToolbarViewDelegate?

    private var buttons: [ToolbarItem: ToolbarButton] = [:]

    /// 当前选中的绘图工具。
    var selectedTool: ToolbarItem? {
        didSet {
            for (item, button) in buttons where item.isDrawingTool {
                button.isSelectedTool = item == selectedTool
            }
        }
    }

    init(groups: [[ToolbarItem]]) {
        var x = Self.padding
        var layout: [(ToolbarItem, CGFloat)] = []
        var separators: [CGFloat] = []
        for (index, group) in groups.enumerated() {
            if index > 0 {
                separators.append(x + Self.separatorWidth / 2)
                x += Self.separatorWidth
            }
            for item in group {
                layout.append((item, x))
                x += Self.buttonSize
            }
        }
        let size = CGSize(width: x + Self.padding, height: Self.buttonSize + Self.padding * 2)
        super.init(frame: CGRect(origin: .zero, size: size))

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.98, alpha: 0.97).cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 0, alpha: 0.12).cgColor
        shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = CGSize(width: 0, height: -2)
            return shadow
        }()

        for (item, buttonX) in layout {
            let button = ToolbarButton(item: item)
            button.frame = CGRect(x: buttonX, y: Self.padding, width: Self.buttonSize, height: Self.buttonSize)
            button.target = self
            button.action = #selector(buttonClicked(_:))
            addSubview(button)
            buttons[item] = button
        }

        for sx in separators {
            let line = NSView(frame: CGRect(x: sx - 0.5, y: Self.padding + 6, width: 1, height: Self.buttonSize - 12))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor(white: 0, alpha: 0.15).cgColor
            addSubview(line)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 换一个按钮的悬停提示（同一个按钮在不同场景含义不同，比如贴图里的 ✕ 是关闭贴图）。
    func setToolTip(_ toolTip: String, for item: ToolbarItem) {
        buttons[item]?.toolTip = toolTip
    }

    func setEnabled(_ enabled: Bool, for item: ToolbarItem) {
        buttons[item]?.isEnabled = enabled
    }

    @objc private func buttonClicked(_ sender: ToolbarButton) {
        delegate?.toolbar(self, didClick: sender.item)
    }

    // 吞掉工具栏空白处的点击，避免传给遮罩开始框选。
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 工具栏按钮：SF Symbol 图标，选中时蓝底，悬停时灰底。
final class ToolbarButton: NSButton {
    let item: ToolbarItem

    var isSelectedTool = false {
        didSet { updateAppearance() }
    }

    private var isHovered = false {
        didSet { updateAppearance() }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    init(item: ToolbarItem) {
        self.item = item
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        title = ""
        toolTip = item.toolTip
        refusesFirstResponder = true
        setAccessibilityLabel(item.title)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title)?
            .withSymbolConfiguration(config)
        wantsLayer = true
        layer?.cornerRadius = 5
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func updateAppearance() {
        let accent = OverlayView.accentColor
        let tint: NSColor
        if !isEnabled {
            tint = NSColor(white: 0, alpha: 0.25)
        } else if isSelectedTool {
            tint = accent
        } else {
            switch item {
            case .done: tint = NSColor(srgbRed: 0.1, green: 0.65, blue: 0.3, alpha: 1)
            case .cancel: tint = NSColor(srgbRed: 0.85, green: 0.2, blue: 0.2, alpha: 1)
            default: tint = NSColor(white: 0.2, alpha: 1)
            }
        }
        contentTintColor = tint

        let background: NSColor
        if isSelectedTool {
            background = accent.withAlphaComponent(0.15)
        } else if isHovered, isEnabled {
            background = NSColor(white: 0, alpha: 0.07)
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
    }
}
