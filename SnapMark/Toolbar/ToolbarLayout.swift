import CoreGraphics

/// 工具栏位置计算（屏幕本地坐标，y 向上）。
enum ToolbarLayout {
    enum Placement: Equatable {
        /// 选区下方，右对齐。
        case below
        /// 下方放不下：选区上方，右对齐。
        case above
        /// 上下都放不下：选区内部右下角。
        case inside
    }

    static let gap: CGFloat = 8

    static func frame(size: CGSize, selection: CGRect, bounds: CGRect) -> (frame: CGRect, placement: Placement) {
        let x = selection.maxX - size.width

        let belowY = selection.minY - gap - size.height
        if belowY >= bounds.minY {
            return (clampX(CGRect(x: x, y: belowY, width: size.width, height: size.height), bounds), .below)
        }

        let aboveY = selection.maxY + gap
        if aboveY + size.height <= bounds.maxY {
            return (clampX(CGRect(x: x, y: aboveY, width: size.width, height: size.height), bounds), .above)
        }

        let inside = CGRect(x: selection.maxX - gap - size.width, y: selection.minY + gap,
                            width: size.width, height: size.height)
        return (clamp(inside, bounds), .inside)
    }

    /// 属性条：放在工具栏远离选区的一侧（下方 → 更下方，上方 → 更上方，内部 → 工具栏上方），
    /// 放不下时换到另一侧。左边与工具栏对齐。
    static func stylePanelFrame(size: CGSize, toolbar: CGRect, placement: Placement, bounds: CGRect) -> CGRect {
        let spacing: CGFloat = 6
        let below = CGRect(x: toolbar.minX, y: toolbar.minY - spacing - size.height, width: size.width, height: size.height)
        let above = CGRect(x: toolbar.minX, y: toolbar.maxY + spacing, width: size.width, height: size.height)

        let preferred: CGRect
        let fallback: CGRect
        switch placement {
        case .below: (preferred, fallback) = (below, above)
        case .above, .inside: (preferred, fallback) = (above, below)
        }
        let fits = { (r: CGRect) in r.minY >= bounds.minY && r.maxY <= bounds.maxY }
        return clamp(fits(preferred) ? preferred : fallback, bounds)
    }

    private static func clampX(_ rect: CGRect, _ bounds: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        return r
    }

    private static func clamp(_ rect: CGRect, _ bounds: CGRect) -> CGRect {
        var r = clampX(rect, bounds)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }
}
