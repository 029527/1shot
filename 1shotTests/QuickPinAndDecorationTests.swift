import AppKit
import ImageIO
import XCTest
@testable import OneShot

/// 读取像素（RGBA，premultiplied，按从上到下的行序）。
private struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    /// (x, y)：y 从上往下数。
    func rgba(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }
}

private func solidImage(width: Int, height: Int, red: CGFloat = 0.2, green: CGFloat = 0.5, blue: CGFloat = 0.9) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

final class ImageDecoratorTests: XCTestCase {
    func testDisabledReturnsSameImage() {
        let image = solidImage(width: 40, height: 30)
        let off = ImageDecoration(isEnabled: false, cornerRatio: 0.1, shadowLength: 20)
        XCTAssertTrue(ImageDecorator.apply(image, decoration: off, scale: 2) === image)
        let zero = ImageDecoration(isEnabled: true, cornerRatio: 0, shadowLength: 0)
        XCTAssertFalse(zero.isEffective)
        XCTAssertTrue(ImageDecorator.apply(image, decoration: zero, scale: 2) === image)
    }

    func testCornerOnlyKeepsSizeAndClearsCorners() {
        let image = solidImage(width: 200, height: 100)
        let result = ImageDecorator.apply(image, decoration: .init(isEnabled: true, cornerRatio: 0.2, shadowLength: 0),
                                          scale: 2)
        XCTAssertEqual(result.width, 200)
        XCTAssertEqual(result.height, 100)
        let pixels = Pixels(result)
        XCTAssertEqual(pixels.rgba(0, 0).a, 0, "左上角在圆角外，应透明")
        XCTAssertEqual(pixels.rgba(199, 99).a, 0, "右下角在圆角外，应透明")
        let center = pixels.rgba(100, 50)
        XCTAssertEqual(center.a, 255)
        XCTAssertEqual(Int(center.b), 230, accuracy: 2)
        // 边的中点不受圆角影响。
        XCTAssertEqual(pixels.rgba(100, 0).a, 255)
    }

    func testShadowAddsTransparentMarginBelowHeavier() {
        let image = solidImage(width: 120, height: 80)
        let decoration = ImageDecoration(isEnabled: true, cornerRatio: 0.05, shadowLength: 10)
        let scale: CGFloat = 2
        let result = ImageDecorator.apply(image, decoration: decoration, scale: scale)
        let margin = ImageDecorator.margin(shadowLength: 10, scale: scale)
        XCTAssertEqual(margin, 26)
        XCTAssertEqual(result.width, 120 + margin * 2)
        XCTAssertEqual(result.height, 80 + margin * 2)

        let pixels = Pixels(result)
        // 最外圈几乎完全透明。
        for x in stride(from: 0, to: result.width, by: 7) {
            XCTAssertLessThan(pixels.rgba(x, 0).a, 8)
            XCTAssertLessThan(pixels.rgba(x, result.height - 1).a, 16)
        }
        // 阴影向下：图片下方比上方更暗。
        let midX = result.width / 2
        let above = pixels.rgba(midX, margin - 6).a
        let below = pixels.rgba(midX, margin + 80 + 6).a
        XCTAssertGreaterThan(below, above)
        XCTAssertGreaterThan(below, 10)
        // 图片本身保持原色、不透明。
        let center = pixels.rgba(midX, margin + 40)
        XCTAssertEqual(center.a, 255)
        XCTAssertEqual(Int(center.r), 51, accuracy: 2)
    }

    func testCornerRadiusUsesShortSide() {
        XCTAssertEqual(ImageDecorator.cornerRadius(width: 1000, height: 200, ratio: 0.1), 20)
        XCTAssertEqual(ImageDecorator.cornerRadius(width: 100, height: 100, ratio: 0.9), 50)
    }

    func testJPEGFlattensTransparencyOnWhite() throws {
        let image = solidImage(width: 60, height: 60)
        let decorated = ImageDecorator.apply(image, decoration: .init(isEnabled: true, cornerRatio: 0.3, shadowLength: 0),
                                             scale: 1)
        let data = try XCTUnwrap(ImageEncoder.data(for: decorated, format: .jpg))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let corner = Pixels(decoded).rgba(0, 0)
        XCTAssertGreaterThan(corner.r, 240, "透明角应变成白色而不是黑色")
        XCTAssertGreaterThan(corner.g, 240)
    }

    func testPreferencesDecorationClampsAndDefaults() {
        Preferences.registerDefaults()
        let defaults = UserDefaults.standard
        let keys = [Preferences.Key.decorationEnabled, Preferences.Key.cornerPercent, Preferences.Key.shadowLength]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        for key in keys { defaults.removeObject(forKey: key) }
        XCTAssertEqual(Preferences.decoration, ImageDecoration(isEnabled: false, cornerRatio: 0.03, shadowLength: 20))

        defaults.set(true, forKey: Preferences.Key.decorationEnabled)
        defaults.set(80.0, forKey: Preferences.Key.cornerPercent)
        defaults.set(-5.0, forKey: Preferences.Key.shadowLength)
        XCTAssertEqual(Preferences.decoration, ImageDecoration(isEnabled: true, cornerRatio: 0.25, shadowLength: 0))
    }
}

