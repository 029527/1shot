import XCTest
@testable import OneShot

final class FileNamerTests: XCTestCase {
    let utc8 = TimeZone(secondsFromGMT: 8 * 3600)!
    /// 2026-11-21 14:03:22 +08:00
    let date = Date(timeIntervalSince1970: 1_795_241_002)
    let directory = URL(fileURLWithPath: "/tmp/截图", isDirectory: true)

    func testFileName() {
        XCTAssertEqual(FileNamer.fileName(for: date, fileExtension: "png", timeZone: utc8), "截图 2026-11-21 14.03.22.png")
    }

    func testUniqueURLWithoutConflict() {
        let url = FileNamer.uniqueURL(in: directory, date: date, fileExtension: "png", timeZone: utc8) { _ in false }
        XCTAssertEqual(url.lastPathComponent, "截图 2026-11-21 14.03.22.png")
        XCTAssertEqual(url.deletingLastPathComponent().path, directory.path)
    }

    func testUniqueURLAppendsCounter() {
        let taken: Set<String> = ["截图 2026-11-21 14.03.22.jpg", "截图 2026-11-21 14.03.22 (1).jpg"]
        let url = FileNamer.uniqueURL(in: directory, date: date, fileExtension: "jpg", timeZone: utc8) {
            taken.contains($0.lastPathComponent)
        }
        XCTAssertEqual(url.lastPathComponent, "截图 2026-11-21 14.03.22 (2).jpg")
    }

    func testSaveWritesFileAndDeduplicates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = ImageExporterTests.solidImage(width: 4, height: 4, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        let first = try FileSaver.save(image, format: .png, directory: dir, date: date)
        let second = try FileSaver.save(image, format: .png, directory: dir, date: date)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.hasSuffix(" (1).png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))

        let jpg = try FileSaver.save(image, format: .jpg, directory: dir, date: date)
        XCTAssertEqual(jpg.pathExtension, "jpg")
        XCTAssertNotNil(NSImage(contentsOf: jpg))
    }

    func testImageFormatFromExtension() {
        XCTAssertEqual(ImageFormat(fileExtension: "JPEG"), .jpg)
        XCTAssertEqual(ImageFormat(fileExtension: "jpg"), .jpg)
        XCTAssertEqual(ImageFormat(fileExtension: "png"), .png)
        XCTAssertEqual(ImageFormat(fileExtension: ""), .png)
    }

    func testToastMessages() {
        XCTAssertEqual(OutputPipeline.toastMessage(copied: true, saved: true), "已复制并保存")
        XCTAssertEqual(OutputPipeline.toastMessage(copied: true, saved: false), "已复制")
        XCTAssertEqual(OutputPipeline.toastMessage(copied: false, saved: true), "已保存")
        XCTAssertNil(OutputPipeline.toastMessage(copied: false, saved: false))
    }
}

final class ToolbarLayoutTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 300, height: 40)

    func testBelowRightAligned() {
        let layout = ToolbarLayout.frame(size: size, selection: CGRect(x: 200, y: 300, width: 400, height: 300), bounds: bounds)
        XCTAssertEqual(layout.placement, .below)
        XCTAssertEqual(layout.frame, CGRect(x: 300, y: 252, width: 300, height: 40))
    }

    func testAboveWhenNoRoomBelow() {
        let layout = ToolbarLayout.frame(size: size, selection: CGRect(x: 200, y: 20, width: 400, height: 300), bounds: bounds)
        XCTAssertEqual(layout.placement, .above)
        XCTAssertEqual(layout.frame, CGRect(x: 300, y: 328, width: 300, height: 40))
    }

    func testInsideWhenNoRoomEitherSide() {
        let layout = ToolbarLayout.frame(size: size, selection: CGRect(x: 0, y: 0, width: 1000, height: 800), bounds: bounds)
        XCTAssertEqual(layout.placement, .inside)
        XCTAssertEqual(layout.frame, CGRect(x: 692, y: 8, width: 300, height: 40))
    }

    func testClampedHorizontallyForNarrowSelectionAtLeftEdge() {
        let layout = ToolbarLayout.frame(size: size, selection: CGRect(x: 0, y: 300, width: 50, height: 50), bounds: bounds)
        XCTAssertEqual(layout.frame.minX, 0)
    }

    func testStylePanelBelowToolbar() {
        let toolbar = CGRect(x: 300, y: 252, width: 300, height: 40)
        let frame = ToolbarLayout.stylePanelFrame(size: CGSize(width: 200, height: 30), toolbar: toolbar,
                                                  placement: .below, bounds: bounds)
        XCTAssertEqual(frame, CGRect(x: 300, y: 216, width: 200, height: 30))
    }

    func testStylePanelFlipsWhenNoRoomBelow() {
        let toolbar = CGRect(x: 300, y: 10, width: 300, height: 40)
        let frame = ToolbarLayout.stylePanelFrame(size: CGSize(width: 200, height: 30), toolbar: toolbar,
                                                  placement: .below, bounds: bounds)
        XCTAssertEqual(frame.minY, 56)
    }

    func testStylePanelAboveToolbarWhenInside() {
        let toolbar = CGRect(x: 692, y: 8, width: 300, height: 40)
        let frame = ToolbarLayout.stylePanelFrame(size: CGSize(width: 200, height: 30), toolbar: toolbar,
                                                  placement: .inside, bounds: bounds)
        XCTAssertEqual(frame, CGRect(x: 692, y: 54, width: 200, height: 30))
    }
}

