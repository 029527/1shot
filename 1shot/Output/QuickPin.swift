import AppKit
import UniformTypeIdentifiers

/// 快速贴图要贴的内容。
enum PinContent {
    /// 刚截的图（剪贴板还是它）：贴回原位置。
    case capture(OutputPipeline.LastCapture)
    /// 剪贴板里的图片。`size` 为 pt 尺寸（按图片 DPI 换算）。
    case image(CGImage, size: CGSize)
    /// 剪贴板里的文字 / 链接。
    case text(String)
}

/// 快速贴图（快捷键）：优先贴剪贴板内容；剪贴板里没有能贴的东西时，贴最近一次截图。
@MainActor
enum QuickPin {
    /// 文字最多取这么多字符。
    static let maxTextLength = 10_000

    static func run() {
        let pasteboard = NSPasteboard.general
        let content = content(from: pasteboard, lastCapture: OutputPipeline.lastCapture)
            ?? OutputPipeline.lastCapture.map(PinContent.capture)
            ?? latestHistory()
        guard let content else {
            Toast.shared.show(String(localized: "剪贴板里没有可以贴的图片或文字"), near: mouseAnchor())
            return
        }
        pin(content)
    }

    static func pin(_ content: PinContent) {
        switch content {
        case .capture(let capture):
            PinManager.shared.pin(capture.image, frame: capture.anchor)
        case .image(let image, let size):
            PinManager.shared.pin(image, size: size, around: NSEvent.mouseLocation)
        case .text(let text):
            let scale = screen(containing: NSEvent.mouseLocation)?.backingScaleFactor ?? 2
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            guard let card = TextCardRenderer.render(text, scale: scale, dark: dark) else { return }
            PinManager.shared.pin(card.image, size: card.size, around: NSEvent.mouseLocation, text: text)
        }
    }

    /// 读剪贴板：刚截的图 → 图片文件 → 图片数据 → 文字。都没有返回 nil。
    static func content(from pasteboard: NSPasteboard, lastCapture: OutputPipeline.LastCapture?) -> PinContent? {
        if let lastCapture, lastCapture.pasteboardChangeCount == pasteboard.changeCount {
            return .capture(lastCapture)
        }

        let imageFiles = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL] ?? []
        for url in imageFiles {
            if let data = try? Data(contentsOf: url), let image = bitmap(from: data) {
                return image
            }
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = bitmap(from: data) {
                return image
            }
        }

        if let string = pasteboard.string(forType: .string) {
            let text = String(string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
            if !text.isEmpty { return .text(text) }
        }
        return nil
    }

    private static func bitmap(from data: Data) -> PinContent? {
        guard let rep = NSBitmapImageRep(data: data), let image = rep.cgImage else { return nil }
        var size = rep.size
        if size.width < 1 || size.height < 1 {
            size = CGSize(width: image.width, height: image.height)
        }
        return .image(image, size: size)
    }

    private static func latestHistory() -> PinContent? {
        let store = HistoryStore.shared
        guard let item = store.items.first, let image = store.image(for: item) else { return nil }
        let scale = max(item.scale, 1)
        return .image(image, size: CGSize(width: CGFloat(item.width) / scale, height: CGFloat(item.height) / scale))
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private static func mouseAnchor() -> CGRect {
        let point = NSEvent.mouseLocation
        return CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
    }
}

/// 把文字画成一张卡片图片（贴图用）。链接用链接色加下划线。
enum TextCardRenderer {
    static let fontSize: CGFloat = 14
    static let padding: CGFloat = 12
    static let maxWidth: CGFloat = 420
    static let maxHeight: CGFloat = 600
    static let minWidth: CGFloat = 60

    /// 整段文字是否是一个链接。
    static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isWhitespace }),
              let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    static func attributed(_ text: String, dark: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.1, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        if isLink(text) {
            attributes[.foregroundColor] = dark ? NSColor(srgbRed: 0.42, green: 0.66, blue: 1, alpha: 1)
                : NSColor(srgbRed: 0.0, green: 0.4, blue: 0.85, alpha: 1)
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            // 长链接没有空格，按字符换行。
            paragraph.lineBreakMode = .byCharWrapping
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// 卡片的 pt 尺寸：宽度按内容收缩，最宽 `maxWidth`；高度最高 `maxHeight`（超出部分截断）。
    static func layout(_ string: NSAttributedString) -> (size: CGSize, textRect: CGRect) {
        let bound = string.boundingRect(
            with: CGSize(width: maxWidth - padding * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let width = min(maxWidth, max(minWidth, bound.width.rounded(.up) + padding * 2))
        let height = min(maxHeight, bound.height.rounded(.up) + padding * 2)
        let textRect = CGRect(x: padding, y: padding, width: width - padding * 2, height: height - padding * 2)
        return (CGSize(width: width, height: height), textRect)
    }

    static func render(_ text: String, scale: CGFloat, dark: Bool) -> (image: CGImage, size: CGSize)? {
        let string = attributed(text, dark: dark)
        let (size, textRect) = layout(string)
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(dark ? CGColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
            : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else { return nil }
        return (image, size)
    }
}
