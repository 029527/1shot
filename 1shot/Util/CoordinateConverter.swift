import AppKit
import CoreGraphics

/// 全局坐标换算。
///
/// - AppKit 全局坐标：原点在**主屏左下角**，y 轴向上，单位 pt。
/// - CG 全局坐标（`CGWindowList`、ScreenCaptureKit、`CGDisplayBounds`）：原点在**主屏左上角**，y 轴向下，单位 pt。
///
/// 两者只差一次以主屏高度为轴的翻转，所以只需要主屏高度。
struct CoordinateConverter: Equatable {
    /// 主屏（`NSScreen.screens[0]`，frame 原点为 0,0）的高度，单位 pt。
    let primaryScreenHeight: CGFloat

    init(primaryScreenHeight: CGFloat) {
        self.primaryScreenHeight = primaryScreenHeight
    }

    @MainActor
    static var current: CoordinateConverter {
        CoordinateConverter(primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    func appKitPoint(fromCG point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    func cgRect(fromAppKit rect: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    func appKitRect(fromCG rect: CGRect) -> CGRect {
        // 翻转公式是对称的。
        cgRect(fromAppKit: rect)
    }
}

/// 一块屏幕的几何信息，负责「全局 pt ⇄ 屏幕本地 pt ⇄ 截图像素」的换算。
///
/// - 屏幕本地坐标：原点在该屏左下角，y 向上，单位 pt（与遮罩视图的坐标一致）。
/// - 像素坐标：原点在该屏截图的左上角，y 向下，单位 px（与 `CGImage` 一致）。
struct ScreenGeometry: Equatable {
    /// 屏幕在 AppKit 全局坐标中的 frame（pt）。
    let frame: CGRect
    /// `backingScaleFactor`，pt → px 的倍数。
    let scale: CGFloat

    init(frame: CGRect, scale: CGFloat) {
        self.frame = frame
        self.scale = scale
    }

    @MainActor
    init(screen: NSScreen) {
        self.init(frame: screen.frame, scale: screen.backingScaleFactor)
    }

    /// 屏幕本地坐标下的边界（原点 0,0）。
    var localBounds: CGRect {
        CGRect(origin: .zero, size: frame.size)
    }

    /// 截图的像素尺寸。
    var pixelSize: CGSize {
        CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
    }

    // MARK: 全局 ⇄ 本地

    func localPoint(fromGlobal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }

    func globalPoint(fromLocal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + frame.minX, y: point.y + frame.minY)
    }

    func localRect(fromGlobal rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    func globalRect(fromLocal rect: CGRect) -> CGRect {
        rect.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    // MARK: 本地 ⇄ 像素

    func pixelPoint(fromLocal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: (frame.height - point.y) * scale)
    }

    func localPoint(fromPixel point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale, y: frame.height - point.y / scale)
    }

    /// 本地 pt 矩形 → 像素矩形（未取整）。
    func pixelRect(fromLocal rect: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX * scale,
            y: (frame.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// 本地 pt 矩形 → 整数像素矩形：四条边各自四舍五入到最近的像素，并裁剪到截图范围内。
    func integralPixelRect(fromLocal rect: CGRect) -> CGRect {
        let raw = pixelRect(fromLocal: rect)
        let minX = raw.minX.rounded()
        let minY = raw.minY.rounded()
        let maxX = raw.maxX.rounded()
        let maxY = raw.maxY.rounded()
        let rounded = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return rounded.intersection(CGRect(origin: .zero, size: pixelSize))
    }

    func localRect(fromPixel rect: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX / scale,
            y: frame.height - rect.maxY / scale,
            width: rect.width / scale,
            height: rect.height / scale
        )
    }

    // MARK: CG 全局 → 本地

    /// CG 全局矩形（如 `CGWindowList` 的窗口边界）→ 本屏本地矩形。
    func localRect(fromCG rect: CGRect, converter: CoordinateConverter) -> CGRect {
        localRect(fromGlobal: converter.appKitRect(fromCG: rect))
    }
}

extension NSScreen {
    /// 对应的 `CGDirectDisplayID`，与 `SCDisplay.displayID` 一致。
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
