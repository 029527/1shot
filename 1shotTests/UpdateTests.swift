import Foundation
import XCTest
@testable import OneShot

final class VersionNumberTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(VersionNumber.normalized("v1.2.3"), "1.2.3")
        XCTAssertEqual(VersionNumber.normalized("0.10"), "0.10")
        XCTAssertEqual(VersionNumber.normalized("v2.0.0-beta.1"), "2.0.0")
        XCTAssertNil(VersionNumber.normalized("latest"))
        XCTAssertNil(VersionNumber.normalized("v1..2"))
    }

    func testCompare() {
        XCTAssertTrue(VersionNumber.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertTrue(VersionNumber.isNewer("1.10.0", than: "1.9.3"), "按数字比较，不按字符串")
        XCTAssertTrue(VersionNumber.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(VersionNumber.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(VersionNumber.isNewer("0.1.0", than: "0.2.0"))
    }
}

final class ReleaseInfoTests: XCTestCase {
    private func json(tag: String = "v0.2.0", prerelease: Bool = false, assets: [String]) -> Data {
        let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"# }
            .joined(separator: ",")
        return Data(#"""
        {"tag_name":"\#(tag)","body":"- 新功能","html_url":"https://github.com/o/r/releases/tag/\#(tag)",
         "draft":false,"prerelease":\#(prerelease),"assets":[\#(list)]}
        """#.utf8)
    }

    func testParsesLatestRelease() throws {
        let release = try ReleaseInfo.parse(json(assets: ["1shot-0.2.0.zip", "1shot-0.2.0.zip.sha256"]))
        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.zipURL.lastPathComponent, "1shot-0.2.0.zip")
        XCTAssertEqual(release.checksumURL?.lastPathComponent, "1shot-0.2.0.zip.sha256")
        XCTAssertEqual(release.notes, "- 新功能")
    }

    func testRejectsPrereleaseAndMissingAsset() {
        XCTAssertThrowsError(try ReleaseInfo.parse(json(prerelease: true, assets: ["1shot-0.2.0.zip"])))
        XCTAssertThrowsError(try ReleaseInfo.parse(json(assets: ["other.zip"]))) { error in
            XCTAssertEqual(error as? ReleaseInfo.ParseError, .missingAsset("1shot-0.2.0.zip"))
        }
        XCTAssertThrowsError(try ReleaseInfo.parse(Data("{}".utf8)))
    }

    func testParsesChecksumFile() {
        let hex = String(repeating: "ab", count: 32)
        XCTAssertEqual(ReleaseInfo.parseChecksum("\(hex)  1shot-0.2.0.zip\n"), hex)
        XCTAssertEqual(ReleaseInfo.parseChecksum(hex.uppercased()), hex)
        XCTAssertNil(ReleaseInfo.parseChecksum("not-a-hash  file"))
        XCTAssertNil(ReleaseInfo.parseChecksum(""))
    }
}

final class UpdateInstallerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("1shot-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testSHA256() throws {
        let file = directory.appendingPathComponent("a.txt")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try UpdateInstaller.sha256(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testOnlyInstallsInPlaceFromApplicationsFolder() {
        let writable: (String) -> Bool = { _ in true }
        XCTAssertTrue(UpdateInstaller.canInstallInPlace(appURL: URL(fileURLWithPath: "/Applications/1shot.app"),
                                                        isWritable: writable))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(UpdateInstaller.canInstallInPlace(appURL: URL(fileURLWithPath: home + "/Applications/1shot.app"),
                                                        isWritable: writable))
        XCTAssertFalse(UpdateInstaller.canInstallInPlace(
            appURL: URL(fileURLWithPath: "/Users/x/Developer/1shot/build/Build/Products/Debug/1shot.app"), isWritable: writable),
            "开发构建不自动替换")
        XCTAssertFalse(UpdateInstaller.canInstallInPlace(appURL: URL(fileURLWithPath: "/Applications/1shot.app"),
                                                         isWritable: { _ in false }))
    }

    func testVerifyAcceptsTheRunningAppAndRejectsWrongVersion() throws {
        let app = Bundle.main.bundleURL
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        XCTAssertNoThrow(try UpdateInstaller.verify(app: app, expectedVersion: version, current: app))
        XCTAssertThrowsError(try UpdateInstaller.verify(app: app, expectedVersion: "999.0.0", current: app))
    }

    func testReplacementScriptSwapsAppAfterProcessExits() throws {
        let current = directory.appendingPathComponent("1shot.app")
        let staged = directory.appendingPathComponent("staged/1shot.app")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: current.appendingPathComponent("marker"))
        try Data("new".utf8).write(to: staged.appendingPathComponent("marker"))

        // 等待的进程已经结束：脚本应立即替换。
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()

        let backup = directory.appendingPathComponent(".1shot-previous.app")
        let process = UpdateInstaller.replacementProcess(waitingFor: finished.processIdentifier, current: current,
                                                         staged: staged, backup: backup, relaunch: false)
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path), "旧版本备份已清理")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testReplacementRestoresOldAppWhenNewIsMissing() throws {
        let current = directory.appendingPathComponent("1shot.app")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: current.appendingPathComponent("marker"))
        let process = UpdateInstaller.replacementProcess(
            waitingFor: 999_999, current: current, staged: directory.appendingPathComponent("missing.app"),
            backup: directory.appendingPathComponent(".backup.app"), relaunch: false)
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("marker"), encoding: .utf8), "old",
                       "新版本不在时把旧版本放回原处")
    }

    func testCheckIsDueAfterInterval() {
        let now = Date()
        XCTAssertTrue(UpdateService.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateService.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateService.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }
}