final class ImageExporterTests: XCTestCase {
    static func solidImage(width: Int, height: Int, color: CGColor) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// 读取图片某像素（左上角原点）的 RGB。
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * image.width * 4 + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

    func testOutputSizeIsSelectionTimesScale() throws {
        // 100×80 pt 的 Retina 屏，截图 200×160 px。
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
        let image = Self.solidImage(width: 200, height: 160, color: blue)
        let output = try XCTUnwrap(ImageExporter.compose(image: image, geometry: geometry,
                                                         selection: CGRect(x: 10, y: 10, width: 50, height: 40)))
        XCTAssertEqual(output.width, 100)
        XCTAssertEqual(output.height, 80)
    }

    func testCropsTheRightRegion() throws {
        // 截图左上角 20×20 px 是红色，其余蓝色。选区取屏幕左上角 10×10 pt。
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(blue)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 140, width: 20, height: 20)) // CGContext y 向上：顶部 20 行
        let image = context.makeImage()!

        let output = try XCTUnwrap(ImageExporter.compose(image: image, geometry: geometry,
                                                         selection: CGRect(x: 0, y: 70, width: 10, height: 10)))
        XCTAssertEqual(output.width, 20)
        let (r, g, b) = Self.pixel(output, x: 10, y: 10)
        XCTAssertEqual([r, g, b], [255, 0, 0])
    }

    func testDrawsOverlaysAtPixelScale() throws {
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
        let image = Self.solidImage(width: 200, height: 160, color: blue)
        let selection = CGRect(x: 10, y: 10, width: 50, height: 40)
        let output = try XCTUnwrap(ImageExporter.compose(image: image, geometry: geometry, selection: selection) { ctx in
            // 在选区左下角画 10×10 pt 的红块（本地 pt 坐标）。
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 10, y: 10, width: 10, height: 10))
            // 选区外的绘制应被裁掉。
            ctx.fill(CGRect(x: 0, y: 0, width: 5, height: 5))
        })
        // 输出 100×80 px：左下角 20×20 px 为红，即左上原点下的 y ∈ [60, 80)。
        XCTAssertEqual(Self.pixel(output, x: 5, y: 75).0, 255)
        XCTAssertEqual(Self.pixel(output, x: 19, y: 60).0, 255)
        XCTAssertEqual(Self.pixel(output, x: 21, y: 75).0, 0)   // 右边一点就是蓝色
        XCTAssertEqual(Self.pixel(output, x: 5, y: 58).2, 255)  // 上边一点就是蓝色
        XCTAssertEqual(Self.pixel(output, x: 50, y: 40).2, 255)
    }

    func testEmptySelectionReturnsNil() {
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
        let image = Self.solidImage(width: 200, height: 160, color: blue)
        XCTAssertNil(ImageExporter.compose(image: image, geometry: geometry, selection: .zero))
    }
}
