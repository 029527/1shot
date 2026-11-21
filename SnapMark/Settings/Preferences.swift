import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 截图快捷键，默认 ⌃⇧A。
    static let captureScreen = Self("captureScreen", initial: .init(.a, modifiers: [.control, .shift]))
}

/// 用户设置（UserDefaults）。M4 会补齐全部选项。
enum Preferences {
    private enum Key {
        static let saveDirectory = "saveDirectory"
    }

    static var defaults: UserDefaults { .standard }

    /// 默认保存目录：~/Pictures/截图
    static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("截图", isDirectory: true)
    }

    static var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.saveDirectory), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return defaultSaveDirectory
        }
        set {
            defaults.set(newValue.path, forKey: Key.saveDirectory)
        }
    }

    /// 返回保存目录，不存在就创建。
    @discardableResult
    static func ensureSaveDirectory() throws -> URL {
        let url = saveDirectory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
