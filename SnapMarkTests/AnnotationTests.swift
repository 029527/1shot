import XCTest
@testable import SnapMark

final class ShapeHitTestTests: XCTestCase {
    let red = Palette.colors[0]

    func testRectangleHitsBorderOnly() {
        let shape = RectangleShape(rect: CGRect(x: 0, y: 0, width: 100, height: 50), color: red, lineWidth: 4)
        XCTAssertTrue(shape.hitTest(CGPoint(x: 50, y: 0), tolerance: 2))
        XCTAssertTrue(shape.hitTest(CGPoint(x: 103, y: 25), tolerance: 2))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 50, y: 25), tolerance: 2))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 150, y: 25), tolerance: 2))
    }

    func testEllipseHitsOutline() {
        let shape = EllipseShape(rect: CGRect(x: 0, y: 0, width: 100, height: 100), color: red, lineWidth: 2)
        XCTAssertTrue(shape.hitTest(CGPoint(x: 100, y: 50), tolerance: 2))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 50, y: 50), tolerance: 2))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 2, y: 2), tolerance: 2)) // 外接矩形的角不算
    }

    func testArrowHitsAlongShaft() {
        let shape = ArrowShape(start: .zero, end: CGPoint(x: 100, y: 100), color: red, lineWidth: 4)
        XCTAssertTrue(shape.hitTest(CGPoint(x: 50, y: 50), tolerance: 2))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 80, y: 20), tolerance: 2))
    }

    func testPenHitsStroke() {
        let shape = PenShape(points: [.zero, CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)], color: red, lineWidth: 4)
        XCTAssertTrue(shape.hitTest(CGPoint(x: 70, y: 1), tolerance: 2))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 70, y: 20), tolerance: 2))
    }

    func testTextHitsFrame() {
        let shape = TextShape(topLeft: CGPoint(x: 10, y: 100), text: "你好 SnapMark", color: red, fontSize: 20,
                              maxWidth: 500)
        let frame = shape.frame
        XCTAssertEqual(frame.maxY, 100)
        XCTAssertGreaterThan(frame.width, 40)
        XCTAssertTrue(shape.hitTest(CGPoint(x: frame.midX, y: frame.midY), tolerance: 0))
        XCTAssertFalse(shape.hitTest(CGPoint(x: frame.maxX + 20, y: frame.midY), tolerance: 0))
    }

    func testTextWrapsAtMaxWidth() {
        let wide = TextShape(topLeft: .zero, text: String(repeating: "很长的文字", count: 20), color: red,
                             fontSize: 14, maxWidth: 100)
        XCTAssertLessThanOrEqual(wide.frame.width, 100)
        XCTAssertGreaterThan(wide.frame.height, 40)
    }

    func testMosaicHitsBrushArea() {
        let shape = MosaicShape(points: [.zero, CGPoint(x: 100, y: 0)], brushWidth: 20, blockSize: 8)
        XCTAssertTrue(shape.hitTest(CGPoint(x: 50, y: 8), tolerance: 0))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 50, y: 30), tolerance: 0))
    }
}

final class ShapeBuilderTests: XCTestCase {
    let style = ToolStyle(size: .medium, colorIndex: 0)