@MainActor
final class QuickPinTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("1shotTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    func testEmptyPasteboardHasNoContent() {
        XCTAssertNil(QuickPin.content(from: pasteboard, lastCapture: nil))
        pasteboard.clearContents()
        pasteboard.setString("   \n ", forType: .string)
        XCTAssertNil(QuickPin.content(from: pasteboard, lastCapture: nil))
    }

    func testLastCaptureWinsWhenPasteboardUnchanged() {
        let image = solidImage(width: 20, height: 10)
        PasteboardWriter.write(image, to: pasteboard)
        let capture = OutputPipeline.LastCapture(image: image, anchor: CGRect(x: 100, y: 200, width: 10, height: 5),
                                                 scale: 2, pasteboardChangeCount: pasteboard.changeCount)
        guard case .capture(let found) = QuickPin.content(from: pasteboard, lastCapture: capture) else {
            return XCTFail("应识别为刚截的图")
        }
        XCTAssertEqual(found.anchor, capture.anchor)

        // 之后用户在别处复制了文字：贴文字。
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        guard case .text(let text) = QuickPin.content(from: pasteboard, lastCapture: capture) else {
            return XCTFail("剪贴板变了，应贴新内容")
        }
        XCTAssertEqual(text, "hello")
    }

    func testReadsImageDataWithDPI() throws {
        let image = solidImage(width: 80, height: 40)
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: 40, height: 20) // 144 DPI，即 Retina 截图
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        pasteboard.setData(png, forType: .png)
        guard case .image(let found, let size) = QuickPin.content(from: pasteboard, lastCapture: nil) else {
            return XCTFail("应识别为图片")
        }
        XCTAssertEqual(found.width, 80)
        XCTAssertEqual(size, CGSize(width: 40, height: 20))
    }

    func testReadsImageFileURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("1shot-pin-\(UUID().uuidString).png")
        try XCTUnwrap(ImageEncoder.data(for: solidImage(width: 30, height: 12), format: .png)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        pasteboard.writeObjects([url as NSURL])
        guard case .image(let found, _) = QuickPin.content(from: pasteboard, lastCapture: nil) else {
            return XCTFail("应读取图片文件")
        }
        XCTAssertEqual(found.width, 30)
        XCTAssertEqual(found.height, 12)
    }

    func testTrimsAndLimitsText() {
        pasteboard.setString("  https://example.com/a  \n", forType: .string)
        guard case .text(let text) = QuickPin.content(from: pasteboard, lastCapture: nil) else {
            return XCTFail("应识别为文字")
        }
        XCTAssertEqual(text, "https://example.com/a")

        pasteboard.clearContents()
        pasteboard.setString(String(repeating: "字", count: QuickPin.maxTextLength + 50), forType: .string)
        guard case .text(let long) = QuickPin.content(from: pasteboard, lastCapture: nil) else {
            return XCTFail("应识别为文字")
        }
        XCTAssertEqual(long.count, QuickPin.maxTextLength)
    }

    func testPinFrameCentersAndFitsScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let small = PinManager.frame(for: CGSize(width: 100, height: 50), around: CGPoint(x: 500, y: 400), in: visible)
        XCTAssertEqual(small, CGRect(x: 450, y: 375, width: 100, height: 50))

        let nearEdge = PinManager.frame(for: CGSize(width: 100, height: 50), around: CGPoint(x: 990, y: 5), in: visible)
        XCTAssertEqual(nearEdge.maxX, 1000)
        XCTAssertEqual(nearEdge.minY, 0)

        let huge = PinManager.frame(for: CGSize(width: 2000, height: 400), around: CGPoint(x: 500, y: 400), in: visible)
        XCTAssertEqual(huge.width, 800)
        XCTAssertEqual(huge.height, 160)
        XCTAssertTrue(visible.contains(huge))
    }
}

final class TextCardRendererTests: XCTestCase {
    func testLinkDetection() {
        XCTAssertTrue(TextCardRenderer.isLink("https://example.com/path?q=1"))
        XCTAssertTrue(TextCardRenderer.isLink("http://a.b"))
        XCTAssertFalse(TextCardRenderer.isLink("看这里 https://example.com"))
        XCTAssertFalse(TextCardRenderer.isLink("ftp://example.com"))
        XCTAssertFalse(TextCardRenderer.isLink("hello"))
    }

    func testShortTextShrinksToContent() throws {
        let card = try XCTUnwrap(TextCardRenderer.render("你好", scale: 2, dark: false))
        XCTAssertLessThan(card.size.width, 120)
        XCTAssertGreaterThanOrEqual(card.size.width, TextCardRenderer.minWidth)
        XCTAssertEqual(card.image.width, Int((card.size.width * 2).rounded(.up)))
        // 背景是白色、不透明。
        let corner = Pixels(card.image).rgba(1, 1)
        XCTAssertEqual(corner.a, 255)
        XCTAssertGreaterThan(corner.r, 250)
    }

    func testLongTextIsCapped() throws {
        let text = String(repeating: "这是一段很长的文字，用来测试换行和截断。", count: 200)
        let card = try XCTUnwrap(TextCardRenderer.render(text, scale: 1, dark: true))
        // 中文按字换行，右侧会留一点余量，宽度接近但不超过上限。
        XCTAssertLessThanOrEqual(card.size.width, TextCardRenderer.maxWidth)
        XCTAssertGreaterThan(card.size.width, TextCardRenderer.maxWidth - TextCardRenderer.fontSize * 2)
        XCTAssertEqual(card.size.height, TextCardRenderer.maxHeight)
        let corner = Pixels(card.image).rgba(1, 1)
        XCTAssertLessThan(corner.r, 60, "深色模式背景应为深色")
    }
}

final class CaptureModeTests: XCTestCase {
    func testQuickCopyFinishesOnlyWhenSelected() {
        XCTAssertTrue(CaptureMode.quickCopy.finishesOnSelection(.selected))
        XCTAssertFalse(CaptureMode.quickCopy.finishesOnSelection(.hovering))
        XCTAssertFalse(CaptureMode.quickCopy.finishesOnSelection(.dragging))
        XCTAssertFalse(CaptureMode.annotate.finishesOnSelection(.selected))
    }
}
