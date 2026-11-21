import AppKit

@MainActor
protocol StylePanelDelegate: AnyObject {
    func stylePanel(_ panel: StylePanelView, didSelect size: SizeLevel)
    func stylePanel(_ panel: StylePanelView, didSelectColorAt index: Int)
    func stylePanel(_ panel: StylePanelView, didChange options: ToolOptions)
}

/// 工具栏旁边的属性条，按工具显示不同的控件：
/// - 普通工具：3 档粗细（文字为字号）+ 8 个颜色
/// - 高亮：形状（矩形 / 椭圆 / 圆角矩形）+ 不透明度
/// - 马赛克：效果（像素化 / 模糊）+ 方式（画笔 / 框选）+ 画笔粗细 + 强度
/// - 水印：文字 + 不透明度 + 颜色
final class StylePanelView: NSView, NSTextFieldDelegate {
    weak var delegate: StylePanelDelegate?

    static let itemSize: CGFloat = 26
    static let padding: CGFloat = 5

    private var sizeButtons: [StyleButton] = []
    private var colorButtons: [StyleButton] = []
    private var shapeButtons: [StyleButton] = []
    private var effectButtons: [StyleButton] = []
    private var modeButtons: [StyleButton] = []
    private var separators: [NSView] = []

    private let amountTitle = NSTextField(labelWithString: "")
    private let amountSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let amountValue = NSTextField(labelWithString: "")
    let textField = NSTextField(string: "")

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
        // 属性条始终是浅色背景，控件也固定浅色外观。
        appearance = NSAppearance(named: .aqua)