    func testSquareConstraintKeepsDirection() {
        XCTAssertEqual(ShapeBuilder.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 130, y: 60), square: true),
                       CGRect(x: 100, y: 60, width: 40, height: 40))
        XCTAssertEqual(ShapeBuilder.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 130, y: 60), square: false),
                       CGRect(x: 100, y: 60, width: 30, height: 40))
    }

    func testArrowSnapsTo45Degrees() {
        let end = ShapeBuilder.snap(from: .zero, to: CGPoint(x: 100, y: 10))
        XCTAssertEqual(end.x, hypot(100, 10), accuracy: 0.001)
        XCTAssertEqual(end.y, 0, accuracy: 0.001)

        let diagonal = ShapeBuilder.snap(from: .zero, to: CGPoint(x: 50, y: 60))
        XCTAssertEqual(diagonal.x, diagonal.y, accuracy: 0.001)
    }

    func testClickProducesNoRectangle() {
        var builder = ShapeBuilder(tool: .rectangle, style: style, start: CGPoint(x: 10, y: 10))
        builder.update(to: CGPoint(x: 11, y: 10.5), constrain: false)
        XCTAssertNil(builder.makeShape())
    }

    func testEllipseWithShiftIsCircle() throws {
        var builder = ShapeBuilder(tool: .ellipse, style: style, start: .zero)
        builder.update(to: CGPoint(x: 80, y: 30), constrain: true)
        let shape = try XCTUnwrap(builder.makeShape() as? EllipseShape)
        XCTAssertEqual(shape.rect.width, shape.rect.height)
        XCTAssertEqual(shape.lineWidth, 4)
    }

    func testPenCollectsPoints() throws {
        var builder = ShapeBuilder(tool: .pen, style: style, start: .zero)
        builder.update(to: CGPoint(x: 0.2, y: 0), constrain: false) // 太近，忽略
        builder.update(to: CGPoint(x: 5, y: 5), constrain: false)
        builder.update(to: CGPoint(x: 10, y: 0), constrain: false)
        let shape = try XCTUnwrap(builder.makeShape() as? PenShape)
        XCTAssertEqual(shape.points.count, 3)
    }

    func testMosaicUsesBrushSizeForLevel() throws {
        var builder = ShapeBuilder(tool: .mosaic, style: ToolStyle(size: .large, colorIndex: 0), start: .zero)
        builder.update(to: CGPoint(x: 30, y: 0), constrain: false)
        let shape = try XCTUnwrap(builder.makeShape() as? MosaicShape)
        XCTAssertEqual(shape.brushWidth, 40)
        XCTAssertEqual(shape.blockSize, 16)
    }

    func testArrowHeadGrowsWithLineWidth() {
        XCTAssertLessThan(ArrowShape.headLength(for: 2), ArrowShape.headLength(for: 8))
    }
}

final class AnnotationDocumentTests: XCTestCase {
    private func rect(_ x: CGFloat) -> RectangleShape {
        RectangleShape(rect: CGRect(x: x, y: 0, width: 10, height: 10), color: Palette.colors[0], lineWidth: 2)
    }

    func testUndoRedo() {
        var document = AnnotationDocument()
        XCTAssertFalse(document.canUndo)
        document.add(rect(0))
        document.add(rect(20))
        XCTAssertEqual(document.shapes.count, 2)

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.shapes.count, 1)
        XCTAssertTrue(document.canRedo)
        XCTAssertTrue(document.redo())
        XCTAssertEqual(document.shapes.count, 2)
        XCTAssertFalse(document.redo())
    }

    func testNewShapeClearsRedo() {
        var document = AnnotationDocument()
        document.add(rect(0))
        document.undo()
        document.add(rect(20))
        XCTAssertFalse(document.canRedo)
        XCTAssertEqual(document.shapes.count, 1)
    }

    func testReplaceAndRemoveAreUndoable() throws {
        var document = AnnotationDocument()
        let original = rect(0)
        document.add(original)
        document.replace(id: original.id, with: rect(50))
        XCTAssertEqual((document.shapes.first as? RectangleShape)?.rect.minX, 50)
        document.undo()
        XCTAssertEqual((document.shapes.first as? RectangleShape)?.rect.minX, 0)
        document.remove(id: original.id)
        XCTAssertTrue(document.isEmpty)
        document.undo()
        XCTAssertEqual(document.shapes.count, 1)
    }

    func testTopmostHit() {
        var document = AnnotationDocument()
        let bottom = RectangleShape(rect: CGRect(x: 0, y: 0, width: 100, height: 100), color: Palette.colors[0], lineWidth: 4)
        let top = RectangleShape(rect: CGRect(x: 0, y: 0, width: 100, height: 50), color: Palette.colors[1], lineWidth: 4)
        document.add(bottom)
        document.add(top)
        XCTAssertEqual(document.shape(at: CGPoint(x: 0, y: 10))?.id, top.id)
        XCTAssertEqual(document.shape(at: CGPoint(x: 50, y: 100))?.id, bottom.id)
        XCTAssertNil(document.shape(at: CGPoint(x: 50, y: 75)))
    }
}

final class AnnotationExportTests: XCTestCase {
    let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
    let selection = CGRect(x: 10, y: 10, width: 60, height: 50)

