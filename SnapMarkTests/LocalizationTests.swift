import Foundation
import XCTest
@testable import SnapMark

final class LocalizationTests: XCTestCase {
    private var englishBundle: Bundle? {
        Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
    }

    func testEnglishBundleTranslatesKeyStrings() throws {
        let en = try XCTUnwrap(englishBundle, "App 里应包含 en.lproj")
        func t(_ key: String) -> String { en.localizedString(forKey: key, value: nil, table: nil) }
        XCTAssertEqual(t("截图"), "Capture Screen")
        XCTAssertEqual(t("设置…"), "Settings…")
        XCTAssertEqual(t("已复制并保存"), "Copied and saved")
        XCTAssertEqual(t("save-directory-name"), "Screenshots")
        XCTAssertEqual(String(format: t("截图 %@"), "2026-01-01 12.00.00"), "Screenshot 2026-01-01 12.00.00")
        XCTAssertEqual(String(format: t("保存最近 %lld 张截图，可以重新复制、贴图。"), 50),
                       "Keeps the last 50 screenshots so you can copy or pin them again.")
    }

    /// 源代码里每个 `String(localized: "…")` 都要在 String Catalog 里有英文翻译。
    func testEverySourceStringHasEnglishTranslation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let catalogURL = root.appendingPathComponent("SnapMark/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])

        let integerExpressions: Set<String> = ["HistoryStore.defaultLimit", "store.limit", "store.items.count"]
        let pattern = try NSRegularExpression(pattern: #"String\(localized: "((?:[^"\\]|\\.)*)"\)"#)
        var missing: [String] = []
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("SnapMark"), includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                let key = Self.catalogKey(String(source[range]), integerExpressions: integerExpressions)
                let entry = strings[key] as? [String: Any]
                let localizations = entry?["localizations"] as? [String: Any]
                if localizations?["en"] == nil { missing.append("\(url.lastPathComponent): \(key)") }
            }
        }
        XCTAssertEqual(missing, [], "以下文案缺少英文翻译")
    }

    /// Swift 插值 → 格式占位符：整数 `%lld`，其他 `%@`。
    private static func catalogKey(_ literal: String, integerExpressions: Set<String>) -> String {
        var result = ""
        var index = literal.startIndex
        while index < literal.endIndex {
            if literal[index...].hasPrefix("\\(") {
                var depth = 1
                var cursor = literal.index(index, offsetBy: 2)
                let start = cursor
                while depth > 0 {
                    if literal[cursor] == "(" { depth += 1 } else if literal[cursor] == ")" { depth -= 1 }
                    cursor = literal.index(after: cursor)
                }
                let expression = String(literal[start..<literal.index(before: cursor)])
                result += integerExpressions.contains(expression) ? "%lld" : "%@"
                index = cursor
            } else {
                result.append(literal[index])
                index = literal.index(after: index)
            }
        }
        return result
    }
}
