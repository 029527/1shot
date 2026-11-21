import XCTest
@testable import OneShot

final class WindowListSnapshotTests: XCTestCase {
    private func entry(
        id: Int, pid: Int32, rect: CGRect, layer: Int = 0, alpha: Double = 1, name: String = "App"
    ) -> [String: Any] {
        [
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowOwnerName as String: name,
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: rect.dictionaryRepresentation,
        ]
    }

    func testParsesAndFilters() {
        let raw = [
            entry(id: 1, pid: 100, rect: CGRect(x: 0, y: 0, width: 300, height: 200)),
            entry(id: 2, pid: 999, rect: CGRect(x: 0, y: 0, width: 300, height: 200)),          // 自己
            entry(id: 3, pid: 101, rect: CGRect(x: 0, y: 0, width: 300, height: 200), alpha: 0), // 透明
            entry(id: 4, pid: 102, rect: CGRect(x: 0, y: 0, width: 1, height: 200)),            // 太窄
            entry(id: 5, pid: 103, rect: CGRect(x: 50, y: 50, width: 500, height: 500), layer: 3),
        ]
        let snapshot = WindowListSnapshot(rawList: raw, excludingPID: 999)
        XCTAssertEqual(snapshot.windows.map(\.windowID), [1, 5])
        XCTAssertEqual(snapshot.windows[1].layer, 3)
        XCTAssertEqual(snapshot.windows[1].frame, CGRect(x: 50, y: 50, width: 500, height: 500))
    }

    func testTopmostWindowKeepsFrontToBackOrder() {
        let raw = [
            entry(id: 10, pid: 1, rect: CGRect(x: 100, y: 100, width: 100, height: 100)),
            entry(id: 11, pid: 2, rect: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
        ]
        let snapshot = WindowListSnapshot(rawList: raw, excludingPID: 0)
        XCTAssertEqual(snapshot.topmostWindow(containingCG: CGPoint(x: 150, y: 150))?.windowID, 10)
        XCTAssertEqual(snapshot.topmostWindow(containingCG: CGPoint(x: 500, y: 500))?.windowID, 11)
        XCTAssertNil(snapshot.topmostWindow(containingCG: CGPoint(x: 2000, y: 2000)))
    }

    func testSkipsMalformedEntries() {
        let raw: [[String: Any]] = [[kCGWindowNumber as String: NSNumber(value: 1)]]
        XCTAssertTrue(WindowListSnapshot(rawList: raw, excludingPID: 0).windows.isEmpty)
    }
}
