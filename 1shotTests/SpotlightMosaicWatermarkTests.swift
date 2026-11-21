import AppKit
import XCTest
@testable import OneShot

/// 白底画布上执行绘制，返回像素读取函数（坐标 y 向上，1pt = 1px）。
private func render(width: Int = 200, height: Int = 100, _ draw: (CGContext) -> Void) -> (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
    }
    return { x, y in
        let i = ((height - 1 - y) * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }
}

private func stripes(width: Int = 200, height: Int = 100) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in stride(from: 0, to: width, by: 2) {
        context.setFillColor(x % 4 == 0 ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
                                        : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 2, height: height))
    }
    return context.makeImage()!
}

final class SpotlightTests: XCTestCase {
    func testOutsideDimmedInsideUntouched() {
        let spotlight = SpotlightShape(rect: CGRect(x: 20, y: 20, width: 40, height: 40), kind: .rectangle, opacity: 0.5)
        let pixel = render { context in
            var environment = AnnotationEnvironment()
            environment.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
            AnnotationRenderer.draw([spotlight], in: context, environment: environment)
        }
        XCTAssertEqual(Int(pixel(40, 40).r), 255, accuracy: 1, "高亮区域内保持原样")
        XCTAssertEqual(Int(pixel(150, 50).r), 128, accuracy: 2, "框外按 50% 变暗")
    }

    func testTwoSpotlightsDimOnlyOnce() {
        let a = SpotlightShape(rect: CGRect(x: 10, y: 10, width: 30, height: 30), kind: .rectangle, opacity: 0.5)
        let b = SpotlightShape(rect: CGRect(x: 100, y: 10, width: 30, height: 30), kind: .ellipse, opacity: 0.5)
        let pixel = render { context in
            var environment = AnnotationEnvironment()
            environment.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
            AnnotationRenderer.draw([a, b], in: context, environment: environment)
        }
        XCTAssertEqual(Int(pixel(25, 25).r), 255, accuracy: 1, "第一个高亮不会被第二个压暗")
        XCTAssertEqual(Int(pixel(115, 25).r), 255, accuracy: 1)
        XCTAssertEqual(Int(pixel(70, 80).r), 128, accuracy: 2, "框外只暗一次")
        XCTAssertGreaterThan(pixel(101, 11).r, 200 - 80, "椭圆的角落在框外，会变暗")
    }

    func testMosaicOutsideSpotlightIsDimmedToo() {
        let source = MosaicSource(image: stripes(), localBounds: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 1)
        let mosaic = MosaicShape(region: .rect(CGRect(x: 120, y: 0, width: 80, height: 100)), effect: .blur, amount: 0.5)
        let spotlight = SpotlightShape(rect: CGRect(x: 0, y: 0, width: 60, height: 100), kind: .rectangle, opacity: 0.5)
        let blurredOnly = render { context in
            AnnotationRenderer.draw([mosaic], in: context, environment: AnnotationEnvironment(mosaic: source))
        }
        let pixel = render { context in
            var environment = AnnotationEnvironment(mosaic: source)
            environment.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
            // 先加高亮、后加马赛克：马赛克仍然要被压暗。
            AnnotationRenderer.draw([spotlight, mosaic], in: context, environment: environment)
        }
        XCTAssertLessThan(Int(pixel(160, 50).r), Int(blurredOnly(160, 50).r) - 40, "框外的马赛克也要变暗")
    }

    func testBuilderMakesSpotlightWithOptions() throws {
        var style = ToolStyle(size: .medium, colorIndex: 0)
        style.options.spotlightShape = .roundedRectangle
        style.options.amount = 0.7
        var builder = ShapeBuilder(tool: .spotlight, style: style, start: CGPoint(x: 10, y: 10))
        builder.update(to: CGPoint(x: 60, y: 40), constrain: false)
        let shape = try XCTUnwrap(builder.makeShape() as? SpotlightShape)
        XCTAssertEqual(shape.rect, CGRect(x: 10, y: 10, width: 50, height: 30))
        XCTAssertEqual(shape.kind, .roundedRectangle)
        XCTAssertEqual(shape.opacity, 0.7)
        XCTAssertEqual(shape.style.options.amount, 0.7)
        XCTAssertEqual(shape.editHandles.count, 8)
    }
}

final class MosaicOptionTests: XCTestCase {
    func testAreaModeMakesRectRegion() throws {
        var style = ToolStyle(size: .small, colorIndex: 0)
        style.options.mosaicMode = .area
        style.options.mosaicEffect = .blur
        var builder = ShapeBuilder(tool: .mosaic, style: style, start: CGPoint(x: 5, y: 5))
        builder.update(to: CGPoint(x: 45, y: 25), constrain: false)
        let shape = try XCTUnwrap(builder.makeShape() as? MosaicShape)
        guard case .rect(let rect) = shape.region else { return XCTFail("框选方式应生成矩形区域") }
        XCTAssertEqual(rect, CGRect(x: 5, y: 5, width: 40, height: 20))
        XCTAssertEqual(shape.effect, .blur)
        XCTAssertEqual(shape.style.options.mosaicMode, .area)
        XCTAssertEqual(shape.editHandles.count, 8, "框选的马赛克可以拖控制点调整")
    }

    func testAmountMapsToBlockAndBlur() {
        XCTAssertEqual(MosaicShape.blockSize(amount: 0), 4)
        XCTAssertEqual(MosaicShape.blockSize(amount: 1), 28)
        XCTAssertEqual(MosaicShape.blurRadius(amount: 0), 2)
        XCTAssertEqual(MosaicShape.blurRadius(amount: 1), 20)
        XCTAssertEqual(MosaicShape(points: [], brushWidth: 20, blockSize: 8).blockSize, 8, "旧接口换算后不变")
    }

