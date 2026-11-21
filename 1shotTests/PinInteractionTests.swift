import AppKit
import XCTest
@testable import OneShot

@MainActor
final class PinInteractionTests: XCTestCase {
    private func whiteImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makePin() -> PinWindow {
        let pin = PinWindow(image: whiteImage(width: 400, height: 240), frame: CGRect(x: 300, y: 300, width: 200, height: 120))
        pin.orderFrontRegardless()
        return pin
    }

    private func click(_ pin: PinWindow, count: Int, at point: CGPoint = CGPoint(x: 100, y: 60)) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: pin.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: count, pressure: 1)!
            if type == .leftMouseDown { pin.pinView.mouseDown(with: event) } else { pin.pinView.mouseUp(with: event) }
        }
    }

    // MARK: 缩放

    func testScrollUpZoomsInRegardlessOfNaturalScrolling() {
        // 传统滚动：滚轮往上 deltaY > 0；自然滚动：deltaY < 0 且标记为反向。物理方向相同，都应放大。
        XCTAssertGreaterThan(PinWindow.zoomFactor(deltaY: 1, precise: false, invertedFromDevice: false), 1)
        XCTAssertGreaterThan(PinWindow.zoomFactor(deltaY: -1, precise: false, invertedFromDevice: true), 1)
        XCTAssertLessThan(PinWindow.zoomFactor(deltaY: -1, precise: false, invertedFromDevice: false), 1)
        XCTAssertGreaterThan(PinWindow.zoomFactor(deltaY: 6, precise: true, invertedFromDevice: false), 1)
    }

    func testZoomInThenOutReturnsToOriginal() {
        let up = PinWindow.zoomFactor(deltaY: 3, precise: false, invertedFromDevice: false)
        let down = PinWindow.zoomFactor(deltaY: -3, precise: false, invertedFromDevice: false)
        XCTAssertEqual(up * down, 1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(PinWindow.zoomFactor(deltaY: 500, precise: false, invertedFromDevice: false), exp(0.5) + 1e-9,
                                 "一次滚动的倍数有上限，不会突然变得很大")
    }

    func testCanZoomWhileEditingAndAnnotationsStayAligned() throws {
        let pin = makePin()
        defer { pin.close() }
        pin.toggleEditor()
        pin.setZoom(2)
        XCTAssertEqual(pin.zoom, 2, "编辑时也能缩放")
        XCTAssertEqual(pin.frame.size, CGSize(width: 400, height: 240))
        XCTAssertEqual(pin.pinView.annotationHost.bounds.size, CGSize(width: 200, height: 120), "标注坐标仍按原始尺寸")
        XCTAssertEqual(pin.pinView.controlsHost.bounds.size, CGSize(width: 200, height: 120))

        let editor = try XCTUnwrap(pin.editor)
        editor.annotations.toggle(.rectangle)
        _ = editor.mouseDown(at: CGPoint(x: 20, y: 20), clickCount: 1, modifiers: [])
        editor.mouseDragged(to: CGPoint(x: 120, y: 90), modifiers: [])
        editor.mouseUp(at: CGPoint(x: 120, y: 90), modifiers: [])
        let output = pin.outputImage
        XCTAssertEqual(output.width, 400, "输出仍是原图像素尺寸")
    }

    // MARK: 双击关闭

    func testDoubleClickClosesPin() {
        let pin = makePin()
        click(pin, count: 1)
        XCTAssertTrue(pin.isVisible, "单击不关闭")
        click(pin, count: 2)
        XCTAssertFalse(pin.isVisible, "双击关闭贴图")
    }

    func testDoubleClickClosesPinInEditModeWithoutTool() {
        let pin = makePin()
        pin.toggleEditor()
        click(pin, count: 2)
        XCTAssertFalse(pin.isVisible, "编辑模式下没选工具时，双击空白处也关闭")
    }

    func testDoubleClickWithDrawingToolDoesNotClose() throws {
        let pin = makePin()
        defer { pin.close() }
        pin.toggleEditor()
        try XCTUnwrap(pin.editor).annotations.toggle(.counter)
        click(pin, count: 2)
        XCTAssertTrue(pin.isVisible, "选了工具时双击是在画图")
    }

    // MARK: 完成提示

    func testDontShowAgainTurnsOffCompletionToasts() {
        Preferences.registerDefaults()
        let saved = UserDefaults.standard.object(forKey: Preferences.Key.showToast)
        defer { UserDefaults.standard.set(saved, forKey: Preferences.Key.showToast) }
        Preferences.showToast = true

        Toast.shared.dontShowAgain()
        XCTAssertFalse(Preferences.showToast)
        // 「已关闭」本身是提醒类，会显示；之后的完成提示不再显示。
        Toast.shared.showCompletion("已复制", near: CGRect(x: 400, y: 400, width: 10, height: 10))
        XCTAssertFalse(Preferences.showToast)
    }
}
