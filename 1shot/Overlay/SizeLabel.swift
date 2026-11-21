import CoreGraphics

/// 选区尺寸标签「宽 × 高」（物理像素）的文字与位置。
enum SizeLabel {
    static let gap: CGFloat = 4

    static func text(for pixelSize: CGSize) -> String {
        "\(Int(pixelSize.width.rounded())) × \(Int(pixelSize.height.rounded()))"
    }

    /// 标签放在选区左上角上方；上方放不下时放进选区内部左上角。始终保持在 bounds 内。
    /// 坐标为屏幕本地坐标（y 向上）。
    static func frame(labelSize: CGSize, selection: CGRect, bounds: CGRect) -> CGRect {
        var origin = CGPoint(x: selection.minX, y: selection.maxY + gap)
        if origin.y + labelSize.height > bounds.maxY {
            origin = CGPoint(x: selection.minX + gap, y: selection.maxY - gap - labelSize.height)
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - labelSize.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - labelSize.height)
        return CGRect(origin: origin, size: labelSize)
    }
}
