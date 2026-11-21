import AppKit
import XCTest
@testable import SnapMark

final class AssetsTests: XCTestCase {
    func testMenuBarIconIsTemplateSized() throws {
        let image = try XCTUnwrap(NSImage(named: "MenuBarIcon"))
        XCTAssertTrue(image.isTemplate, "菜单栏图标应为模板图，自动适配深浅色")
        XCTAssertEqual(image.size, CGSize(width: 16, height: 16))
    }

    func testAppIconIsBundled() {
        let info = Bundle.main.infoDictionary
        XCTAssertEqual(info?["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertNotNil(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
    }
}
