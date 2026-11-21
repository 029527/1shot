import Foundation

/// 测试用的独立 UserDefaults。`removePersistentDomain` 之后系统仍会留下一个空的 plist，
/// 所以清理时连 ~/Library/Preferences/<suite>.plist 一起删掉，不在用户电脑上留垃圾。
final class TestDefaults {
    let suite: String
    let defaults: UserDefaults

    init(_ prefix: String = "1shotTests") {
        suite = "\(prefix).\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        defaults.synchronize()
        let file = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: file)
    }

    deinit { cleanUp() }
}
