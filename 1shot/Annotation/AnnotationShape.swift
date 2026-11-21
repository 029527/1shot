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
    /// 选区（本地 pt）：高亮变暗、水印平铺的范围。
    var bounds: CGRect = .zero
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

    // MARK: 编辑（选中已有图形再修改）

    /// 画出这个图形的工具（决定属性条显示什么）。
    var tool: AnnotationTool { get }
    /// 当前样式（属性条回显）。
    var style: ToolStyle { get }
    /// 换颜色 / 粗细，id 不变。
    func restyled(_ style: ToolStyle) -> any AnnotationShape
    /// 整体平移，id 不变。
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape
    /// 可拖动的编辑控制点。
    var editHandles: [CGPoint] { get }
    /// 拖动第 `index` 个控制点到 `point`。
    func dragging(handle index: Int, to point: CGPoint, constrain: Bool) -> any AnnotationShape
}

extension AnnotationShape {
    var editHandles: [CGPoint] { [] }
    func dragging(handle index: Int, to point: CGPoint, constrain: Bool) -> any AnnotationShape { self }
}

extension ToolStyle {
    /// 由图形的实际数值反推档位和颜色序号（属性条回显用）。
    static func matching(value: CGFloat, in levels: [CGFloat], color: PaletteColor?) -> ToolStyle {
        let index = levels.indices.min { abs(levels[$0] - value) < abs(levels[$1] - value) } ?? 1
        let colorIndex = color.flatMap { Palette.colors.firstIndex(of: $0) } ?? Palette.defaultIndex
        return ToolStyle(size: SizeLevel(rawValue: index) ?? .medium, colorIndex: colorIndex)
    }
}

/// 拖动矩形类控制点：被拖的边移到 `point`，对边固定；越过对边时翻转。控制点顺序同 `SelectionHandle.allCases`。
func resizedRect(_ rect: CGRect, handleIndex: Int, to point: CGPoint, square: Bool) -> CGRect {
    guard SelectionHandle.allCases.indices.contains(handleIndex) else { return rect }
    let handle = SelectionHandle.allCases[handleIndex]
    var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    if handle.movesMinX { minX = point.x }
    if handle.movesMaxX { maxX = point.x }
    if handle.movesMinY { minY = point.y }
    if handle.movesMaxY { maxY = point.y }
    var result = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    if square, handle.movesMinX || handle.movesMaxX, handle.movesMinY || handle.movesMaxY {
        // 角点 + ⇧：以对角为锚点保持正方形。
        let anchor = CGPoint(x: handle.movesMinX ? rect.maxX : rect.minX, y: handle.movesMinY ? rect.maxY : rect.minY)
        result = ShapeBuilder.rect(from: anchor, to: point, square: true)
    }
    return result
}

private func offset(_ points: [CGPoint], _ dx: CGFloat, _ dy: CGFloat) -> [CGPoint] {
    points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
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
    /// 涂抹轨迹，或框选的区域。
    enum Region {
        case stroke(points: [CGPoint], brushWidth: CGFloat)
        case rect(CGRect)
    }

    let id = UUID()
    var region: Region
    var effect: MosaicEffect
    /// 0…1：像素块大小 / 模糊半径。
    var amount: Double

    init(region: Region, effect: MosaicEffect, amount: Double) {
        self.region = region
        self.effect = effect
        self.amount = min(max(amount, 0), 1)
    }

    /// 画笔像素化（兼容旧接口）：`blockSize` 换算成强度。
    init(points: [CGPoint], brushWidth: CGFloat, blockSize: CGFloat) {
        self.init(region: .stroke(points: points, brushWidth: brushWidth), effect: .pixelate,
                  amount: Double((blockSize - Self.minBlockSize) / Self.blockSizeRange))
    }

    static let minBlockSize: CGFloat = 4
    static let blockSizeRange: CGFloat = 24
    static let minBlurRadius: CGFloat = 2
    static let blurRadiusRange: CGFloat = 18

    /// 强度 → 像素块大小（pt）：4…28。
    static func blockSize(amount: Double) -> CGFloat {
        (minBlockSize + CGFloat(min(max(amount, 0), 1)) * blockSizeRange).rounded()
    }

    /// 强度 → 模糊半径（pt）：2…20。
    static func blurRadius(amount: Double) -> CGFloat {
        (minBlurRadius + CGFloat(min(max(amount, 0), 1)) * blurRadiusRange).rounded()
    }

    var blockSize: CGFloat { Self.blockSize(amount: amount) }
    var blurRadius: CGFloat { Self.blurRadius(amount: amount) }

    var points: [CGPoint] {
        if case .stroke(let points, _) = region { return points }
        return []
    }

    var brushWidth: CGFloat {
        if case .stroke(_, let width) = region { return width }
        return 0
    }

    var bounds: CGRect {
        switch region {
        case .stroke(let points, let width): return PenShape(points: points, color: PaletteColor(0), lineWidth: width).bounds
        case .rect(let rect): return rect
        }
    }

    var maskPath: CGPath {
        switch region {
        case .stroke(let points, let width):
            return PenShape.smoothPath(points)
                .copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        case .rect(let rect):
            return CGPath(rect: rect, transform: nil)
        }
    }

    /// 从定格原图（而不是已画的标注）取样。
    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        guard let source = environment.mosaic else { return }
        let image = effect == .pixelate ? source.pixelated(blockSize: blockSize) : source.blurred(radius: blurRadius)
        guard let image else { return }
        context.saveGState()
        context.addPath(maskPath)
        context.clip()
        context.interpolationQuality = effect == .pixelate ? .none : .high
        context.draw(image, in: source.localBounds)
        context.restoreGState()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        maskPath.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            .contains(point) || maskPath.contains(point)
    }
}

