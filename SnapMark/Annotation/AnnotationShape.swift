import AppKit
import CoreGraphics

/// 标注颜色（sRGB）。
struct PaletteColor: Equatable, Hashable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    init(_ hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
    }
}

/// 绘制标注时需要的外部资源。
struct AnnotationEnvironment {
    /// 马赛克取样源（定格原图的像素化版本）。
    var mosaic: MosaicSource?
}

/// 一个标注图形。每个图形都是独立的数据对象，坐标为选区所在屏幕的**本地 pt 坐标**（y 向上）。
///
/// 第二期「选中已有图形再修改」：用 `hitTest` 找到图形，修改后用 `AnnotationDocument.replace` 写回。
protocol AnnotationShape {
    var id: UUID { get }
    /// 绘制覆盖的范围（含线宽），用于刷新和命中。
    var bounds: CGRect { get }
    func draw(in context: CGContext, environment: AnnotationEnvironment)
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool
}

extension AnnotationShape {
    /// 判断点是否落在描边路径附近。
    func strokeHit(_ path: CGPath, lineWidth: CGFloat, point: CGPoint, tolerance: CGFloat) -> Bool {
        path.copy(strokingWithWidth: lineWidth + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(point)
    }
}

// MARK: - 矩形 / 椭圆

struct RectangleShape: AnnotationShape {
    let id = UUID()
    var rect: CGRect
    var color: PaletteColor
    var lineWidth: CGFloat

    var bounds: CGRect { rect.insetBy(dx: -lineWidth, dy: -lineWidth) }

    var path: CGPath { CGPath(rect: rect, transform: nil) }

    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.miter)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        strokeHit(path, lineWidth: lineWidth, point: point, tolerance: tolerance)
    }
}

struct EllipseShape: AnnotationShape {
    let id = UUID()
    var rect: CGRect
    var color: PaletteColor
    var lineWidth: CGFloat

    var bounds: CGRect { rect.insetBy(dx: -lineWidth, dy: -lineWidth) }

    var path: CGPath { CGPath(ellipseIn: rect, transform: nil) }

    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        strokeHit(path, lineWidth: lineWidth, point: point, tolerance: tolerance)
    }
}

// MARK: - 箭头

struct ArrowShape: AnnotationShape {
    let id = UUID()
    var start: CGPoint
    var end: CGPoint
    var color: PaletteColor
    var lineWidth: CGFloat

    /// 箭头头部长度随粗细变化。
    static func headLength(for lineWidth: CGFloat) -> CGFloat { 8 + lineWidth * 3 }

    private var geometry: (shaftEnd: CGPoint, head: [CGPoint]) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return (end, []) }
        let ux = dx / length, uy = dy / length
        let headLength = min(Self.headLength(for: lineWidth), length)
        let halfWidth = headLength * 0.45
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let left = CGPoint(x: base.x - uy * halfWidth, y: base.y + ux * halfWidth)
        let right = CGPoint(x: base.x + uy * halfWidth, y: base.y - ux * halfWidth)
        // 杆在头部中间结束，避免圆头露出尖端。
        let shaftEnd = CGPoint(x: end.x - ux * headLength * 0.6, y: end.y - uy * headLength * 0.6)
        return (shaftEnd, [end, left, right])
    }

    var bounds: CGRect {
        let head = Self.headLength(for: lineWidth)
        return SelectionModel.rect(from: start, to: end).insetBy(dx: -head, dy: -head)
    }

    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        let (shaftEnd, head) = geometry
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()
        if head.count == 3 {
            context.move(to: head[0])
            context.addLine(to: head[1])
            context.addLine(to: head[2])
            context.closePath()
            context.fillPath()
        }
        context.restoreGState()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        return strokeHit(path, lineWidth: max(lineWidth, Self.headLength(for: lineWidth) * 0.5),
                         point: point, tolerance: tolerance)
    }
}

// MARK: - 画笔

struct PenShape: AnnotationShape {
    let id = UUID()
    var points: [CGPoint]
    var color: PaletteColor
    var lineWidth: CGFloat

    /// 平滑曲线：以相邻点的中点为端点、原始点为控制点的二次贝塞尔。
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            if points.count == 2 { path.addLine(to: points[1]) } else { path.addLine(to: first) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    var path: CGPath { Self.smoothPath(points) }

    var bounds: CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for p in points { rect = rect.union(CGRect(origin: p, size: .zero)) }
        return rect.insetBy(dx: -lineWidth, dy: -lineWidth)
    }

    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        strokeHit(path, lineWidth: lineWidth, point: point, tolerance: tolerance)
    }
}

// MARK: - 马赛克

struct MosaicShape: AnnotationShape {
    let id = UUID()
    var points: [CGPoint]
    /// 涂抹宽度（pt）。
    var brushWidth: CGFloat
    /// 像素块大小（pt）。
    var blockSize: CGFloat

    var bounds: CGRect {
        PenShape(points: points, color: PaletteColor(0), lineWidth: brushWidth).bounds
    }

    var maskPath: CGPath {
        PenShape.smoothPath(points)
            .copy(strokingWithWidth: brushWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    /// 从定格原图（而不是已画的标注）取样。
    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        guard let source = environment.mosaic, let image = source.pixelated(blockSize: blockSize) else { return }
        context.saveGState()
        context.addPath(maskPath)
        context.clip()
        context.interpolationQuality = .none
        context.draw(image, in: source.localBounds)
        context.restoreGState()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        maskPath.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(point) || maskPath.contains(point)
    }
}

// MARK: - 文字

struct TextShape: AnnotationShape {
    let id = UUID()
    /// 文字框左上角（本地坐标，y 向上）。
    var topLeft: CGPoint
    var text: String
    var color: PaletteColor
    var fontSize: CGFloat
    /// 自动换行宽度（与输入框一致）。
    var maxWidth: CGFloat

    static func font(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .medium)
    }

    static func attributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font(size: fontSize), .foregroundColor: color]
    }

    var attributedString: NSAttributedString {
        NSAttributedString(string: text, attributes: Self.attributes(fontSize: fontSize, color: color.nsColor))
    }

    var textSize: CGSize {
        let rect = attributedString.boundingRect(
            with: CGSize(width: max(maxWidth, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    var frame: CGRect {
        let size = textSize
        return CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    }

    var bounds: CGRect { frame.insetBy(dx: -2, dy: -2) }

    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let frame = self.frame
        attributedString.draw(
            with: CGRect(x: frame.minX, y: frame.minY, width: max(maxWidth, frame.width), height: frame.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        NSGraphicsContext.current = previous
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}
