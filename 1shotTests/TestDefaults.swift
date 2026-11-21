import Foundation

/// 测试用的独立 UserDefaults，配置文件放在临时目录（绝对路径作为配置域），
/// 不会在 ~/Library/Preferences 里留下文件。
final class TestDefaults {
    let suite: String
    let defaults: UserDefaults

    init(_ prefix: String = "1shotTests") {
        suite = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)").path
        defaults = UserDefaults(suiteName: suite)!
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}
