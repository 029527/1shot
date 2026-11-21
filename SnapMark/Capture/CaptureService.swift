import AppKit
import ScreenCaptureKit

/// 一块屏幕的定格结果。
struct DisplayCapture {
    let displayID: CGDirectDisplayID
    let geometry: ScreenGeometry
    /// 原生像素分辨率的截图（不含鼠标指针、不含本 App 的窗口）。
    let image: CGImage
}

/// 一次截图的全部输入：所有屏幕的定格画面 + 当时的窗口列表。
struct CaptureResult {
    let displays: [DisplayCapture]
    let windows: WindowListSnapshot
    let converter: CoordinateConverter
    /// 各阶段耗时（毫秒），用于性能日志。
    let timings: CaptureTimings
}

struct CaptureTimings {
    var contentMs: Double = 0
    var windowListMs: Double = 0
    var screenshotMs: Double = 0
}

enum CaptureError: LocalizedError {
    case noDisplays
    case screenshotFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            return String(localized: "没有找到可以截图的显示器。")
        case .screenshotFailed(let underlying):
            return String(localized: "截图失败：\(underlying.localizedDescription)")
        }
    }
}

/// 负责截取所有显示器，并缓存 `SCShareableContent`（显示器信息）。
///
/// `SCShareableContent` 的获取要几十毫秒，所以在启动时、以及显示器变化时预先获取，
/// 按快捷键时直接用缓存。
@MainActor
final class CaptureService {
    private var cachedContent: SCShareableContent?
    private var loadingTask: Task<SCShareableContent, Error>?

    /// 丢弃缓存并在后台重新获取（启动、显示器插拔、分辨率变化时调用）。
    func refreshContent() {
        cachedContent = nil
        loadingTask = nil
        Task {
            do {
                _ = try await content()
            } catch {
                Log.capture.error("预取 SCShareableContent 失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 返回缓存的 `SCShareableContent`，没有则获取。并发调用会共享同一个请求。
    private func content() async throws -> SCShareableContent {
        if let cachedContent { return cachedContent }
        if let loadingTask { return try await loadingTask.value }

        let task = Task<SCShareableContent, Error> {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
        loadingTask = task
        do {
            let content = try await task.value
            // 期间可能被 refreshContent() 重置过，只在仍是同一个请求时写缓存。
            if loadingTask == task {
                cachedContent = content
                loadingTask = nil
            }
            return content
        } catch {
            if loadingTask == task { loadingTask = nil }
            throw error
        }
    }

    /// 截取所有显示器（原生像素分辨率，不带鼠标指针，排除本 App 的窗口），同时记下窗口列表。
    func captureAllScreens() async throws -> CaptureResult {
        var timings = CaptureTimings()
        let screens = NSScreen.screens
        let converter = CoordinateConverter.current

        // 1. 窗口列表：越早越好，代表「按下快捷键那一刻」。
        var stopwatch = Stopwatch()
        let windows = WindowListSnapshot.capture(excludingPID: getpid())
        timings.windowListMs = stopwatch.elapsedMs

        // 2. 显示器信息（通常命中缓存）。
        stopwatch = Stopwatch()
        var content = try await content()
        if !screens.allSatisfy({ screen in content.displays.contains { $0.displayID == screen.displayID } }) {
            // 缓存过期（显示器刚变化），强制刷新一次。
            Log.capture.notice("显示器缓存过期，重新获取")
            cachedContent = nil
            loadingTask = nil
            content = try await self.content()
        }
        timings.contentMs = stopwatch.elapsedMs

        // 3. 每块屏幕并行截图。
        let pid = getpid()
        let selfApp = content.applications.first { $0.processID == pid }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == pid }

        struct Job {
            let displayID: CGDirectDisplayID
            let geometry: ScreenGeometry
            let filter: SCContentFilter
            let configuration: SCStreamConfiguration
        }

        var jobs: [Job] = []
        for screen in screens {
            guard
                let displayID = screen.displayID,
                let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            let filter: SCContentFilter
            if let selfApp {
                filter = SCContentFilter(display: display, excludingApplications: [selfApp], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            }

            let geometry = ScreenGeometry(screen: screen)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(geometry.pixelSize.width)
            configuration.height = Int(geometry.pixelSize.height)
            configuration.showsCursor = false
            configuration.scalesToFit = false
            configuration.captureResolution = .best
            configuration.capturesAudio = false
            // 统一用 sRGB：放大镜取色、导出、粘贴到其他 App 时颜色一致。
            configuration.colorSpaceName = CGColorSpace.sRGB

            jobs.append(Job(displayID: displayID, geometry: geometry, filter: filter, configuration: configuration))
        }

        guard !jobs.isEmpty else { throw CaptureError.noDisplays }

        stopwatch = Stopwatch()
        var images: [CGDirectDisplayID: CGImage] = [:]
        do {
            try await withThrowingTaskGroup(of: (CGDirectDisplayID, CGImage).self) { group in
                for job in jobs {
                    let filter = job.filter
                    let configuration = job.configuration
                    let displayID = job.displayID
                    group.addTask {
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: filter,
                            configuration: configuration
                        )
                        return (displayID, image)
                    }
                }
                for try await (displayID, image) in group {
                    images[displayID] = image
                }
            }
        } catch {
            throw CaptureError.screenshotFailed(underlying: error)
        }
        timings.screenshotMs = stopwatch.elapsedMs

        let displays = jobs.compactMap { job -> DisplayCapture? in
            guard let image = images[job.displayID] else { return nil }
            return DisplayCapture(displayID: job.displayID, geometry: job.geometry, image: image)
        }

        return CaptureResult(displays: displays, windows: windows, converter: converter, timings: timings)
    }

    /// 截取某块屏幕上的一个区域（长截图用）。`globalRect` 为 AppKit 全局坐标（pt），不含本 App 的窗口。
    func captureRegion(_ globalRect: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) async throws -> CGImage {
        let content = try await content()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplays
        }
        let pid = getpid()
        let filter: SCContentFilter
        if let selfApp = content.applications.first(where: { $0.processID == pid }) {
            filter = SCContentFilter(display: display, excludingApplications: [selfApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // sourceRect：相对该显示器左上角的 pt 坐标。
        let cgRect = CoordinateConverter.current.cgRect(fromAppKit: globalRect)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = cgRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = Int((globalRect.width * scale).rounded())
        configuration.height = Int((globalRect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        configuration.colorSpaceName = CGColorSpace.sRGB
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw CaptureError.screenshotFailed(underlying: error)
        }
    }
}
