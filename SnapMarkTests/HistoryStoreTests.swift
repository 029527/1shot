import XCTest
@testable import SnapMark

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("History-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func png() -> Data {
        let image = ImageExporterTests.solidImage(width: 4, height: 2, color: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        return ImageEncoder.data(for: image, format: .png)!
    }

    func testAddNewestFirstAndPersist() throws {
        let store = HistoryStore(directory: directory)
        let first = try store.add(pngData: png(), width: 4, height: 2, scale: 2, date: Date(timeIntervalSince1970: 1))
        let second = try store.add(pngData: png(), width: 4, height: 2, scale: 1, date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(store.items.map(\.id), [second.id, first.id])
        XCTAssertNotNil(store.image(for: first))

        let reloaded = HistoryStore(directory: directory)
        XCTAssertEqual(reloaded.items, store.items)
    }

    func testPrunesOldestBeyondLimit() throws {
        let store = HistoryStore(directory: directory, limit: 3)
        var added: [HistoryItem] = []
        for i in 0..<5 {
            added.append(try store.add(pngData: png(), width: 4, height: 2, scale: 2, date: Date(timeIntervalSince1970: Double(i))))
        }
        XCTAssertEqual(store.items.map(\.id), added.reversed().prefix(3).map(\.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: added[0]).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: added[4]).path))
    }

    func testRemoveAndClear() throws {
        let store = HistoryStore(directory: directory)
        let a = try store.add(pngData: png(), width: 4, height: 2, scale: 2)
        _ = try store.add(pngData: png(), width: 4, height: 2, scale: 2)
        store.remove(a)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: a).path))
        store.removeAll()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(HistoryStore(directory: directory).items.isEmpty)
    }

    func testMissingFilesAreDroppedOnLoad() throws {
        let store = HistoryStore(directory: directory)
        let a = try store.add(pngData: png(), width: 4, height: 2, scale: 2)
        try FileManager.default.removeItem(at: store.url(for: a))
        XCTAssertTrue(HistoryStore(directory: directory).items.isEmpty)
    }
}
