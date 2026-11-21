import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// 马赛克取样源：对一块屏幕的定格原图做像素化（`CIPixellate`），按块大小缓存。
final class MosaicSource {
    let image: CGImage
    /// 截图对应的屏幕本地范围（pt），绘制时铺满这个范围。
    let localBounds: CGRect
    let scale: CGFloat

    private var cache: [Int: CGImage] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])

    init(image: CGImage, localBounds: CGRect, scale: CGFloat) {
        self.image = image
        self.localBounds = localBounds
        self.scale = scale
    }

    /// `blockSize` 单位为 pt，内部换算成像素。
    func pixelated(blockSize: CGFloat) -> CGImage? {
        let pixels = max(2, Int((blockSize * scale).rounded()))
        if let cached = cache[pixels] { return cached }

        let input = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(pixels)
        // 网格对齐到图片左下角，不同笔画的方块互相对齐。
        filter.center = CGPoint(x: 0, y: 0)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let result = Self.context.createCGImage(output, from: input.extent,
                                                      format: .RGBA8, colorSpace: image.colorSpace)
        else { return nil }
        cache[pixels] = result
        return result
    }
}
