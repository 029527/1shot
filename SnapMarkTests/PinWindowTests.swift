import XCTest
@testable import SnapMark

@MainActor
final class PinWindowTests: XCTestCase {
    private func makeWindow() -> PinWindow {
        let image = ImageExporterTests.solidImage(width: 400, height: 200, color: CGColor(gray: 0.5, alpha: 1))
        return PinWindow(image: image, frame: CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    func testZoomAroundCenterKeepsCenter() {
        let window = makeWindow()
        window.setZoom(2)
        XCTAssertEqual(window.frame, CGRect(x: 0, y: 50, width: 400, height: 200))
        window.close()
    }

    func testZoomAroundAnchorKeepsAnchorFixed() {
        let window = makeWindow()
        // 以左下角为锚点：原点不动。
        window.setZoom(1.5, anchor: .zero)
        XCTAssertEqual(window.frame.origin, CGPoint(x: 100, y: 100))
        XCTAssertEqual(window.frame.size, CGSize(width: 300, height: 150))
        window.close()
    }

    func testZoomIsClamped() {
        let window = makeWindow()
        window.setZoom(100)
        XCTAssertEqual(window.zoom, PinWindow.maxZoom)
        window.setZoom(0.001)
        XCTAssertEqual(window.zoom, PinWindow.minZoom)
        window.resetZoom(nil)
        XCTAssertEqual(window.frame.size, CGSize(width: 200, height: 100))
        window.close()
    }

    func testCommandsParse() {
        func event(_ key: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0)!
        }
        XCTAssertEqual(OverlayCommand(keyEquivalent: event("t", .command)), .pin)
        XCTAssertEqual(OverlayCommand(keyEquivalent: event("r", .command)), .ocr)
        XCTAssertEqual(OverlayCommand(keyEquivalent: event("l", .command)), .longScreenshot)
        XCTAssertEqual(OverlayCommand(keyEquivalent: event("z", [.command, .shift])), .redo)
        XCTAssertNil(OverlayCommand(keyEquivalent: event("t", .control)))
    }
}
