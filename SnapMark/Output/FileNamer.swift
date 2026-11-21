import Foundation

/// 文件名：`截图 2026-11-21 14.03.22.png`，重名时追加 ` (1)`、` (2)`。
enum FileNamer {
    /// 每次新建 formatter：可能在后台线程调用，DateFormatter 不宜跨线程共享修改。
    static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "截图 \(formatter.string(from: date))"
    }

    static func fileName(for date: Date, fileExtension: String, timeZone: TimeZone = .current) -> String {
        "\(baseName(for: date, timeZone: timeZone)).\(fileExtension)"
    }

    /// 目录里不重名的文件 URL。
    static func uniqueURL(
        in directory: URL,
        date: Date,
        fileExtension: String,
        timeZone: TimeZone = .current,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let base = baseName(for: date, timeZone: timeZone)
        var candidate = directory.appendingPathComponent("\(base).\(fileExtension)")
        var index = 1
        while fileExists(candidate) {
            candidate = directory.appendingPathComponent("\(base) (\(index)).\(fileExtension)")
            index += 1
        }
        return candidate
    }
}