    func testRectangleExportedAtPixelScale() throws {
        let image = ImageExporterTests.solidImage(width: 200, height: 160, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        // 线宽 4pt → 8px；矩形左边在本地 x=20 → 选区内 10pt → 输出 20px。
        let shape = RectangleShape(rect: CGRect(x: 20, y: 20, width: 30, height: 30), color: Palette.colors[4], lineWidth: 4)
        let output = try XCTUnwrap(ImageExporter.compose(image: image, geometry: geometry, selection: selection) { ctx in
            shape.draw(in: ctx, environment: AnnotationEnvironment())
        })
        XCTAssertEqual(output.width, 120)
        XCTAssertEqual(output.height, 100)
        // 左边线覆盖 x ∈ [16, 24) px；中心 y：本地 35pt → 选区顶部 60pt 往下 25pt → 50px。
        let onLine = ImageExporterTests.pixel(output, x: 20, y: 50)
        XCTAssertEqual(onLine.0, 0)
        XCTAssertEqual(onLine.2, 255) // 蓝色 #007AFF
        let inside = ImageExporterTests.pixel(output, x: 50, y: 50)
        XCTAssertEqual([inside.0, inside.1, inside.2], [255, 255, 255])
        let outsideLine = ImageExporterTests.pixel(output, x: 12, y: 50)
        XCTAssertEqual(outsideLine.0, 255)
    }

    func testMosaicSamplesOriginalImage() throws {
        // 原图左半黑、右半白（像素）。像素化后，涂抹区域的颜色只来自原图。
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 160))
        let image = ctx.makeImage()!

        let source = MosaicSource(image: image, localBounds: geometry.localBounds, scale: 2)
        let pixelated = try XCTUnwrap(source.pixelated(blockSize: 8))
        XCTAssertEqual(pixelated.width, 200)

        // 先画一个红色矩形，再在上面涂马赛克：马赛克区域应显示原图（白），不是红色。
        let red = RectangleShape(rect: CGRect(x: 55, y: 20, width: 10, height: 30), color: Palette.colors[0], lineWidth: 6)
        let mosaic = MosaicShape(points: [CGPoint(x: 60, y: 25), CGPoint(x: 60, y: 45)], brushWidth: 20, blockSize: 8)
        let output = try XCTUnwrap(ImageExporter.compose(image: image, geometry: geometry, selection: selection) { c in
            let environment = AnnotationEnvironment(mosaic: source)
            red.draw(in: c, environment: environment)
            mosaic.draw(in: c, environment: environment)
        })
        // 本地 (60, 35) → 选区内 (50, 25pt 从顶部) → 像素 (100, 50)，位于白色半边的方块里。
        let sample = ImageExporterTests.pixel(output, x: 104, y: 50)
        XCTAssertEqual([sample.0, sample.1, sample.2], [255, 255, 255])
    }

    func testTextIsRendered() throws {
        let image = ImageExporterTests.solidImage(width: 200, height: 160, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let text = TextShape(topLeft: CGPoint(x: 15, y: 55), text: "■■■", color: Palette.colors[6], fontSize: 20, maxWidth: 50)
        let output = try XCTUnwrap(ImageExporter.compose(image: image, geometry: geometry, selection: selection) { ctx in
            text.draw(in: ctx, environment: AnnotationEnvironment())
        })
        // 文字区域里应该有接近黑色的像素。
        var darkPixels = 0
        for x in stride(from: 10, to: 110, by: 2) {
            for y in stride(from: 10, to: 60, by: 2) where ImageExporterTests.pixel(output, x: x, y: y).0 < 60 {
                darkPixels += 1
            }
        }
        XCTAssertGreaterThan(darkPixels, 20)
    }
}

final class ToolStyleTests: XCTestCase {
    func testStyleStorePersistsPerTool() {
        let suite = "SnapMarkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StyleStore(defaults: defaults)

        XCTAssertEqual(store.style(for: .arrow), ToolStyle(size: .medium, colorIndex: 0)) // 默认中号、红色
        store.setStyle(ToolStyle(size: .large, colorIndex: 4), for: .arrow)
        XCTAssertEqual(StyleStore(defaults: defaults).style(for: .arrow), ToolStyle(size: .large, colorIndex: 4))
        XCTAssertEqual(store.style(for: .pen), ToolStyle(size: .medium, colorIndex: 0))
    }