    func testBlurSmoothsStripes() {
        let source = MosaicSource(image: stripes(), localBounds: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 1)
        let shape = MosaicShape(region: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), effect: .blur, amount: 0.5)
        let pixel = render { context in
            AnnotationRenderer.draw([shape], in: context, environment: AnnotationEnvironment(mosaic: source))
        }
        // 黑白相间 2px 条纹模糊后变成均匀的灰（Core Image 在线性空间混合，sRGB 下约 188）；
        // 相邻像素不再一黑一白。区域外不受影响（白底）。
        let a = Int(pixel(50, 50).r), b = Int(pixel(52, 50).r)
        XCTAssertEqual(a, b, accuracy: 6)
        XCTAssertGreaterThan(a, 120)
        XCTAssertLessThan(a, 220)
        XCTAssertEqual(pixel(150, 50).r, 255)
    }
}

@MainActor
final class WatermarkTests: XCTestCase {
    func testWatermarkDrawsTiledText() {
        let watermark = WatermarkShape(text: "1shot", color: Palette.colors[6], opacity: 0.5,
                                       area: CGRect(x: 0, y: 0, width: 200, height: 100))
        let pixel = render { context in
            AnnotationRenderer.draw([watermark], in: context, environment: AnnotationEnvironment())
        }
        var darker = 0
        for x in stride(from: 0, to: 200, by: 2) {
            for y in stride(from: 0, to: 100, by: 2) where pixel(x, y).r < 220 { darker += 1 }
        }
        XCTAssertGreaterThan(darker, 30, "平铺的文字应遍布整块区域")
        XCTAssertFalse(watermark.hitTest(CGPoint(x: 50, y: 50), tolerance: 4), "水印不挡住点选")
    }

    func testControllerAppliesWatermarkAsOneUndoStep() throws {
        let testDefaults = TestDefaults("WatermarkTests")
        let defaults = testDefaults.defaults
        defer { testDefaults.cleanUp() }
        let controller = AnnotationController(styles: StyleStore(defaults: defaults))
        let host = TestHost(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        controller.attach(to: host, source: AnnotationSource(id: 1, image: stripes(), bounds: host.bounds, scale: 1),
                          selection: CGRect(x: 10, y: 10, width: 200, height: 100))

        controller.toggle(.watermark)
        XCTAssertNil(controller.currentWatermark, "没有文字时不加水印")
        var options = ToolOptions()
        options.amount = 0.3
        options.text = "机密"
        controller.stylePanel(controller.stylePanel, didChange: options)
        options.text = "机密文件"
        controller.stylePanel(controller.stylePanel, didChange: options)
        let watermark = try XCTUnwrap(controller.currentWatermark)
        XCTAssertEqual(watermark.text, "机密文件")
        XCTAssertEqual(watermark.area, CGRect(x: 10, y: 10, width: 200, height: 100))

        controller.toggle(.watermark) // 离开水印工具：合并成一步撤销
        XCTAssertTrue(controller.document.canUndo)
        controller.undo()
        XCTAssertNil(controller.currentWatermark, "一次撤销去掉整个水印")
        XCTAssertFalse(controller.document.canUndo)

        options.text = String(repeating: "长", count: 30)
        controller.toggle(.watermark)
        controller.stylePanel(controller.stylePanel, didChange: options)
        XCTAssertEqual(controller.currentWatermark?.text.count, WatermarkShape.maxLength)
    }

    func testStyleStoreRoundTripsOptions() {
        let testDefaults = TestDefaults("StyleStoreOptions")
        let defaults = testDefaults.defaults
        defer { testDefaults.cleanUp() }
        let store = StyleStore(defaults: defaults)
        XCTAssertEqual(store.style(for: .watermark).options.amount, 0.3)
        XCTAssertEqual(store.style(for: .watermark).colorIndex, 6)
        XCTAssertEqual(store.style(for: .spotlight).options.amount, 0.5)

        var mosaic = store.style(for: .mosaic)
        mosaic.options.mosaicEffect = .blur
        mosaic.options.mosaicMode = .area
        mosaic.options.amount = 0.8
        store.setStyle(mosaic, for: .mosaic)
        XCTAssertEqual(store.style(for: .mosaic).options, mosaic.options)

        var watermark = store.style(for: .watermark)
        watermark.options.text = "内部资料"
        store.setStyle(watermark, for: .watermark)
        XCTAssertEqual(store.style(for: .watermark).options.text, "内部资料")
    }

    func testStylePanelShowsControlsPerTool() {
        let panel = StylePanelView(frame: .zero)
        panel.configure(tool: .watermark, style: ToolStyle(size: .medium, colorIndex: 6))
        XCTAssertFalse(panel.textField.isHidden)
        let watermarkWidth = panel.frame.width

        var mosaic = ToolStyle(size: .medium, colorIndex: 0)
        mosaic.options.mosaicMode = .area
        panel.configure(tool: .mosaic, style: mosaic)
        XCTAssertTrue(panel.textField.isHidden)
        let areaWidth = panel.frame.width
        mosaic.options.mosaicMode = .brush
        panel.configure(tool: .mosaic, style: mosaic)
        XCTAssertGreaterThan(panel.frame.width, areaWidth, "画笔方式多出粗细按钮")

        panel.configure(tool: .rectangle, style: ToolStyle(size: .medium, colorIndex: 0))
        XCTAssertLessThan(panel.frame.width, watermarkWidth)
    }
}

/// 测试用的标注宿主。
private final class TestHost: NSView, AnnotationHost {
    let annotationHost = PassthroughView()
    let controlsHost = PassthroughView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        for host in [annotationHost, controlsHost] {
            host.frame = bounds
            addSubview(host)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
