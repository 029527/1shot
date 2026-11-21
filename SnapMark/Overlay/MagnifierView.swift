import AppKit

/// 一个像素的颜色（sRGB）。
struct PixelColor: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var rgb: String {
        "RGB(\(red), \(green), \(blue))"
    }

    func string(in format: ColorFormat) -> String {
        format == .hex ? hex : rgb
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

enum ColorFormat {
    case hex, rgb

    mutating func toggle() {
        self = self == .hex ? .rgb : .hex
    }
}

/// 从定格原图里取光标周围的像素。
enum PixelSampler {
    /// 放大镜显示的像素边长（奇数，中心是光标所在像素）。
    static let gridSize = 15

    struct Sample {
        /// gridSize × gridSize 的小图，超出原图的部分为黑色。
        let image: CGImage
        let center: PixelColor
    }

    /// `centerPixel` 为原图像素坐标（左上角原点）。
    static func sample(_ image: CGImage, centerPixel: CGPoint, gridSize: Int = gridSize) -> Sample? {
        let half = gridSize / 2
        let cx = Int(centerPixel.x.rounded(.down))
        let cy = Int(centerPixel.y.rounded(.down))
        let region = CGRect(x: cx - half, y: cy - half, width: gridSize, height: gridSize)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let visible = region.intersection(imageBounds)

        let bytesPerRow = gridSize * 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: gridSize, height: gridSize, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: gridSize, height: gridSize))
        context.interpolationQuality = .none

        if !visible.isNull, !visible.isEmpty, let cropped = image.cropping(to: visible) {
            // 像素坐标 y 向下，CGContext y 向上。
            let dx = visible.minX - region.minX
            let dyTop = visible.minY - region.minY
            let y = CGFloat(gridSize) - dyTop - visible.height
            context.draw(cropped, in: CGRect(x: dx, y: y, width: visible.width, height: visible.height))
        }

        guard let data = context.data, let output = context.makeImage() else { return nil }
        // 位图内存第一行是图像顶部。
        let offset = half * bytesPerRow + half * 4
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let color = PixelColor(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
        return Sample(image: output, center: color)
    }
}

/// 放大镜位置：默认在光标右下方，靠近屏幕边缘时换到另一侧。坐标为屏幕本地坐标（y 向上）。
enum MagnifierLayout {
    static let offset: CGFloat = 20

    static func frame(cursor: CGPoint, size: CGSize, bounds: CGRect) -> CGRect {
        var x = cursor.x + offset
        if x + size.width > bounds.maxX { x = cursor.x - offset - size.width }
        var y = cursor.y - offset - size.height
        if y < bounds.minY { y = cursor.y + offset }
        x = min(max(x, bounds.minX), bounds.maxX - size.width)
        y = min(max(y, bounds.minY), bounds.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// 放大镜：光标周围 15×15 像素的放大图、十字准线、坐标、颜色值。
final class MagnifierView: NSView {
    static let cellSize: CGFloat = 8
    static let infoHeight: CGFloat = 54
    static var loupeSide: CGFloat { CGFloat(PixelSampler.gridSize) * cellSize }
    static var size: CGSize { CGSize(width: loupeSide, height: loupeSide + infoHeight) }

    struct Content {
        var sample: PixelSampler.Sample
        /// 光标所在像素坐标（相对本屏截图）。
        var pixel: CGPoint
        var format: ColorFormat
        /// 临时提示，比如「已复制」。
        var feedback: String?
    }

    var content: Content? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let content, let context = NSGraphicsContext.current?.cgContext else { return }
        let side = Self.loupeSide
        let cell = Self.cellSize
        let loupe = CGRect(x: 0, y: Self.infoHeight, width: side, height: side)

        // 背景
        NSColor(white: 0.08, alpha: 0.92).setFill()
        bounds.fill()

        // 放大图（最近邻，像素清晰）
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(content.sample.image, in: loupe)
        context.restoreGState()

        // 十字准线：中心像素所在的行和列
        let half = CGFloat(PixelSampler.gridSize / 2)
        let crossColor = NSColor(srgbRed: 0.25, green: 0.6, blue: 1, alpha: 0.45)
        crossColor.setFill()
        CGRect(x: loupe.minX, y: loupe.minY + half * cell, width: side, height: cell).fill()
        CGRect(x: loupe.minX + half * cell, y: loupe.minY, width: cell, height: side).fill()

        // 中心像素框
        let centerCell = CGRect(x: loupe.minX + half * cell, y: loupe.minY + half * cell, width: cell, height: cell)
        NSColor.white.setStroke()
        let centerPath = NSBezierPath(rect: centerCell.insetBy(dx: 0.5, dy: 0.5))
        centerPath.lineWidth = 1
        centerPath.stroke()

        // 分隔线
        NSColor.white.withAlphaComponent(0.3).setFill()
        CGRect(x: 0, y: Self.infoHeight - 0.5, width: side, height: 0.5).fill()

        // 文字信息
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let primary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let secondary: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]

        let coordinate = "坐标 (\(Int(content.pixel.x)), \(Int(content.pixel.y)))"
        (coordinate as NSString).draw(at: CGPoint(x: 8, y: 36), withAttributes: primary)

        let swatch = CGRect(x: 8, y: 21, width: 11, height: 11)
        content.sample.center.nsColor.setFill()
        swatch.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        NSBezierPath(rect: swatch.insetBy(dx: 0.5, dy: 0.5)).stroke()
        (content.sample.center.string(in: content.format) as NSString)
            .draw(at: CGPoint(x: 24, y: 19), withAttributes: primary)

        let hint = content.feedback ?? "C 复制颜色  ⇧ 切换格式"
        (hint as NSString).draw(at: CGPoint(x: 8, y: 4), withAttributes: secondary)
    }
}