    func testToolShortcuts() {
        XCTAssertEqual(AnnotationTool(shortcut: "r"), .rectangle)
        XCTAssertEqual(AnnotationTool(shortcut: "O"), .ellipse)
        XCTAssertEqual(AnnotationTool(shortcut: "m"), .mosaic)
        XCTAssertNil(AnnotationTool(shortcut: "c"))
    }

    func testSizes() {
        XCTAssertEqual(ToolStyle(size: .small, colorIndex: 0).lineWidth, 2)
        XCTAssertEqual(ToolStyle(size: .large, colorIndex: 0).fontSize, 28)
        XCTAssertEqual(Palette.colors.count, 8)
    }
}

final class CounterAndHighlighterTests: XCTestCase {
    let style = ToolStyle(size: .medium, colorIndex: 0)

    func testCounterPlacedAtClickWithNumber() throws {
        var builder = ShapeBuilder(tool: .counter, style: style, start: CGPoint(x: 50, y: 50), counterNumber: 3)
        builder.update(to: CGPoint(x: 60, y: 55), constrain: false)
        let shape = try XCTUnwrap(builder.makeShape() as? CounterShape)
        XCTAssertEqual(shape.number, 3)
        XCTAssertEqual(shape.center, CGPoint(x: 60, y: 55))
        XCTAssertEqual(shape.diameter, 26)
        XCTAssertTrue(shape.hitTest(CGPoint(x: 70, y: 55), tolerance: 0))
        XCTAssertFalse(shape.hitTest(CGPoint(x: 80, y: 55), tolerance: 0))
    }

    func testCounterTextColorContrast() {
        let onRed = CounterShape(center: .zero, number: 1, color: Palette.colors[0], diameter: 20)
        let onYellow = CounterShape(center: .zero, number: 1, color: Palette.colors[2], diameter: 20)
        let onWhite = CounterShape(center: .zero, number: 1, color: Palette.colors[7], diameter: 20)
        XCTAssertEqual(onRed.textColor, .white)
        XCTAssertEqual(onYellow.textColor, .black)
        XCTAssertEqual(onWhite.textColor, .black)
    }

    func testHighlighterShiftDrawsStraightLine() throws {
        var builder = ShapeBuilder(tool: .highlighter, style: style, start: .zero)
        builder.update(to: CGPoint(x: 30, y: 5), constrain: false)
        builder.update(to: CGPoint(x: 100, y: 8), constrain: true)
        let shape = try XCTUnwrap(builder.makeShape() as? HighlighterShape)
        XCTAssertEqual(shape.points.count, 2)
        XCTAssertEqual(shape.points[1].y, 0, accuracy: 0.001)
        XCTAssertEqual(shape.lineWidth, 18)
    }

    func testHighlighterDefaultsToYellow() {
        let suite = "SnapMarkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(StyleStore(defaults: defaults).style(for: .highlighter).colorIndex, 2)
        XCTAssertEqual(AnnotationTool(shortcut: "h"), .highlighter)
        XCTAssertEqual(AnnotationTool(shortcut: "N"), .counter)
    }

    func testHighlighterIsTranslucent() throws {
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 1)
        let image = ImageExporterTests.solidImage(width: 100, height: 80, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        // 同一条笔画来回经过同一点，颜色也不应叠深。
        let shape = HighlighterShape(points: [CGPoint(x: 10, y: 40), CGPoint(x: 90, y: 40), CGPoint(x: 10, y: 40)],
                                     color: Palette.colors[4], lineWidth: 10)
        let output = try XCTUnwrap(ImageExporter.compose(image: image, geometry: geometry,
                                                         selection: geometry.localBounds) { ctx in
            shape.draw(in: ctx, environment: AnnotationEnvironment())
        })
        let pixel = ImageExporterTests.pixel(output, x: 50, y: 40)
        // 白底 + 40% 蓝（#007AFF）：红通道约 153，而不是 0（不透明）或更低（叠加）。
        XCTAssertEqual(Double(pixel.0), 153, accuracy: 6)
    }
}
