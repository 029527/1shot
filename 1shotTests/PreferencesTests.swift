import XCTest
@testable import OneShot

final class PreferencesTests: XCTestCase {
    func testRegisteredDefaults() {
        Preferences.registerDefaults()
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        XCTAssertEqual(registered[Preferences.Key.autoCopy] as? Bool, true)
        XCTAssertEqual(registered[Preferences.Key.autoSave] as? Bool, true)
        XCTAssertEqual(registered[Preferences.Key.showToast] as? Bool, true)
        XCTAssertEqual(registered[Preferences.Key.imageFormat] as? String, "png")
    }

    func testDefaultSaveDirectory() {
        let url = Preferences.defaultSaveDirectory
        XCTAssertEqual(url.lastPathComponent, "截图")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Pictures")
    }

    func testImageFormatProperties() {
        XCTAssertEqual(ImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageFormat.jpg.fileExtension, "jpg")
        XCTAssertEqual(ImageFormat.jpg.utType, .jpeg)
        XCTAssertEqual(ImageFormat(rawValue: "jpg"), .jpg)
    }
}
