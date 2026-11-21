import Foundation
import KeyboardShortcuts
import UniformTypeIdentifiers

extension KeyboardShortcuts.Name {
    /// 截图（选区后显示工具栏，可以标注），默认 ⌃⇧A。
    static let captureScreen = Self("captureScreen", initial: .init(.a, modifiers: [.control, .shift]))
    /// 截图并自动复制（选完区域立即完成，不显示工具栏），默认不设置。
    static let captureAndCopy = Self("captureAndCopy")
    /// 贴图：把剪贴板内容（或最近一次截图）贴到桌面，默认不设置。
    static let pinClipboard = Self("pinClipboard")
}

/// 截图模式。
enum CaptureMode: Equatable {
    /// 选区后显示工具栏，用户自己标注、完成。
    case annotate
    /// 选完区域立即完成并复制，不显示工具栏。
    case quickCopy

    /// 选区刚确定（松开鼠标后进入 selected）时是否直接完成。
    func finishesOnSelection(_ state: SelectionModel.State) -> Bool {
        self == .quickCopy && state == .selected
    }
}

/// 输出图片的圆角与阴影（只作用于复制、保存的图片；贴图和截图历史保留原图）。
struct ImageDecoration: Equatable {
    var isEnabled: Bool
    /// 圆角半径占短边的比例（0…0.25）。
    var cornerRatio: Double
    /// 阴影长度（pt）。
    var shadowLength: Double

    static let cornerRange: ClosedRange<Double> = 0...25
    static let shadowRange: ClosedRange<Double> = 0...60

    /// 是否会真正改变图片。
    var isEffective: Bool { isEnabled && (cornerRatio > 0 || shadowLength > 0) }
}

/// 界面语言：跟随系统，或固定为简体中文 / 英文（写入本 App 的 AppleLanguages，重启后生效）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// 选项里显示的名字：语言名用该语言自己的写法。
    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    static let appleLanguagesKey = "AppleLanguages"

    /// 当前设置（读本 App 自己的 UserDefaults 域，不含全局）。
    static func current(in defaults: UserDefaults = .standard) -> AppLanguage {
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = defaults.persistentDomain(forName: domain)?[appleLanguagesKey] as? [String],
              let first = languages.first
        else { return .system }
        if first.hasPrefix("zh") { return .simplifiedChinese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    func apply(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set([rawValue], forKey: Self.appleLanguagesKey)
        }
    }
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
        static let keepHistory = "keepHistory"
        static let decorationEnabled = "decorationEnabled"
        /// 圆角比例（百分比，0…25）。
        static let cornerPercent = "cornerPercent"
        /// 阴影长度（pt，0…60）。
        static let shadowLength = "shadowLength"
    }

    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.autoCopy: true,
            Key.autoSave: true,
            Key.imageFormat: ImageFormat.png.rawValue,
            Key.showToast: true,
            Key.keepHistory: true,
            Key.decorationEnabled: false,
            Key.cornerPercent: 3.0,
            Key.shadowLength: 20.0,
        ])
    }

    /// 圆角与阴影设置。
    static var decoration: ImageDecoration {
        ImageDecoration(
            isEnabled: defaults.bool(forKey: Key.decorationEnabled),
            cornerRatio: min(max(defaults.double(forKey: Key.cornerPercent), ImageDecoration.cornerRange.lowerBound),
                             ImageDecoration.cornerRange.upperBound) / 100,
            shadowLength: min(max(defaults.double(forKey: Key.shadowLength), ImageDecoration.shadowRange.lowerBound),
                              ImageDecoration.shadowRange.upperBound)
        )
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

    /// 保留截图历史（默认开，最近 50 条）。
    static var keepHistory: Bool {
        get { defaults.bool(forKey: Key.keepHistory) }
        set { defaults.set(newValue, forKey: Key.keepHistory) }
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
            .appendingPathComponent(String(localized: "save-directory-name", defaultValue: "截图"), isDirectory: true)
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
