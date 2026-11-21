import AppKit
import Combine
import ImageIO

/// 一条截图历史。
struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let fileName: String
    let width: Int
    let height: Int
    /// 截图所在屏幕的 scale，贴图时还原 pt 尺寸。
    let scale: Double
}

/// 截图历史：PNG 文件 + index.json，保存在 ~/Library/Application Support/SnapMark/History，最多保留 `limit` 条。
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore(directory: defaultDirectory)

    nonisolated static let defaultLimit = 50

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnapMark/History", isDirectory: true)
    }

    @Published private(set) var items: [HistoryItem] = []

    let directory: URL
    let limit: Int

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL, limit: Int = defaultLimit) {
        self.directory = directory
        self.limit = limit
        load()
    }

    func url(for item: HistoryItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    func image(for item: HistoryItem) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: item) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 新增一条（最新的在最前），超出上限时删除最旧的。
    @discardableResult
    func add(pngData: Data, width: Int, height: Int, scale: Double, date: Date = Date()) throws -> HistoryItem {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let item = HistoryItem(id: id, date: date, fileName: "\(id.uuidString).png", width: width, height: height,
                               scale: scale)
        try pngData.write(to: url(for: item), options: .atomic)
        items.insert(item, at: 0)
        if items.count > limit {
            for old in items[limit...] {
                try? FileManager.default.removeItem(at: url(for: old))
            }
            items.removeSubrange(limit...)
        }
        persist()
        return item
    }

    func remove(_ item: HistoryItem) {
        try? FileManager.default.removeItem(at: url(for: item))
        items.removeAll { $0.id == item.id }
        persist()
    }

    func removeAll() {
        for item in items {
            try? FileManager.default.removeItem(at: url(for: item))
        }
        items.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        // 丢掉文件已不存在的记录。
        items = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: indexURL, options: .atomic)
        } catch {
            Log.app.error("保存截图历史失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
