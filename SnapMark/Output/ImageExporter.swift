import CoreGraphics
import Foundation

/// 按原生像素合成最终图片：截图选区 + 所有标注。
enum ImageExporter {
    /// - Parameters:
    ///   - image: 整块屏幕的定格截图（像素）。
    ///   - geometry: 该屏幕的几何信息。
    ///   - selection: 选区，屏幕本地坐标（pt）。
    ///   - drawOverlays: 在**屏幕本地 pt 坐标系**里绘制标注；上下文已经缩放到像素，
    ///     所以线宽、字号自动乘以 scale，Retina 上不会发糊。绘制已裁剪到选区。
    static func compose(
        image: CGImage,
        geometry: ScreenGeometry,
        selection: CGRect,
        drawOverlays: (CGContext) -> Void = { _ in }
    ) -> CGImage? {
        let pixelRect = geometry.integralPixelRect(fromLocal: selection)
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        guard width > 0, height > 0 else { return nil }

        let space = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // 像素坐标（左上原点）→ 上下文（左下原点）：把整张截图平移到选区对齐的位置。
        context.interpolationQuality = .none
        context.translateBy(x: -pixelRect.minX, y: -(CGFloat(image.height) - pixelRect.maxY))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // 之后的绘制使用屏幕本地 pt 坐标。
        let scale = geometry.frame.width > 0 ? CGFloat(image.width) / geometry.frame.width : geometry.scale
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        context.setShouldAntialias(true)

        context.saveGState()
        context.clip(to: selection)
        drawOverlays(context)
        context.restoreGState()

        return context.makeImage()
    }
}