        for level in SizeLevel.allCases {
            sizeButtons.append(makeButton(.size(level), tag: level.rawValue, action: #selector(sizeClicked(_:))))
        }
        for (index, color) in Palette.colors.enumerated() {
            let button = makeButton(.color(color), tag: index, action: #selector(colorClicked(_:)))
            button.toolTip = Palette.names[index]
            colorButtons.append(button)
        }
        let shapes: [(String, String)] = [
            ("rectangle", String(localized: "矩形")), ("circle", String(localized: "椭圆")),
            ("app", String(localized: "圆角矩形")),
        ]
        for (index, (symbol, name)) in shapes.enumerated() {
            let button = makeButton(.symbol(symbol), tag: index, action: #selector(shapeClicked(_:)))
            button.toolTip = name
            shapeButtons.append(button)
        }
        let effects: [(String, String)] = [
            ("checkerboard.rectangle", String(localized: "像素化")), ("drop", String(localized: "模糊")),
        ]
        for (index, (symbol, name)) in effects.enumerated() {
            let button = makeButton(.symbol(symbol), tag: index, action: #selector(effectClicked(_:)))
            button.toolTip = name
            effectButtons.append(button)
        }
        let modes: [(String, String)] = [
            ("paintbrush.pointed", String(localized: "画笔涂抹")), ("rectangle.dashed", String(localized: "框选区域")),
        ]
        for (index, (symbol, name)) in modes.enumerated() {
            let button = makeButton(.symbol(symbol), tag: index, action: #selector(modeClicked(_:)))
            button.toolTip = name
            modeButtons.append(button)
        }

        for label in [amountTitle, amountValue] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = NSColor(white: 0.25, alpha: 1)
            addSubview(label)
        }
        amountValue.alignment = .right
        amountValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        amountSlider.controlSize = .small
        amountSlider.isContinuous = true
        amountSlider.target = self
        amountSlider.action = #selector(amountChanged(_:))
        addSubview(amountSlider)

        textField.placeholderString = String(localized: "最多 \(String(WatermarkShape.maxLength)) 个字")
        textField.font = .systemFont(ofSize: 12)
        textField.bezelStyle = .roundedBezel
        textField.controlSize = .small
        textField.delegate = self
        textField.focusRingType = .none
        addSubview(textField)

        configure(tool: .rectangle, style: style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeButton(_ kind: StyleButton.Kind, tag: Int, action: Selector) -> StyleButton {
        let button = StyleButton(kind: kind)
        button.tag = tag
        button.target = self
        button.action = action
        addSubview(button)
        return button
    }

    /// 水印文字框正在输入。
    var isEditingText: Bool {
        guard let editor = window?.firstResponder as? NSText else { return false }
        return editor.delegate === textField
    }

    // MARK: 布局

    func configure(tool: AnnotationTool, style: ToolStyle) {
        let toolChanged = tool != self.tool
        self.tool = tool
        self.style = style
        let options = style.options

        var x = Self.padding
        var separatorIndex = 0
        func separator() {
            if separatorIndex == separators.count {
                let line = NSView()
                line.wantsLayer = true
                line.layer?.backgroundColor = NSColor(white: 0, alpha: 0.15).cgColor
                addSubview(line)
                separators.append(line)
            }
            let line = separators[separatorIndex]
            line.isHidden = false
            line.frame = CGRect(x: x + 5, y: Self.padding + 5, width: 1, height: Self.itemSize - 10)
            separatorIndex += 1
            x += 11
        }
        func place(_ buttons: [StyleButton], visible: Bool, chosen: Int?) {
            for button in buttons {
                button.isHidden = !visible
                guard visible else { continue }
                button.isChosen = button.tag == chosen
                button.frame = CGRect(x: x, y: Self.padding, width: Self.itemSize, height: Self.itemSize)
                x += Self.itemSize
            }
        }
        var groups = 0
        func beginGroup() {
            if groups > 0 { separator() }
            groups += 1
        }

        // 水印文字
        let showText = tool == .watermark
        textField.isHidden = !showText
        if showText {
            beginGroup()
            if toolChanged || !isEditingText { textField.stringValue = options.text }
            textField.frame = CGRect(x: x + 2, y: Self.padding + 2, width: 150, height: Self.itemSize - 4)
            x += 154
        }

        // 高亮形状
        let showShapes = tool == .spotlight
        if showShapes { beginGroup() }
        place(shapeButtons, visible: showShapes, chosen: options.spotlightShape.rawValue)

        // 马赛克效果、方式
        let isMosaic = tool == .mosaic
        if isMosaic { beginGroup() }
        place(effectButtons, visible: isMosaic, chosen: options.mosaicEffect.rawValue)
        if isMosaic { beginGroup() }
        place(modeButtons, visible: isMosaic, chosen: options.mosaicMode.rawValue)

        // 粗细 / 字号
        let showSizes = tool.usesSize(options)
        if showSizes { beginGroup() }
        let sizeNames = tool == .text
            ? [String(localized: "小号字"), String(localized: "中号字"), String(localized: "大号字")]
            : [String(localized: "细"), String(localized: "中"), String(localized: "粗")]
        for button in sizeButtons {
            button.isTextTool = tool == .text
            button.toolTip = sizeNames[button.tag]
        }
        place(sizeButtons, visible: showSizes, chosen: style.size.rawValue)

        // 强度 / 不透明度
        let amountName = tool.amountTitle
        let showAmount = amountName != nil
        for view in [amountTitle, amountSlider, amountValue] as [NSView] { view.isHidden = !showAmount }
        if let amountName {
            beginGroup()
            amountTitle.stringValue = amountName
            amountTitle.sizeToFit()
            amountTitle.frame.origin = CGPoint(x: x + 4, y: (Self.itemSize + Self.padding * 2 - amountTitle.frame.height) / 2)
            x += amountTitle.frame.width + 10
            amountSlider.doubleValue = options.amount
            amountSlider.frame = CGRect(x: x, y: Self.padding + 3, width: 110, height: Self.itemSize - 6)
            x += 114
            amountValue.stringValue = Self.percent(options.amount)
            amountValue.frame = CGRect(x: x, y: amountTitle.frame.minY, width: 40, height: amountTitle.frame.height)
            x += 44
        }

        // 颜色
        let showColors = tool.usesColor
        if showColors { beginGroup() }
        place(colorButtons, visible: showColors, chosen: style.colorIndex)

        for line in separators.dropFirst(separatorIndex) { line.isHidden = true }
        setFrameSize(CGSize(width: x + Self.padding, height: Self.itemSize + Self.padding * 2))
    }

    static func percent(_ amount: Double) -> String {
        "\(Int((amount * 100).rounded()))%"
    }

    // MARK: 动作

    @objc private func sizeClicked(_ sender: StyleButton) {
        guard let level = SizeLevel(rawValue: sender.tag) else { return }
        delegate?.stylePanel(self, didSelect: level)
    }

    @objc private func colorClicked(_ sender: StyleButton) {
        delegate?.stylePanel(self, didSelectColorAt: sender.tag)
    }

    private func change(_ update: (inout ToolOptions) -> Void) {
        var options = style.options
        update(&options)
        delegate?.stylePanel(self, didChange: options)
    }

    @objc private func shapeClicked(_ sender: StyleButton) {
        change { $0.spotlightShape = SpotlightShapeKind(rawValue: sender.tag) ?? .rectangle }
    }

    @objc private func effectClicked(_ sender: StyleButton) {
        change { $0.mosaicEffect = MosaicEffect(rawValue: sender.tag) ?? .pixelate }
    }

    @objc private func modeClicked(_ sender: StyleButton) {
        change { $0.mosaicMode = MosaicMode(rawValue: sender.tag) ?? .brush }
    }

    @objc private func amountChanged(_ sender: NSSlider) {
        // 按 5% 取整，数值更干净。
        let value = (sender.doubleValue * 20).rounded() / 20
        amountValue.stringValue = Self.percent(value)
        change { $0.amount = value }
    }

    func controlTextDidChange(_ notification: Notification) {
        var text = textField.stringValue
        if text.count > WatermarkShape.maxLength {
            text = String(text.prefix(WatermarkShape.maxLength))
            textField.stringValue = text
        }
        change { $0.text = text }
    }

    /// 回车：结束输入，把焦点还给画布。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            return true
        }
        return false
    }

    func endEditing() {
        guard isEditingText else { return }
        window?.makeFirstResponder(nil)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 属性条里的一个按钮：粗细圆点 / 字号 A / 颜色块 / 选项图标。
final class StyleButton: NSButton {
    enum Kind {
        case size(SizeLevel)
        case color(PaletteColor)
        case symbol(String)
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
        let highlightsBackground: Bool
        switch kind {
        case .size, .symbol: highlightsBackground = true
        case .color: highlightsBackground = false
        }
        if isChosen, highlightsBackground {
            OverlayView.accentColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }
        let tint = isChosen ? OverlayView.accentColor : NSColor(white: 0.25, alpha: 1)

        switch kind {
        case .size(let level):
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

        case .symbol(let name):
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                .applying(.init(paletteColors: [tint]))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)?
                .withSymbolConfiguration(config) else { return }
            let size = image.size
            image.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                  width: size.width, height: size.height))

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
