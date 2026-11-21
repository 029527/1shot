import AppKit
import XCTest
@testable import OneShot

/// 选着工具时点中同类的已有标注：选中再编辑（截图遮罩和贴图共用 AnnotationController）。
@MainActor
final class ReselectTests: XCTestCase {
    private var testDefaults: TestDefaults!
    private var controller: AnnotationController!
    private var host: ReselectHost!

    override func setUp() {
        super.setUp()
        testDefaults = TestDefaults()
        controller = AnnotationController(styles: StyleStore(defaults: testDefaults.defaults))
        host = ReselectHost(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        controller.attach(to: host, source: AnnotationSource(id: 1, image: context.makeImage()!, bounds: host.bounds, scale: 1),
                          selection: host.bounds)
    }

    override func tearDown() {
        controller.reset()
        testDefaults.cleanUp()
        super.tearDown()
    }

    private func drag(from a: CGPoint, to b: CGPoint) {
        _ = controller.mouseDown(at: a, constrain: false)
        if controller.isDrawing {
            _ = controller.mouseDragged(to: b, constrain: false)
            _ = controller.mouseUp(at: b, constrain: false)
        } else if controller.isEditingShape {
            _ = controller.editDragged(to: b, constrain: false)
            _ = controller.editEnded()
        }
    }

    func testClickingExistingShapeWithSameToolSelectsAndMovesIt() throws {
        controller.toggle(.rectangle)
        drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 100))
        XCTAssertEqual(controller.document.shapes.count, 1)

        // 点在矩形边上拖动：移动它，而不是再画一个。
        drag(from: CGPoint(x: 20, y: 60), to: CGPoint(x: 50, y: 60))
        XCTAssertEqual(controller.document.shapes.count, 1, "没有新增图形")
        let moved = try XCTUnwrap(controller.document.shapes.first as? RectangleShape)
        XCTAssertEqual(moved.rect.origin, CGPoint(x: 50, y: 20))
        XCTAssertNotNil(controller.selectedShape, "移动后保持选中")
        XCTAssertEqual(controller.tool, .rectangle, "工具保持选中")

        // 选中后改颜色：作用于这个矩形。
        controller.stylePanel(controller.stylePanel, didSelectColorAt: 4)
        XCTAssertEqual((controller.document.shapes.first as? RectangleShape)?.color, Palette.colors[4])

        // 在空白处拖动：取消选中并画新的。
        drag(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 260, y: 190))
        XCTAssertEqual(controller.document.shapes.count, 2)
        XCTAssertNil(controller.selectedShape)
        XCTAssertEqual((controller.document.shapes.last as? RectangleShape)?.color, Palette.colors[4],
                       "新画的沿用刚才改的颜色")
    }

    func testDifferentToolStillDrawsOverExistingShape() {
        controller.toggle(.rectangle)
        drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 100))
        controller.toggle(.arrow)
        drag(from: CGPoint(x: 20, y: 60), to: CGPoint(x: 80, y: 60))
        XCTAssertEqual(controller.document.shapes.count, 2, "箭头从矩形边上开始画，不会选中矩形")
    }

    func testSelectedShapeHandleResizesWithToolActive() throws {
        controller.toggle(.spotlight)
        drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 100))
        // 点在高亮区域内部：选中。
        _ = controller.mouseDown(at: CGPoint(x: 60, y: 60), constrain: false)
        _ = controller.editEnded()
        XCTAssertTrue(controller.selectedShape is SpotlightShape)
        // 拖右上角控制点。
        drag(from: CGPoint(x: 120, y: 100), to: CGPoint(x: 150, y: 130))
        let spotlight = try XCTUnwrap(controller.document.shapes.first as? SpotlightShape)
        XCTAssertEqual(spotlight.rect, CGRect(x: 20, y: 20, width: 130, height: 110))
        XCTAssertEqual(controller.document.shapes.count, 1)
    }

    func testMosaicBrushKeepsPaintingButAreaIsSelectable() {
        controller.toggle(.mosaic)
        drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 120, y: 20))
        drag(from: CGPoint(x: 60, y: 20), to: CGPoint(x: 60, y: 80))
        XCTAssertEqual(controller.document.shapes.count, 2, "画笔方式在已有马赛克上继续涂抹")

        var options = ToolOptions()
        options.mosaicMode = .area
        controller.stylePanel(controller.stylePanel, didChange: options)
        drag(from: CGPoint(x: 150, y: 100), to: CGPoint(x: 250, y: 180))
        XCTAssertEqual(controller.document.shapes.count, 3)
        drag(from: CGPoint(x: 200, y: 140), to: CGPoint(x: 210, y: 140))
        XCTAssertEqual(controller.document.shapes.count, 3, "框选的马赛克可以点中移动")
    }

    func testTextToolClickOnTextReedits() throws {
        let text = TextShape(topLeft: CGPoint(x: 30, y: 150), text: "你好", color: Palette.colors[0], fontSize: 20, maxWidth: 200)
        controller.toggle(.text)
        // 直接放一段文字进文档（模拟之前输入过）。
        controller.debugAppend(text)
        XCTAssertTrue(controller.mouseDown(at: CGPoint(x: 40, y: 140), constrain: false))
        XCTAssertTrue(controller.isEditingText, "选着文字工具单击已有文字：重新编辑")
        XCTAssertTrue(controller.document.shapes.isEmpty, "编辑期间原文字从文档里拿出来")
        controller.finishTextEditing()
        XCTAssertEqual(controller.document.shapes.count, 1)
    }

    func testWatermarkToolShowsExistingWatermark() throws {
        controller.toggle(.watermark)
        var options = ToolOptions()
        options.text = "机密"
        options.amount = 0.6
        controller.stylePanel(controller.stylePanel, didChange: options)
        controller.stylePanel(controller.stylePanel, didSelectColorAt: 4)
        controller.toggle(.watermark) // 离开

        // 改掉存储的水印样式（比如在别的截图里用过别的文字），再回来：应显示现有水印。
        var other = StyleStore(defaults: testDefaults.defaults).style(for: .watermark)
        other.options.text = "别的文字"
        StyleStore(defaults: testDefaults.defaults).setStyle(other, for: .watermark)

        controller.toggle(.watermark)
        let style = try XCTUnwrap(controller.currentStyle)
        XCTAssertEqual(style.options.text, "机密")
        XCTAssertEqual(style.options.amount, 0.6)
        XCTAssertEqual(style.colorIndex, 4)
        XCTAssertEqual(controller.currentWatermark?.text, "机密", "回显时不改动现有水印")
    }
}

private final class ReselectHost: NSView, AnnotationHost {
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
