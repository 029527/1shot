import XCTest
@testable import SnapMark

final class ScrollStitcherTests: XCTestCase {
    let width = 120

    /// 每一行都不一样的「长页面」像素（RGBA）。
    private func pageRow(_ y: Int) -> [UInt8] {
        var row: [UInt8] = []
        for x in 0..<width {
            row += [UInt8((x * 7 + y * 13) % 256), UInt8((y * 31 + x) % 256), UInt8((x ^ y) % 256), 255]
        }
        return row
    }

    private func constantRow(_ value: UInt8, pattern: Int) -> [UInt8] {
        var row: [UInt8] = []
        for x in 0..<width { row += [value, UInt8((x * pattern) % 256), 0, 255] }
        return row
    }

    private func image(rows: [[UInt8]]) -> CGImage {
        let data = Data(rows.flatMap { $0 }) as CFData
        return CGImage(width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func rows(of image: CGImage) -> [[UInt8]] {
        let frame = ScrollStitcher.frame(from: image)!
        return (0..<image.height).map { Array(frame.bytes[($0 * width * 4)..<(($0 + 1) * width * 4)]) }
    }

    /// 页面滚动到 `offset` 时，200 行高的视口截图；可带固定的吸顶 / 底栏。
    private func frame(at offset: Int, header: Int = 0, footer: Int = 0) -> CGImage {
        let height = 200
        var result: [[UInt8]] = []
        for r in 0..<height {
            if r < header {
                result.append(constantRow(200, pattern: 3 + r))
            } else if r >= height - footer {
                result.append(constantRow(90, pattern: 5 + r))
            } else {
                result.append(pageRow(offset + r))
            }
        }
        return image(rows: result)
    }

    func testStitchesPlainScroll() throws {
        let stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: frame(at: 0)))
        XCTAssertEqual(stitcher.add(frame(at: 50)), .appended(50))
        XCTAssertEqual(stitcher.add(frame(at: 50)), .unchanged)
        XCTAssertEqual(stitcher.add(frame(at: 130)), .appended(80))
        XCTAssertEqual(stitcher.add(frame(at: 260)), .appended(130))
        XCTAssertEqual(stitcher.totalHeight, 460)

        let result = try XCTUnwrap(stitcher.makeImage())
        XCTAssertEqual(result.height, 460)
        XCTAssertEqual(rows(of: result), (0..<460).map(pageRow))
    }

    func testKeepsHeaderOnceAndFooterAtEnd() throws {
        let stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: frame(at: 0, header: 20, footer: 15)))
        for offset in [40, 100, 180, 300] {
            if case .appended = stitcher.add(frame(at: offset, header: 20, footer: 15)) {} else {
                XCTFail("offset \(offset) 未拼接")
            }
        }
        XCTAssertEqual(stitcher.headerHeight, 20)
        XCTAssertEqual(stitcher.footerHeight, 15)

        let result = try XCTUnwrap(stitcher.makeImage())
        let expected = (0..<20).map { constantRow(200, pattern: 3 + $0) }
            + (20..<(300 + 185)).map(pageRow)
            + (185..<200).map { constantRow(90, pattern: 5 + $0) }
        XCTAssertEqual(result.height, expected.count)
        XCTAssertEqual(rows(of: result), expected)
    }

    func testScrollingBackUpIsIgnoredUntilReturning() throws {
        let stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: frame(at: 0)))
        XCTAssertEqual(stitcher.add(frame(at: 100)), .appended(100))
        // 往回滚：找不到向下的偏移。
        XCTAssertNotEqual(stitcher.add(frame(at: 40)), .appended(0))
        XCTAssertEqual(stitcher.totalHeight, 300)
        XCTAssertEqual(stitcher.add(frame(at: 150)), .appended(50))
        XCTAssertEqual(rows(of: stitcher.makeImage()!), (0..<350).map(pageRow))
    }

    func testTooFastHasNoMatch() throws {
        let stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: frame(at: 0)))
        XCTAssertEqual(stitcher.add(frame(at: 195)), .noMatch)
        XCTAssertEqual(stitcher.totalHeight, 200)
    }

    func testStopsAtMaxHeight() throws {
        let stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: frame(at: 0), maxHeight: 280))
        XCTAssertEqual(stitcher.add(frame(at: 60)), .appended(60))
        XCTAssertEqual(stitcher.add(frame(at: 120)), .limitReached)
        XCTAssertEqual(stitcher.totalHeight, 280)
        XCTAssertEqual(stitcher.add(frame(at: 180)), .limitReached)
        XCTAssertEqual(rows(of: stitcher.makeImage()!), (0..<280).map(pageRow))
    }

    func testRejectsDifferentSize() throws {
        let stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: frame(at: 0)))
        let small = image(rows: (0..<100).map(pageRow))
        XCTAssertEqual(stitcher.add(small), .sizeMismatch)
    }
}
