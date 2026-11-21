import CoreGraphics

/// 正在拖动绘制的图形（纯逻辑）。坐标为屏幕本地 pt，已限制在选区内。
struct ShapeBuilder {
    let tool: AnnotationTool
    let style: ToolStyle
    let start: CGPoint
    private(set) var current: CGPoint
    private(set) var points: [CGPoint]
    private(set) var constrained = false

    /// 画笔 / 马赛克相邻采样点的最小间距。
    static let minimumPointSpacing: CGFloat = 1

    init(tool: AnnotationTool, style: ToolStyle, start: CGPoint) {
        self.tool = tool
        self.style = style
        self.start = start
        current = start
        points = [start]
    }

    /// `constrain`：按住 ⇧（正方形 / 正圆 / 45° 吸附）。
    mutating func update(to point: CGPoint, constrain: Bool) {
        current = point
        constrained = constrain
        if tool == .pen || tool == .mosaic, let last = points.last,
           hypot(point.x - last.x, point.y - last.y) >= Self.minimumPointSpacing {
            points.append(point)
        }
    }

    /// 当前状态对应的图形；太小（相当于单击）时返回 nil。
    func makeShape() -> (any AnnotationShape)? {
        switch tool {
        case .rectangle, .ellipse:
            let rect = Self.rect(from: start, to: current, square: constrained)
            guard rect.width >= 2 || rect.height >= 2 else { return nil }
            if tool == .rectangle {
                return RectangleShape(rect: rect, color: style.color, lineWidth: style.lineWidth)
            }
            return EllipseShape(rect: rect, color: style.color, lineWidth: style.lineWidth)

        case .arrow:
            let end = constrained ? Self.snap(from: start, to: current) : current
            guard hypot(end.x - start.x, end.y - start.y) >= 3 else { return nil }
            return ArrowShape(start: start, end: end, color: style.color, lineWidth: style.lineWidth)

        case .pen:
            return PenShape(points: points, color: style.color, lineWidth: style.lineWidth)

        case .mosaic:
            return MosaicShape(points: points, brushWidth: style.mosaicBrushWidth, blockSize: style.mosaicBlockSize)

        case .text:
            return nil
        }
    }

    /// 两点围成的矩形；`square` 时取较长边做正方形，方向跟随拖动方向。
    static func rect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
        var dx = b.x - a.x
        var dy = b.y - a.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return SelectionModel.rect(from: a, to: CGPoint(x: a.x + dx, y: a.y + dy))
    }

    /// 把终点吸附到 45° 的倍数方向，长度不变。
    static func snap(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return b }
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
    }
}
