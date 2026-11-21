import AppKit
import Combine

/// 检查更新（GitHub Releases）与端内更新。
///
/// - 自动检查：启动 15 秒后、之后每小时看一次，距上次检查满 24 小时才真正请求。
/// - 自动安装（默认开）：后台下载、校验、暂存；空闲时（没在截图、没有贴图和窗口）替换并重启，
///   或在退出时替换。没开自动安装、或者 App 不在「应用程序」文件夹里时，弹窗让用户选择。
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(Double)
        case ready(ReleaseInfo)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// 由 AppDelegate 提供：正在截图、有贴图或打开着窗口时不自动重启。
    var isBusy: () -> Bool = { false }

    nonisolated static let checkInterval: TimeInterval = 24 * 3600
    private var stagedApp: URL?
    private var replacementScheduled = false
    private var timers: [Timer] = []

    /// `owner/repo`，来自 Info.plist 的 `OneShotUpdateRepository`。
    var repository: String? {
        Bundle.main.object(forInfoDictionaryKey: "OneShotUpdateRepository") as? String
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var releasesPage: URL? {
        repository.flatMap { URL(string: "https://github.com/\($0)/releases") }
    }

    // MARK: 调度

    func start() {
        showUpdatedNoticeIfNeeded()
        let first = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
            MainActor.assumeIsolated { UpdateService.shared.autoCheckIfDue() }
        }
        let hourly = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateService.shared.autoCheckIfDue() }
        }
        // 已下载好的更新：每 5 分钟看一次是否空闲，空闲就安装。
        let idle = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateService.shared.installIfIdle() }
        }
        timers = [first, hourly, idle]
    }

    /// 距上次检查是否已满间隔。
    nonisolated static func isDue(lastCheck: Date?, now: Date = Date(), interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    func autoCheckIfDue() {
        guard Preferences.autoCheckUpdates, Self.isDue(lastCheck: Preferences.lastUpdateCheck) else { return }
        Task { await check(userInitiated: false) }
    }

    // MARK: 检查

    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading: return
        case .ready(let release):
            if userInitiated { presentReady(release) }
            return
        default: break
        }
        guard let repository else { return }
        state = .checking
        do {
            let release = try await fetchLatest(repository: repository)
            Preferences.lastUpdateCheck = Date()
            guard VersionNumber.isNewer(release.version, than: currentVersion) else {
                state = .upToDate
                Log.app.notice("检查更新：已是最新（\(self.currentVersion, privacy: .public)）")
                if userInitiated { presentUpToDate() }
                return
            }
            Log.app.notice("检查更新：发现 \(release.version, privacy: .public)")
            if !userInitiated, Preferences.skippedUpdateVersion == release.version {
                state = .available(release)
                return
            }
            state = .available(release)
            if !userInitiated, Preferences.autoInstallUpdates, UpdateInstaller.canInstallInPlace() {
                await download(release, installImmediately: false)
            } else {
                presentAvailable(release)
            }
        } catch {
            Log.app.error("检查更新失败：\(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            if userInitiated { presentFailure(error.localizedDescription) }
        }
    }

    private func fetchLatest(repository: String) async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw ReleaseInfo.ParseError.notARelease
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("1shot/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw UpdateError.noRelease
        }
        return try ReleaseInfo.parse(data)
    }

    enum UpdateError: LocalizedError {
        case noRelease
        var errorDescription: String? { String(localized: "还没有发布过版本。") }
    }

    // MARK: 下载与安装

    func download(_ release: ReleaseInfo, installImmediately: Bool) async {
        state = .downloading(0)
        do {
            let app = try await UpdateInstaller.downloadAndStage(release) { fraction in
                Task { @MainActor in
                    if case .downloading = UpdateService.shared.state {
                        UpdateService.shared.state = .downloading(fraction)
                    }
                }
            }
            stagedApp = app
            state = .ready(release)
            Log.app.notice("更新已下载并校验：\(release.version, privacy: .public)")
            if installImmediately {
                installNow(relaunch: true)
            } else {
                installIfIdle()
            }
        } catch {
            Log.app.error("下载更新失败：\(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            if installImmediately { presentFailure(error.localizedDescription) }
        }
    }

    /// 替换并重启（或退出时替换）。
    func installNow(relaunch: Bool) {
        guard let stagedApp, !replacementScheduled else { return }
        do {
            try UpdateInstaller.scheduleReplacement(with: stagedApp, relaunch: relaunch)
            replacementScheduled = true
            Preferences.updatedFromVersion = currentVersion
            Log.app.notice("开始安装更新（重启：\(relaunch, privacy: .public)）")
            if relaunch { NSApp.terminate(nil) }
        } catch {
            state = .failed(error.localizedDescription)
            presentFailure(error.localizedDescription)
        }
    }

    /// 端内滚动更新：已下载好、且用户没在用时安装并重启。
    func installIfIdle() {
        guard case .ready = state, Preferences.autoInstallUpdates, !isBusy() else { return }
        installNow(relaunch: true)
    }

    /// 退出时：有下载好的更新就替换（不重新打开）。
    func installOnQuit() {
        guard case .ready = state, !replacementScheduled else { return }
        installNow(relaunch: false)
    }

    // MARK: 提示

    private func showUpdatedNoticeIfNeeded() {
        guard let previous = Preferences.updatedFromVersion else { return }
        Preferences.updatedFromVersion = nil
        guard previous != currentVersion else { return }
        let screen = NSScreen.main?.visibleFrame ?? .zero
        Toast.shared.show(String(localized: "已更新到 1shot \(currentVersion)"),
                          near: CGRect(x: screen.midX, y: screen.maxY - 120, width: 1, height: 1))
    }

    private func presentAvailable(_ release: ReleaseInfo) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "发现新版本 1shot \(release.version)")
        var info = String(localized: "当前版本 \(currentVersion)。")
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { info += "\n\n" + String(notes.prefix(800)) }
        alert.informativeText = info
        let canInstall = UpdateInstaller.canInstallInPlace()
        alert.addButton(withTitle: canInstall ? String(localized: "立即更新") : String(localized: "前往下载"))
        alert.addButton(withTitle: String(localized: "稍后"))
        alert.addButton(withTitle: String(localized: "跳过此版本"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canInstall {
                Task { await download(release, installImmediately: true) }
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertThirdButtonReturn:
            Preferences.skippedUpdateVersion = release.version
        default:
            break
        }
    }

    private func presentReady(_ release: ReleaseInfo) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "1shot \(release.version) 已下载好")
        alert.informativeText = String(localized: "现在重启完成更新？也可以等 1shot 空闲或退出时自动安装。")
        alert.addButton(withTitle: String(localized: "立即重启"))
        alert.addButton(withTitle: String(localized: "稍后"))
        if alert.runModal() == .alertFirstButtonReturn { installNow(relaunch: true) }
    }

    private func presentUpToDate() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "已是最新版本")
        alert.informativeText = String(localized: "1shot \(currentVersion) 是目前的最新版本。")
        alert.runModal()
    }

    private func presentFailure(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "检查更新失败")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "好"))
        if let page = releasesPage {
            alert.addButton(withTitle: String(localized: "打开发布页"))
            if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(page) }
        } else {
            alert.runModal()
        }
    }

    /// 设置页显示的状态文字。
    var statusText: String {
        switch state {
        case .idle:
            if let last = Preferences.lastUpdateCheck {
                return String(localized: "上次检查：\(last.formatted(date: .abbreviated, time: .shortened))")
            }
            return String(localized: "还没有检查过更新")
        case .checking: return String(localized: "正在检查…")
        case .upToDate: return String(localized: "已是最新版本")
        case .available(let release): return String(localized: "发现新版本 \(release.version)")
        case .downloading(let fraction):
            let percent = "\(Int(fraction * 100))%"
            return String(localized: "正在下载… \(percent)")
        case .ready(let release): return String(localized: "\(release.version) 已下载，空闲或退出时安装")
        case .failed(let message): return message
        }
    }
}
