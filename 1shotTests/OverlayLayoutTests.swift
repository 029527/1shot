import XCTest
@testable import OneShot

final class OverlayLayoutTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    // MARK: 尺寸标签

    func testSizeLabelText() {
        XCTAssertEqual(SizeLabel.text(for: CGSize(width: 1280, height: 720)), "1280 × 720")
    }

    func testSizeLabelAboveSelection() {
        let frame = SizeLabel.frame(labelSize: CGSize(width: 80, height: 20),
                                    selection: CGRect(x: 100, y: 100, width: 300, height: 200), bounds: bounds)
        XCTAssertEqual(frame, CGRect(x: 100, y: 304, width: 80, height: 20))
    }

    func testSizeLabelInsideWhenNoRoomAbove() {
        let frame = SizeLabel.frame(labelSize: CGSize(width: 80, height: 20),
                                    selection: CGRect(x: 100, y: 500, width: 300, height: 300), bounds: bounds)
        XCTAssertEqual(frame, CGRect(x: 104, y: 776, width: 80, height: 20))
    }

    func testSizeLabelStaysInsideHorizontally() {
        let frame = SizeLabel.frame(labelSize: CGSize(width: 80, height: 20),
                                    selection: CGRect(x: 960, y: 100, width: 40, height: 40), bounds: bounds)
        XCTAssertEqual(frame.maxX, 1000)
    }

    // MARK: 放大镜位置

    let size = CGSize(width: 120, height: 170)

    func testMagnifierDefaultsToBottomRight() {
        let frame = MagnifierLayout.frame(cursor: CGPoint(x: 400, y: 400), size: size, bounds: bounds)
        XCTAssertEqual(frame, CGRect(x: 420, y: 210, width: 120, height: 170))
    }

    func testMagnifierFlipsNearRightEdge() {
        let frame = MagnifierLayout.frame(cursor: CGPoint(x: 950, y: 400), size: size, bounds: bounds)
        XCTAssertEqual(frame.maxX, 930)
    }

    func testMagnifierFlipsNearBottomEdge() {
        let frame = MagnifierLayout.frame(cursor: CGPoint(x: 400, y: 50), size: size, bounds: bounds)
        XCTAssertEqual(frame.minY, 70)
    }

    func testMagnifierInBottomRightCorner() {
        let frame = MagnifierLayout.frame(cursor: CGPoint(x: 990, y: 10), size: size, bounds: bounds)
        XCTAssertEqual(frame, CGRect(x: 850, y: 30, width: 120, height: 170))
    }

    // MARK: 取色

    /// 4×4 测试图：左上角像素为红色，其余为蓝色。
    private func makeImage() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 3, width: 1, height: 1)) // CGContext y 向上：y=3 是顶行
        return context.makeImage()!
    }

    func testPixelSamplerReadsCenterColor() throws {
        let image = makeImage()
        let topLeft = try XCTUnwrap(PixelSampler.sample(image, centerPixel: CGPoint(x: 0, y: 0)))
        XCTAssertEqual(topLeft.center, PixelColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(topLeft.image.width, PixelSampler.gridSize)

        let other = try XCTUnwrap(PixelSampler.sample(image, centerPixel: CGPoint(x: 2.7, y: 1.2)))
        XCTAssertEqual(other.center, PixelColor(red: 0, green: 0, blue: 255))
    }

    func testColorFormats() {
        let color = PixelColor(red: 255, green: 16, blue: 0)
        XCTAssertEqual(color.hex, "#FF1000")
        XCTAssertEqual(color.rgb, "RGB(255, 16, 0)")
        var format = ColorFormat.hex
        format.toggle()
        XCTAssertEqual(color.string(in: format), "RGB(255, 16, 0)")
    }

    // MARK: 可识别窗口

    func testSelectableFramesFiltersSystemLayersAndConverts() {
        let converter = CoordinateConverter(primaryScreenHeight: 800)
        let snapshot = WindowListSnapshot(windows: [
            WindowInfo(windowID: 1, ownerPID: 1, ownerName: "A", title: "", layer: 0,
                       frame: CGRect(x: 10, y: 0, width: 100, height: 50), alpha: 1),
            WindowInfo(windowID: 2, ownerPID: 2, ownerName: "Dock", title: "", layer: 20,
                       frame: CGRect(x: 0, y: 0, width: 1000, height: 800), alpha: 1),
            WindowInfo(windowID: 3, ownerPID: 3, ownerName: "Menu", title: "", layer: 25,
                       frame: CGRect(x: 0, y: 0, width: 1000, height: 24), alpha: 1),
            WindowInfo(windowID: 4, ownerPID: 4, ownerName: "B", title: "", layer: 3,
                       frame: CGRect(x: 0, y: 700, width: 200, height: 100), alpha: 1),
        ])
        XCTAssertEqual(snapshot.selectableFrames(converter: converter), [
            CGRect(x: 10, y: 750, width: 100, height: 50),
            CGRect(x: 0, y: 0, width: 200, height: 100),
        ])
    }
}
