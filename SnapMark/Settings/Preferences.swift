import Foundation
import KeyboardShortcuts
import UniformTypeIdentifiers

extension KeyboardShortcuts.Name {
    /// 截图快捷键，默认 ⌃⇧A。
    static let captureScreen = Self("captureScreen", initial: .init(.a, modifiers: [.control, .shift]))
}

/// 保存格式。
enum ImageFormat: String, CaseIterable, Identifiable {
    case png
    case jpg

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var utType: UTType { self == .png ? .png : .jpeg }

    var displayName: String { self == .png ? "PNG" : "JPG" }

    /// 根据文件扩展名判断格式（另存为时用户可能改了扩展名）。
    init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": self = .jpg
        default: self = .png
        }
    }
}

/// 用户设置（UserDefaults）。键名同时被 SwiftUI 的 `@AppStorage` 使用。
enum Preferences {
    enum Key {
        static let autoCopy = "autoCopy"
        static let autoSave = "autoSave"
        static let saveDirectory = "saveDirectory"
        static let imageFormat = "imageFormat"
        static let showToast = "showToast"
    }

    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.autoCopy: true,
            Key.autoSave: true,
            Key.imageFormat: ImageFormat.png.rawValue,
            Key.showToast: true,
        ])
    }

    /// 完成后自动复制到剪贴板（默认开）。
    static var autoCopy: Bool {
        get { defaults.bool(forKey: Key.autoCopy) }
        set { defaults.set(newValue, forKey: Key.autoCopy) }
    }

    /// 完成后自动保存到保存目录（默认开）。
    static var autoSave: Bool {
        get { defaults.bool(forKey: Key.autoSave) }
        set { defaults.set(newValue, forKey: Key.autoSave) }
    }

    /// 显示完成提示（默认开）。
    static var showToast: Bool {
        get { defaults.bool(forKey: Key.showToast) }
        set { defaults.set(newValue, forKey: Key.showToast) }
    }

    static var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: Key.imageFormat) ?? "") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: Key.imageFormat) }
    }

    /// JPG 压缩质量。
    static let jpegQuality: CGFloat = 0.9

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
