import CoreGraphics
import Foundation

/// 给截图加圆角和投影：输出一张更大的图片，四周留出透明边放阴影。
enum ImageDecorator {
    /// 阴影不透明度。
    static let shadowOpacity: CGFloat = 0.35
    /// 阴影向下偏移 = 阴影长度 × 这个比例。
    static let shadowOffsetRatio: CGFloat = 0.3

    /// 四周透明边的宽度（px）。
    static func margin(shadowLength: Double, scale: CGFloat) -> Int {
        guard shadowLength > 0 else { return 0 }
        let blur = CGFloat(shadowLength) * scale
        return Int((blur * (1 + shadowOffsetRatio)).rounded(.up))
    }

    /// 圆角半径（px）。
    static func cornerRadius(width: Int, height: Int, ratio: Double) -> CGFloat {
        CGFloat(min(width, height)) * CGFloat(min(max(ratio, 0), 0.5))
    }

    /// `scale`：截图所在屏幕的 scale（阴影长度按 pt 计）。设置无效时原样返回。
    static func apply(_ image: CGImage, decoration: ImageDecoration, scale: CGFloat) -> CGImage {
        guard decoration.isEffective else { return image }
        let width = image.width, height = image.height
        let margin = margin(shadowLength: decoration.shadowLength, scale: scale)
        let canvasWidth = width + margin * 2
        let canvasHeight = height + margin * 2

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .none

        let rect = CGRect(x: margin, y: margin, width: width, height: height)
        let radius = cornerRadius(width: width, height: height, ratio: decoration.cornerRatio)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if decoration.shadowLength > 0 {
            let blur = CGFloat(decoration.shadowLength) * scale
            // 位图上下文的 y 轴向上：负值表示阴影向下。
            context.setShadow(offset: CGSize(width: 0, height: -blur * shadowOffsetRatio), blur: blur,
                              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shadowOpacity))
        }
        // 透明层：先把裁好圆角的图片画进层里，结束时整层一起投影，边缘没有杂色。
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(path)
        context.clip()
        context.draw(image, in: rect)
        context.endTransparencyLayer()

        return context.makeImage() ?? image
    }
}
