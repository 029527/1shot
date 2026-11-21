import AppKit

/// 文字标注的输入框。用 NSTextView 承载，保证中文输入法选词正常。
final class AnnotationTextView: NSTextView {
    /// Esc（且没有正在组字的拼音）时结束输入。
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() {
            // 正在组字：交给输入法取消候选。
            super.cancelOperation(sender)
        } else {
            onEscape?()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 管理一次文字输入：创建输入框、随内容调整大小、结束时生成 `TextShape`。
@MainActor
final class TextEditingController: NSObject, NSTextViewDelegate {
    /// 结束输入：有文字时给出图形，空文本给 nil（自动删除）。
    var onFinish: ((TextShape?) -> Void)?

    private(set) var textView: AnnotationTextView?
    private var topLeft: CGPoint = .zero
    private var maxWidth: CGFloat = 0
    private var style = ToolStyle(size: .medium, colorIndex: 0)

    var isEditing: Bool { textView != nil }

    /// 在 `host`（屏幕本地坐标）的 `point` 处开始输入。文字框左上角对齐点击位置，宽度不超过选区右边。
    func begin(at point: CGPoint, in host: NSView, selection: CGRect, style: ToolStyle) {
        let lineHeight = ceil(TextShape.font(size: style.fontSize).boundingRectForFont.height)
        let topLeft = CGPoint(x: point.x, y: min(point.y + lineHeight / 2, selection.maxY))
        begin(topLeft: topLeft, text: "", in: host, selection: selection, style: style)
    }

    /// 在指定左上角开始输入；`text` 非空时为重新编辑已有文字。
    func begin(topLeft: CGPoint, text: String, in host: NSView, selection: CGRect, style: ToolStyle) {
        finish()
        self.style = style
        let lineHeight = ceil(TextShape.font(size: style.fontSize).boundingRectForFont.height)
        self.topLeft = topLeft
        maxWidth = max(selection.maxX - topLeft.x, style.fontSize)

        let textView = AnnotationTextView(frame: CGRect(x: topLeft.x, y: topLeft.y - lineHeight,
                                                        width: style.fontSize, height: lineHeight))
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.wantsLayer = true
        textView.layer?.borderWidth = 1
        textView.layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        textView.layer?.cornerRadius = 1
        textView.onEscape = { [weak self] in self?.finish() }
        apply(style, to: textView)
        if !text.isEmpty {
            textView.string = text
            apply(style, to: textView)
            textView.selectAll(nil)
        }

        host.addSubview(textView)
        self.textView = textView
        textView.window?.makeKeyAndOrderFront(nil)
        textView.window?.makeFirstResponder(textView)
        resize()
    }

    /// 输入中切换颜色 / 字号。
    func update(style: ToolStyle) {
        guard let textView else { return }
        self.style = style
        apply(style, to: textView)
        resize()
    }

    private func apply(_ style: ToolStyle, to textView: NSTextView) {
        let attributes = TextShape.attributes(fontSize: style.fontSize, color: style.color.nsColor)
        textView.font = TextShape.font(size: style.fontSize)
        textView.textColor = style.color.nsColor
        textView.insertionPointColor = style.color.nsColor
        textView.typingAttributes = attributes
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    /// 结束输入（点击别处、Esc、完成截图前）。
    func finish() {
        guard let textView else { return }
        // 先确认输入法里还没上屏的文字。
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
        let text = textView.string
        self.textView = nil
        let window = textView.window
        textView.removeFromSuperview()
        if let overlay = window?.contentView {
            window?.makeFirstResponder(overlay)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = trimmed.isEmpty ? nil : TextShape(topLeft: topLeft, text: text, color: style.color,
                                                      fontSize: style.fontSize, maxWidth: maxWidth)
        onFinish?(shape)
    }

    func textDidChange(_ notification: Notification) {
        resize()
    }

    /// 宽度随内容增长到选区右边为止，之后自动换行；左上角固定。
    private func resize() {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let lineHeight = ceil(TextShape.font(size: style.fontSize).boundingRectForFont.height)
        let width = min(max(ceil(used.width) + 3, style.fontSize), maxWidth)
        let height = max(ceil(used.height), lineHeight)
        textView.frame = CGRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height)
    }
}
