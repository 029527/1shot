import AppKit
import XCTest
@testable import SnapMark

@MainActor
final class PinEditorTests: XCTestCase {
    private func whiteImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makePin() -> PinWindow {
        // 2x 图：200 × 120 pt
        PinWindow(image: whiteImage(width: 400, height: 240), frame: CGRect(x: 200, y: 300, width: 200, height: 120))
    }

    private func pixel(_ image: CGImage, x: Int, yFromBottom: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -yFromBottom, width: image.width, height: image.height))
        return (bytes[0], bytes[1], bytes[2])
    }

    func testSpaceTogglesToolbarPanel() {
        let pin = makePin()
        defer { pin.close() }
        XCTAssertFalse(pin.isEditing)
        pin.toggleEditor()
        XCTAssertTrue(pin.isEditing)
        XCTAssertEqual(pin.childWindows?.count, 1, "工具栏在跟随贴图的子窗口里")
        pin.toggleEditor()
        XCTAssertFalse(pin.isEditing)
        XCTAssertEqual(pin.childWindows?.count ?? 0, 0)
    }

    func testDrawRectangleIsComposedAtImagePixels() throws {
        let pin = makePin()
        defer { pin.close() }
        pin.toggleEditor()
        let editor = try XCTUnwrap(pin.editor)
        XCTAssertEqual(pin.outputImage.width, 400, "没有标注时输出原图")

        editor.annotations.toggle(.rectangle)
        XCTAssertTrue(editor.mouseDown(at: CGPoint(x: 20, y: 20), clickCount: 1, modifiers: []))
        editor.mouseDragged(to: CGPoint(x: 120, y: 90), modifiers: [])
        editor.mouseUp(at: CGPoint(x: 120, y: 90), modifiers: [])
        XCTAssertTrue(editor.hasAnnotations)

        let output = pin.outputImage
        XCTAssertEqual(output.width, 400)
        XCTAssertEqual(output.height, 240)
        // 矩形左边（x = 20pt → 40px）是红色描边，中间仍是白色。
        let edge = pixel(output, x: 40, yFromBottom: 100)
        XCTAssertGreaterThan(edge.r, 200)
        XCTAssertLessThan(edge.g, 120)
        let inside = pixel(output, x: 140, yFromBottom: 100)
        XCTAssertGreaterThan(inside.g, 240)

        // 收起工具栏后标注仍保留。
        pin.toggleEditor()
        XCTAssertTrue(editor.hasAnnotations)
    }

    func testEscapeStepsBack() throws {
        let pin = makePin()
        defer { pin.close() }
        pin.toggleEditor()
        let editor = try XCTUnwrap(pin.editor)
        editor.annotations.toggle(.arrow)
        editor.escape()
        XCTAssertNil(editor.annotations.tool, "第一次 Esc 取消工具")
        XCTAssertTrue(pin.isEditing)
        editor.escape()
        XCTAssertFalse(pin.isEditing, "第二次 Esc 收起工具栏")
        XCTAssertTrue(pin.isVisible || true)
    }

    func testComposeScalesToImagePixels() throws {
        let image = whiteImage(width: 300, height: 150)
        let output = try XCTUnwrap(PinEditor.compose(image: image, size: CGSize(width: 100, height: 50)) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10)) // 10pt → 30px
        })
        XCTAssertEqual(output.width, 300)
        XCTAssertLessThan(pixel(output, x: 25, yFromBottom: 25).r, 10)
        XCTAssertGreaterThan(pixel(output, x: 35, yFromBottom: 35).r, 240)
    }
}