// MARK: - 高亮（框外变暗）

struct SpotlightShape: AnnotationShape {
    let id = UUID()
    var rect: CGRect
    var kind: SpotlightShapeKind
    /// 框外变暗的不透明度（0…1）。
    var opacity: Double

    var bounds: CGRect { rect.insetBy(dx: -2, dy: -2) }

    var path: CGPath {
        switch kind {
        case .rectangle: return CGPath(rect: rect, transform: nil)
        case .ellipse: return CGPath(ellipseIn: rect, transform: nil)
        case .roundedRectangle:
            let radius = min(12, min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }

    /// 单独画时（理论上不会，统一由 `AnnotationRenderer` 合并绘制）。
    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        Self.drawDimming([self], in: context, bounds: environment.bounds)
    }

    /// 多个高亮合并：`bounds` 内整体变暗一次，所有高亮区域保持原样。不透明度取最大值。
    static func drawDimming(_ spotlights: [SpotlightShape], in context: CGContext, bounds: CGRect) {
        guard let opacity = spotlights.map(\.opacity).max(), opacity > 0, !bounds.isEmpty else { return }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(CGColor(gray: 0, alpha: CGFloat(min(opacity, 1))))
        context.fill(bounds)
        context.setBlendMode(.clear)
        for spotlight in spotlights {
            context.addPath(spotlight.path)
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// 点在边框附近或区域内都算命中（区域内本来就是亮的，方便点中拖动）。
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        path.contains(point) || strokeHit(path, lineWidth: 1, point: point, tolerance: tolerance)
    }
}

// MARK: - 水印

struct WatermarkShape: AnnotationShape {
    static let maxLength = 16
    static let fontSize: CGFloat = 16
    static let angle: CGFloat = -.pi / 6

    let id = UUID()
    var text: String
    var color: PaletteColor
    var opacity: Double
    /// 铺满的范围（选区 / 贴图）。
    var area: CGRect

    var bounds: CGRect { area }

    var attributedText: NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Self.fontSize, weight: .medium),
            .foregroundColor: color.nsColor.withAlphaComponent(CGFloat(min(max(opacity, 0), 1))),
        ])
    }

    /// 斜向（-30°）平铺：行间错开半个间距。
    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        guard !text.isEmpty, !area.isEmpty else { return }
        let string = attributedText
        let size = string.size()
        let stepX = size.width + 56
        let stepY = size.height + 48
        // 旋转后要覆盖整个区域：以中心为原点，铺满对角线长度的范围。
        let radius = hypot(area.width, area.height) / 2 + max(stepX, stepY)

        context.saveGState()
        context.clip(to: area)
        context.translateBy(x: area.midX, y: area.midY)
        context.rotate(by: Self.angle)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        var row = 0
        var y = -radius
        while y < radius {
            var x = -radius + (row.isMultiple(of: 2) ? 0 : stepX / 2)
            while x < radius {
                string.draw(at: CGPoint(x: x, y: y))
                x += stepX
            }
            y += stepY
            row += 1
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    /// 水印不参与点选（不挡住下面的图形），通过水印工具的属性条修改。
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool { false }
}

// MARK: - 统一绘制

