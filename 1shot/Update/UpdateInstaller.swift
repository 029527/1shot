import AppKit
import CryptoKit
import Security

/// 下载、校验、暂存新版本，并在本进程退出后替换 App。
///
/// 校验：SHA-256 与 Release 里的 `.sha256` 一致；解压出的 App 代码签名有效、Bundle ID 相同、版本号正确；
/// 当前 App 有开发者团队签名时，新版本必须是同一个团队签的。
enum UpdateInstaller {
    enum InstallError: LocalizedError, Equatable {
        case checksumMismatch
        case checksumMissing
        case unpackFailed
        case invalidBundle(String)
        case signatureInvalid
        case teamMismatch
        case notWritable

        var errorDescription: String? {
            switch self {
            case .checksumMismatch: return String(localized: "安装包校验失败（SHA-256 不一致）。")
            case .checksumMissing: return String(localized: "新版本缺少校验文件。")
            case .unpackFailed: return String(localized: "解压安装包失败。")
            case .invalidBundle(let reason): return String(localized: "安装包内容不正确：\(reason)")
            case .signatureInvalid: return String(localized: "新版本的代码签名无效。")
            case .teamMismatch: return String(localized: "新版本的签名与当前版本不是同一个开发者。")
            case .notWritable: return String(localized: "没有权限替换当前 App，请手动下载安装。")
            }
        }
    }

    // MARK: 能否自动安装

    /// 只有装在「应用程序」文件夹、且有写权限时才自动替换；开发构建（build/ 目录）只提示去下载。
    static func canInstallInPlace(appURL: URL = Bundle.main.bundleURL,
                                  isWritable: (String) -> Bool = FileManager.default.isWritableFile(atPath:)) -> Bool {
        let path = appURL.standardizedFileURL.path
        let inApplications = path.hasPrefix("/Applications/")
            || path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/")
        return inApplications && isWritable(appURL.deletingLastPathComponent().path)
    }

    // MARK: 下载与校验

    static var stagingRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.1shot.app")
            .appendingPathComponent("Updates", isDirectory: true)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 下载 zip 和校验文件、核对 SHA-256、解压，返回暂存的新 App。
    static func downloadAndStage(_ release: ReleaseInfo, session: URLSession = .shared,
                                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let checksumURL = release.checksumURL else { throw InstallError.checksumMissing }
        let directory = stagingRoot.appendingPathComponent(release.version, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let (checksumData, _) = try await session.data(from: checksumURL, delegate: nil)
        guard let expected = ReleaseInfo.parseChecksum(String(decoding: checksumData, as: UTF8.self)) else {
            throw InstallError.checksumMissing
        }

        let zipURL = directory.appendingPathComponent(ReleaseInfo.zipName(version: release.version))
        let delegate = DownloadProgress(progress)
        let (temporary, _) = try await session.download(from: release.zipURL, delegate: delegate)
        try FileManager.default.moveItem(at: temporary, to: zipURL)
        guard try sha256(of: zipURL) == expected else { throw InstallError.checksumMismatch }

        let unpacked = directory.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpacked.path])
        let app = unpacked.appendingPathComponent("1shot.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw InstallError.unpackFailed }
        try verify(app: app, expectedVersion: release.version)
        return app
    }

    static func verify(app: URL, expectedVersion: String, current: URL = Bundle.main.bundleURL) throws {
        guard let bundle = Bundle(url: app) else { throw InstallError.invalidBundle("Info.plist") }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw InstallError.invalidBundle("Bundle ID \(bundle.bundleIdentifier ?? "?")")
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version == expectedVersion else { throw InstallError.invalidBundle("version \(version ?? "?")") }

        guard let newCode = staticCode(at: app), SecStaticCodeCheckValidity(
            newCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil
        ) == errSecSuccess else { throw InstallError.signatureInvalid }
        if let currentTeam = staticCode(at: current).flatMap(teamIdentifier), currentTeam != teamIdentifier(newCode) {
            throw InstallError.teamMismatch
        }
    }

    private static func staticCode(at url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        return SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess ? code : nil
    }

    private static func teamIdentifier(_ code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: 替换

    /// 启动一个等待本进程退出的脚本：旧 App 挪开 → 新 App 放到原位置 → 去掉隔离属性 → 按需重新打开。
    /// 替换失败时把旧 App 放回去。调用后应尽快退出本进程。
    static func scheduleReplacement(with stagedApp: URL, relaunch: Bool, current: URL = Bundle.main.bundleURL) throws {
        let parent = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { throw InstallError.notWritable }
        let backup = parent.appendingPathComponent(".1shot-previous-\(UUID().uuidString).app")
        let process = replacementProcess(waitingFor: ProcessInfo.processInfo.processIdentifier, current: current,
                                         staged: stagedApp, backup: backup, relaunch: relaunch)
        try process.run()
    }

    /// 替换脚本：等 `pid` 退出 → 旧 App 挪到 `backup` → 新 App 放到原位置 → 去掉隔离属性 → 按需重新打开。
    /// 失败时把旧 App 放回去。路径、PID 都作为参数传入，不拼进脚本文本。
    static func replacementProcess(waitingFor pid: Int32, current: URL, staged: URL, backup: URL,
                                   relaunch: Bool) -> Process {
        let script = """
        pid="$1"; old="$2"; new="$3"; backup="$4"; relaunch="$5"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        if /bin/mv "$old" "$backup" && /bin/mv "$new" "$old"; then
            /usr/bin/xattr -dr com.apple.quarantine "$old" 2>/dev/null
            /bin/rm -rf "$backup"
        else
            [ -e "$backup" ] && [ ! -e "$old" ] && /bin/mv "$backup" "$old"
        fi
        [ "$relaunch" = "1" ] && /usr/bin/open "$old"
        exit 0
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(pid), current.path, staged.path, backup.path,
                             relaunch ? "1" : "0"]
        return process
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.unpackFailed }
    }
}

/// 把下载进度转给回调（0…1）。
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let handler: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(_ handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [handler] progress, _ in
            handler(progress.fractionCompleted)
        }
    }
}
