import Foundation

/// GitHub Releases 上的一个版本（只取更新需要的字段）。
struct ReleaseInfo: Equatable {
    /// 不带 v 的版本号，例如 `0.2.0`。
    let version: String
    let tag: String
    let notes: String
    let pageURL: URL
    let zipURL: URL
    let checksumURL: URL?

    /// 发版资产命名约定（release.yml 里生成）：`1shot-<version>.zip` 与 `1shot-<version>.zip.sha256`。
    static func zipName(version: String) -> String { "1shot-\(version).zip" }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    enum ParseError: LocalizedError, Equatable {
        case notARelease
        case missingAsset(String)

        var errorDescription: String? {
            switch self {
            case .notARelease: return String(localized: "无法读取版本信息。")
            case .missingAsset(let name): return String(localized: "新版本缺少安装包：\(name)")
            }
        }
    }

    /// 解析 `GET /repos/{owner}/{repo}/releases/latest` 的返回。草稿、预发布版本不算。
    static func parse(_ data: Data) throws -> ReleaseInfo {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = VersionNumber.normalized(payload.tag_name)
        else { throw ParseError.notARelease }
        let zipName = zipName(version: version)
        guard let zip = payload.assets.first(where: { $0.name == zipName }) else {
            throw ParseError.missingAsset(zipName)
        }
        let checksum = payload.assets.first { $0.name == zipName + ".sha256" }
        return ReleaseInfo(version: version, tag: payload.tag_name, notes: payload.body ?? "",
                           pageURL: payload.html_url, zipURL: zip.browser_download_url,
                           checksumURL: checksum?.browser_download_url)
    }

    /// `.sha256` 文件内容：`<64 位十六进制>  文件名`。
    static func parseChecksum(_ text: String) -> String? {
        guard let first = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first else { return nil }
        let hex = first.lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hex
    }
}

/// 点分版本号比较：`1.10.0 > 1.9.3`，缺的位按 0 算，忽略前缀 v 和预发布后缀。
enum VersionNumber {
    /// `v1.2.3` → `1.2.3`；不是版本号时返回 nil。
    static func normalized(_ tag: String) -> String? {
        var text = tag.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return core
    }

    static func components(_ version: String) -> [Int] {
        (normalized(version) ?? "0").split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