enum AnnotationRenderer {
    /// 分层绘制（层内保持添加顺序）：
    /// 1. 马赛克（相当于改了原图内容）
    /// 2. 高亮的变暗层（多个高亮合并，框外只暗一次，马赛克也一起变暗）
    /// 3. 其他标注（箭头、文字等，不被压暗）
    /// 4. 水印（最上层）
    /// `environment.bounds` 为选区（变暗、水印的范围）。
    static func draw(_ shapes: [any AnnotationShape], inProgress: (any AnnotationShape)? = nil,
                     in context: CGContext, environment: AnnotationEnvironment, dirtyRect: CGRect? = nil) {
        var all = shapes
        if let inProgress { all.append(inProgress) }
        func visible(_ shape: any AnnotationShape) -> Bool {
            guard let dirtyRect else { return true }
            return shape.bounds.intersects(dirtyRect)
        }
        for shape in all where shape is MosaicShape && visible(shape) {
            shape.draw(in: context, environment: environment)
        }
        SpotlightShape.drawDimming(all.compactMap { $0 as? SpotlightShape }, in: context, bounds: environment.bounds)
        for shape in all where !(shape is MosaicShape || shape is SpotlightShape || shape is WatermarkShape) && visible(shape) {
            shape.draw(in: context, environment: environment)
        }
        for shape in all where shape is WatermarkShape {
            shape.draw(in: context, environment: environment)
        }
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

// MARK: - 荧光笔

struct HighlighterShape: AnnotationShape {
    let id = UUID()
    var points: [CGPoint]
    var color: PaletteColor
    var lineWidth: CGFloat

    /// 半透明，整条笔画一次描边，自身重叠处不会变深。
    static let opacity: CGFloat = 0.4

    var path: CGPath { PenShape.smoothPath(points) }

    var bounds: CGRect {
        PenShape(points: points, color: color, lineWidth: lineWidth).bounds
    }

    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        context.saveGState()
        context.setAlpha(Self.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        strokeHit(path, lineWidth: lineWidth, point: point, tolerance: tolerance)
    }
}

// MARK: - 序号标记

struct CounterShape: AnnotationShape {
    let id = UUID()
    var center: CGPoint
    var number: Int
    var color: PaletteColor
    var diameter: CGFloat

    var circle: CGRect {
        CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    var bounds: CGRect { circle.insetBy(dx: -2, dy: -2) }

    /// 浅色底（白、黄）用黑字，其余用白字。
    var textColor: NSColor {
        let luminance = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        return luminance > 0.7 ? .black : .white
    }

    func draw(in context: CGContext, environment: AnnotationEnvironment) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: circle)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(max(1.5, diameter / 16))
        context.strokeEllipse(in: circle.insetBy(dx: diameter / 32, dy: diameter / 32))
        context.restoreGState()

        let text = "\(number)"
        let fontSize = diameter * (text.count > 1 ? 0.48 : 0.58)
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: textColor,
        ])
        let size = string.size()
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        NSGraphicsContext.current = previous
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= diameter / 2 + tolerance
    }
}

// MARK: - 编辑实现

extension RectangleShape {
    var tool: AnnotationTool { .rectangle }
    var style: ToolStyle { .matching(value: lineWidth, in: ToolStyle.lineWidths, color: color) }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.color = style.color; copy.lineWidth = style.lineWidth; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self; copy.rect = rect.offsetBy(dx: dx, dy: dy); return copy
    }
    var editHandles: [CGPoint] { SelectionHandle.allCases.map { $0.point(in: rect) } }
    func dragging(handle index: Int, to point: CGPoint, constrain: Bool) -> any AnnotationShape {
        var copy = self; copy.rect = resizedRect(rect, handleIndex: index, to: point, square: constrain); return copy
    }
}

extension EllipseShape {
    var tool: AnnotationTool { .ellipse }
    var style: ToolStyle { .matching(value: lineWidth, in: ToolStyle.lineWidths, color: color) }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.color = style.color; copy.lineWidth = style.lineWidth; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self; copy.rect = rect.offsetBy(dx: dx, dy: dy); return copy
    }
    var editHandles: [CGPoint] { SelectionHandle.allCases.map { $0.point(in: rect) } }
    func dragging(handle index: Int, to point: CGPoint, constrain: Bool) -> any AnnotationShape {
        var copy = self; copy.rect = resizedRect(rect, handleIndex: index, to: point, square: constrain); return copy
    }
}

