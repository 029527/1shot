import XCTest
@testable import SnapMark

final class CoordinateConverterTests: XCTestCase {
    /// 主屏 1512×982（MacBook Pro 14"，scale 2），外接屏 1920×1080（scale 1）放在主屏上方偏左。
    let converter = CoordinateConverter(primaryScreenHeight: 982)
    let primary = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    let external = ScreenGeometry(frame: CGRect(x: -400, y: 982, width: 1920, height: 1080), scale: 1)

    // MARK: AppKit ⇄ CG

    func testPointFlipOnPrimary() {
        XCTAssertEqual(converter.cgPoint(fromAppKit: CGPoint(x: 10, y: 0)), CGPoint(x: 10, y: 982))
        XCTAssertEqual(converter.cgPoint(fromAppKit: CGPoint(x: 10, y: 982)), CGPoint(x: 10, y: 0))
        XCTAssertEqual(converter.appKitPoint(fromCG: CGPoint(x: 10, y: 100)), CGPoint(x: 10, y: 882))
    }

    func testRectFlipOnPrimary() {
        // AppKit 中贴着主屏顶部的 100×50 矩形，在 CG 中 y 应为 0。
        let appKit = CGRect(x: 20, y: 932, width: 100, height: 50)
        XCTAssertEqual(converter.cgRect(fromAppKit: appKit), CGRect(x: 20, y: 0, width: 100, height: 50))
    }

    func testRectFlipOnScreenAbovePrimary() {
        // 外接屏在主屏上方：在 CG 坐标里 y 为负。
        XCTAssertEqual(converter.cgRect(fromAppKit: external.frame), CGRect(x: -400, y: -1080, width: 1920, height: 1080))
    }

    func testRoundTrip() {
        let rects = [
            CGRect(x: 0, y: 0, width: 1, height: 1),
            CGRect(x: -400, y: 1500, width: 333.5, height: 21.25),
            CGRect(x: 1000, y: -200, width: 50, height: 400),
        ]
        for rect in rects {
            XCTAssertEqual(converter.appKitRect(fromCG: converter.cgRect(fromAppKit: rect)), rect)
        }
        let point = CGPoint(x: -123.5, y: 1777.25)
        XCTAssertEqual(converter.appKitPoint(fromCG: converter.cgPoint(fromAppKit: point)), point)
    }

    func testNegativeSizeRectIsStandardized() {
        let rect = CGRect(x: 100, y: 100, width: -50, height: -20)
        XCTAssertEqual(converter.cgRect(fromAppKit: rect), CGRect(x: 50, y: 982 - 100, width: 50, height: 20))
    }

    // MARK: 全局 ⇄ 本地

    func testGlobalToLocalOnExternalScreen() {
        let global = CGPoint(x: -300, y: 1082)
        let local = external.localPoint(fromGlobal: global)
        XCTAssertEqual(local, CGPoint(x: 100, y: 100))
        XCTAssertEqual(external.globalPoint(fromLocal: local), global)

        let rect = CGRect(x: -400, y: 982, width: 10, height: 10)
        XCTAssertEqual(external.localRect(fromGlobal: rect), CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(external.globalRect(fromLocal: CGRect(x: 0, y: 0, width: 10, height: 10)), rect)
    }

    // MARK: 本地 ⇄ 像素

    func testPixelSize() {
        XCTAssertEqual(primary.pixelSize, CGSize(width: 3024, height: 1964))
        XCTAssertEqual(external.pixelSize, CGSize(width: 1920, height: 1080))
    }

    func testPixelRectOnRetina() {
        // 本地左下角原点、y 向上；像素左上角原点、y 向下。
        let local = CGRect(x: 10, y: 20, width: 100, height: 50)
        XCTAssertEqual(primary.pixelRect(fromLocal: local), CGRect(x: 20, y: (982 - 70) * 2, width: 200, height: 100))
        XCTAssertEqual(primary.localRect(fromPixel: primary.pixelRect(fromLocal: local)), local)
    }

    func testPixelRectOnNonRetina() {
        let local = CGRect(x: 0, y: 1030, width: 1920, height: 50)
        XCTAssertEqual(external.pixelRect(fromLocal: local), CGRect(x: 0, y: 0, width: 1920, height: 50))
    }

    func testPixelPoint() {
        XCTAssertEqual(primary.pixelPoint(fromLocal: CGPoint(x: 0, y: 982)), CGPoint(x: 0, y: 0))
        XCTAssertEqual(primary.pixelPoint(fromLocal: CGPoint(x: 1, y: 0)), CGPoint(x: 2, y: 1964))
        XCTAssertEqual(primary.localPoint(fromPixel: CGPoint(x: 2, y: 1964)), CGPoint(x: 1, y: 0))
    }

    func testIntegralPixelRectRoundsEdgesAndClamps() {
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1.5)
        // 0.3pt → 0.45px → 0；10.3pt → 15.45px → 15
        let rect = geometry.integralPixelRect(fromLocal: CGRect(x: 0.3, y: 89.7, width: 10, height: 10))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 15, height: 15))

        // 超出屏幕的部分被裁掉。
        let clamped = geometry.integralPixelRect(fromLocal: CGRect(x: 90, y: -10, width: 20, height: 20))
        XCTAssertEqual(clamped, CGRect(x: 135, y: 135, width: 15, height: 15))
    }

    func testCGWindowRectToLocalOnExternalScreen() {
        // 一个窗口在 CG 坐标中位于外接屏左上角（外接屏 CG 原点为 -400, -1080）。
        let cgWindow = CGRect(x: -400, y: -1080, width: 800, height: 600)
        let local = external.localRect(fromCG: cgWindow, converter: converter)
        XCTAssertEqual(local, CGRect(x: 0, y: 1080 - 600, width: 800, height: 600))
    }
}
