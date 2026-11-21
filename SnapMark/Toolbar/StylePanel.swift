import AppKit

@MainActor
protocol StylePanelDelegate: AnyObject {
    func stylePanel(_ panel: StylePanelView, didSelect size: SizeLevel)
    func stylePanel(_ panel: StylePanelView, didSelectColorAt index: Int)
}

/// 工具栏下方的属性条：3 档粗细（文字为 3 档字号）+ 8 个预设颜色。
final class StylePanelView: NSView {
    weak var delegate: StylePanelDelegate?

    static let itemSize: CGFloat = 26
    static let padding: CGFloat = 5

    private var sizeButtons: [StyleButton] = []
    private var colorButtons: [StyleButton] = []
    private let separator = NSView()

    private(set) var tool: AnnotationTool = .rectangle
    private(set) var style = ToolStyle(size: .medium, colorIndex: 0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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

        for level in SizeLevel.allCases {
            let button = StyleButton(kind: .size(level))
            button.target = self
            button.action = #selector(sizeClicked(_:))
            sizeButtons.append(button)
            addSubview(button)
        }
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 0, alpha: 0.15).cgColor
        addSubview(separator)
        for (index, color) in Palette.colors.enumerated() {
            let button = StyleButton(kind: .color(color))
            button.toolTip = Palette.names[index]
            button.tag = index
            button.target = self
            button.action = #selector(colorClicked(_:))
            colorButtons.append(button)
            addSubview(button)
        }
        configure(tool: .rectangle, style: style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tool: AnnotationTool, style: ToolStyle) {
        self.tool = tool
        self.style = style

        let sizeNames = tool == .text ? [String(localized: "小号字"), String(localized: "中号字"), String(localized: "大号字")] : [String(localized: "细"), String(localized: "中"), String(localized: "粗")]
        var x = Self.padding
        for (index, button) in sizeButtons.enumerated() {
            button.kind = .size(SizeLevel(rawValue: index)!)
            button.isTextTool = tool == .text
            button.toolTip = sizeNames[index]
            button.isChosen = index == style.size.rawValue
            button.frame = CGRect(x: x, y: Self.padding, width: Self.itemSize, height: Self.itemSize)
            x += Self.itemSize
        }

        let showColors = tool.usesColor
        separator.isHidden = !showColors
        if showColors {
            separator.frame = CGRect(x: x + 5, y: Self.padding + 5, width: 1, height: Self.itemSize - 10)
            x += 11
        }
        for (index, button) in colorButtons.enumerated() {
            button.isHidden = !showColors
            button.isChosen = index == style.colorIndex
            if showColors {
                button.frame = CGRect(x: x, y: Self.padding, width: Self.itemSize, height: Self.itemSize)
                x += Self.itemSize
            }
        }
        setFrameSize(CGSize(width: x + Self.padding, height: Self.itemSize + Self.padding * 2))
    }

    @objc private func sizeClicked(_ sender: StyleButton) {
        guard case .size(let level) = sender.kind else { return }
        delegate?.stylePanel(self, didSelect: level)
    }

    @objc private func colorClicked(_ sender: StyleButton) {
        delegate?.stylePanel(self, didSelectColorAt: sender.tag)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 属性条里的一个按钮：粗细圆点 / 字号 A / 颜色块。
final class StyleButton: NSButton {
    enum Kind {
        case size(SizeLevel)
        case color(PaletteColor)
    }

    var kind: Kind { didSet { needsDisplay = true } }
    var isChosen = false { didSet { needsDisplay = true } }
    var isTextTool = false { didSet { needsDisplay = true } }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isBordered = false
        title = ""
        refusesFirstResponder = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        if isChosen, case .size = kind {
            OverlayView.accentColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }

        switch kind {
        case .size(let level):
            let tint = isChosen ? OverlayView.accentColor : NSColor(white: 0.25, alpha: 1)
            if isTextTool {
                let size: CGFloat = [10, 13, 16][level.rawValue]
                let string = NSAttributedString(string: "A", attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: tint,
                ])
                let s = string.size()
                string.draw(at: CGPoint(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2))
            } else {
                let diameter: CGFloat = [4, 7, 11][level.rawValue]
                tint.setFill()
                NSBezierPath(ovalIn: CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                                            width: diameter, height: diameter)).fill()
            }

        case .color(let color):
            let swatch = bounds.insetBy(dx: 6, dy: 6)
            color.nsColor.setFill()
            let path = NSBezierPath(roundedRect: swatch, xRadius: 3, yRadius: 3)
            path.fill()
            NSColor(white: 0, alpha: 0.2).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            if isChosen {
                OverlayView.accentColor.setStroke()
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 4, yRadius: 4)
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }
    }
}