extension ArrowShape {
    var tool: AnnotationTool { .arrow }
    var style: ToolStyle { .matching(value: lineWidth, in: ToolStyle.lineWidths, color: color) }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.color = style.color; copy.lineWidth = style.lineWidth; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self
        copy.start = CGPoint(x: start.x + dx, y: start.y + dy)
        copy.end = CGPoint(x: end.x + dx, y: end.y + dy)
        return copy
    }
    /// 起点、终点。
    var editHandles: [CGPoint] { [start, end] }
    func dragging(handle index: Int, to point: CGPoint, constrain: Bool) -> any AnnotationShape {
        var copy = self
        if index == 0 {
            copy.start = constrain ? ShapeBuilder.snap(from: end, to: point) : point
        } else {
            copy.end = constrain ? ShapeBuilder.snap(from: start, to: point) : point
        }
        return copy
    }
}

extension PenShape {
    var tool: AnnotationTool { .pen }
    var style: ToolStyle { .matching(value: lineWidth, in: ToolStyle.lineWidths, color: color) }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.color = style.color; copy.lineWidth = style.lineWidth; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self; copy.points = offset(points, dx, dy); return copy
    }
}

extension HighlighterShape {
    var tool: AnnotationTool { .highlighter }
    var style: ToolStyle { .matching(value: lineWidth, in: ToolStyle.highlighterWidths, color: color) }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.color = style.color; copy.lineWidth = style.highlighterWidth; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self; copy.points = offset(points, dx, dy); return copy
    }
}

extension MosaicShape {
    var tool: AnnotationTool { .mosaic }
    var style: ToolStyle {
        var style = ToolStyle.matching(value: brushWidth, in: ToolStyle.mosaicBrushWidths, color: nil)
        style.options.mosaicEffect = effect
        style.options.amount = amount
        if case .rect = region { style.options.mosaicMode = .area }
        return style
    }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self
        if case .stroke(let points, _) = region {
            copy.region = .stroke(points: points, brushWidth: style.mosaicBrushWidth)
        }
        copy.effect = style.options.mosaicEffect
        copy.amount = style.options.amount
        return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self
        switch region {
        case .stroke(let points, let width): copy.region = .stroke(points: offset(points, dx, dy), brushWidth: width)
        case .rect(let rect): copy.region = .rect(rect.offsetBy(dx: dx, dy: dy))
        }
        return copy
    }
    var editHandles: [CGPoint] {
        if case .rect(let rect) = region { return SelectionHandle.allCases.map { $0.point(in: rect) } }
        return []
    }
    func dragging(handle index: Int, to point: CGPoint, constrain: Bool) -> any AnnotationShape {
        guard case .rect(let rect) = region else { return self }
        var copy = self
        copy.region = .rect(resizedRect(rect, handleIndex: index, to: point, square: constrain))
        return copy
    }
}

extension SpotlightShape {
    var tool: AnnotationTool { .spotlight }
    var style: ToolStyle {
        var style = ToolStyle(size: .medium, colorIndex: Palette.defaultIndex)
        style.options.spotlightShape = kind
        style.options.amount = opacity
        return style
    }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.kind = style.options.spotlightShape; copy.opacity = style.options.amount; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self; copy.rect = rect.offsetBy(dx: dx, dy: dy); return copy
    }
    var editHandles: [CGPoint] { SelectionHandle.allCases.map { $0.point(in: rect) } }
    func dragging(handle index: Int, to point: CGPoint, constrain: Bool) -> any AnnotationShape {
        var copy = self; copy.rect = resizedRect(rect, handleIndex: index, to: point, square: constrain); return copy
    }
}

extension WatermarkShape {
    var tool: AnnotationTool { .watermark }
    var style: ToolStyle {
        var style = ToolStyle(size: .medium, colorIndex: Palette.colors.firstIndex(of: color) ?? 6)
        style.options.text = text
        style.options.amount = opacity
        return style
    }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self
        copy.color = style.color
        copy.opacity = style.options.amount
        copy.text = String(style.options.text.prefix(Self.maxLength))
        return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape { self }
}

extension TextShape {
    var tool: AnnotationTool { .text }
    var style: ToolStyle { .matching(value: fontSize, in: ToolStyle.fontSizes, color: color) }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.color = style.color; copy.fontSize = style.fontSize; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self; copy.topLeft = CGPoint(x: topLeft.x + dx, y: topLeft.y + dy); return copy
    }
}

extension CounterShape {
    var tool: AnnotationTool { .counter }
    var style: ToolStyle { .matching(value: diameter, in: ToolStyle.counterDiameters, color: color) }
    func restyled(_ style: ToolStyle) -> any AnnotationShape {
        var copy = self; copy.color = style.color; copy.diameter = style.counterDiameter; return copy
    }
    func moved(by dx: CGFloat, _ dy: CGFloat) -> any AnnotationShape {
        var copy = self; copy.center = CGPoint(x: center.x + dx, y: center.y + dy); return copy
    }
}
