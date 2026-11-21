import XCTest
@testable import SnapMark

final class TextRecognizerTests: XCTestCase {
    func testLayoutOrdersRowsAndColumns() {
        // Vision 坐标：左下原点，y 越大越靠上。
        let lines = [
            RecognizedLine(text: "world", box: CGRect(x: 0.5, y: 0.8, width: 0.3, height: 0.1)),
            RecognizedLine(text: "第二行", box: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.1)),
            RecognizedLine(text: "Hello", box: CGRect(x: 0.1, y: 0.81, width: 0.3, height: 0.1)),
            RecognizedLine(text: "继续", box: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1)),
        ]
        XCTAssertEqual(TextRecognizer.layout(lines), "Hello world\n第二行继续")
    }

    func testLayoutEmpty() {
        XCTAssertEqual(TextRecognizer.layout([]), "")
    }

    func testRecognizesRenderedText() async throws {
        let width = 900, height = 220
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black]
        ("SnapMark 2026" as NSString).draw(at: CGPoint(x: 30, y: 120), withAttributes: attributes)
        ("截图工具" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: attributes)
        NSGraphicsContext.current = previous

        let lines = try await TextRecognizer.recognize(context.makeImage()!)
        let text = TextRecognizer.layout(lines)
        XCTAssertTrue(text.contains("SnapMark"), text)
        XCTAssertTrue(text.contains("截图"), text)
        XCTAssertLessThan(text.range(of: "SnapMark")!.lowerBound, text.range(of: "截图")!.lowerBound)
    }
}
