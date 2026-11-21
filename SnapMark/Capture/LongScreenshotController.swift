import AppKit
import SwiftUI

/// 长截图：遮罩关闭后，在选区位置留下可点穿的边框，用户自己滚动页面，
/// 定时截取该区域并拼接；点「完成」后按普通截图输出（复制 / 保存 / 历史）。
///
/// 不需要辅助功能权限（不模拟滚动、不监听按键）。
@MainActor
final class LongScreenshotController {
    static let shared = LongScreenshotController()

    /// 截取间隔。
    static let interval: Duration = .milliseconds(120)

    private(set) var isActive = false
    private var captureService: CaptureService?
    private var region: CGRect = .zero
    private var displayID: CGDirectDisplayID = 0
    private var scale: CGFloat = 2
    private var stitcher: ScrollStitcher?
    private var loop: Task<Void, Never>?

    private var borderWindow: NSPanel?
    private var controlPanel: NSPanel?
    private let state = LongScreenshotState()

    /// `region`：AppKit 全局坐标（pt），已对齐到像素。
    func start(region: CGRect, displayID: CGDirectDisplayID, scale: CGFloat, captureService: CaptureService) {
        cancel()
        isActive = true
        self.region = region
        self.displayID = displayID
        self.scale = scale
        self.captureService = captureService
        stitcher = nil
        state.reset()

        showBorder()
        showControlPanel()
        Log.capture.notice("长截图开始：\(Int(region.width), privacy: .public) × \(Int(region.height), privacy: .public) pt")

        loop = Task { [weak self] in
            while let self, self.isActive, !Task.isCancelled {
                let stopwatch = Stopwatch()
                await self.captureOnce()
                let elapsed = Duration.milliseconds(Int(stopwatch.elapsedMs))
                if elapsed < Self.interval {
                    try? await Task.sleep(for: Self.interval - elapsed)
                }
            }
        }
    }

    private func captureOnce() async {
        guard let captureService else { return }
        let frame: CGImage
        do {
            frame = try await captureService.captureRegion(region, displayID: displayID, scale: scale)
        } catch {
            Log.capture.error("长截图截取失败：\(error.localizedDescription, privacy: .public)")
            return
        }
        guard isActive else { return }

        if stitcher == nil {
            stitcher = ScrollStitcher(firstFrame: frame)
            state.update(preview: frame, height: frame.height, status: .waiting)
            return
        }
        guard let stitcher else { return }
        // 比对和拷贝放到后台线程，不卡界面。
        let result = await Task.detached(priority: .userInitiated) { stitcher.add(frame) }.value
        guard isActive else { return }
        switch result {
        case .appended:
            state.update(preview: frame, height: stitcher.totalHeight, status: .scrolling)
        case .unchanged:
            break
        case .noMatch:
            state.update(preview: nil, height: stitcher.totalHeight, status: .tooFast)
        case .limitReached:
            state.update(preview: frame, height: stitcher.totalHeight, status: .full)
        case .sizeMismatch:
            break
        }
    }

    /// 完成：拼出长图并按设置输出。
    func finish() {
        guard isActive else { return }
        let stitcher = stitcher
        let region = region
        let scale = scale
        teardown()
        guard let image = stitcher?.makeImage() else {
            Toast.shared.show(String(localized: "长截图没有截到内容"), near: region)
            return
        }
        Log.capture.notice("长截图完成：\(image.width, privacy: .public) × \(image.height, privacy: .public) px")
        OutputPipeline.deliver(image, anchor: region, scale: scale)
    }

    func cancel() {
        guard isActive else { return }
        Log.capture.notice("长截图取消")
        teardown()
    }

    private func teardown() {
        isActive = false
        loop?.cancel()
        loop = nil
        stitcher = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlPanel?.orderOut(nil)
        controlPanel = nil
    }

    // MARK: 窗口

    private func showBorder() {
        let inset: CGFloat = -3
        let panel = NSPanel(contentRect: region.insetBy(dx: inset, dy: inset),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        let view = DashedBorderView(frame: CGRect(origin: .zero, size: panel.frame.size))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.orderFrontRegardless()
        borderWindow = panel
    }

    private func showControlPanel() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 260),
                            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = String(localized: "长截图")
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentViewController = NSHostingController(rootView: LongScreenshotPanelView(
            state: state,
            onFinish: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        ))

        // 放在选区右侧；放不下放左侧；再放不下放到选区内部右上角。
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.displayID == displayID }?.visibleFrame ?? region
        var origin = CGPoint(x: region.maxX + 12, y: region.maxY - size.height)
        if origin.x + size.width > screen.maxX {
            origin.x = region.minX - 12 - size.width
            if origin.x < screen.minX { origin.x = region.maxX - size.width - 12 }
        }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        controlPanel = panel
    }
}

/// 面板显示的状态。
@MainActor
final class LongScreenshotState: ObservableObject {
    enum Status {
        case waiting, scrolling, tooFast, full

        var text: String {
            switch self {
            case .waiting: return String(localized: "请向下滚动要截取的内容")
            case .scrolling: return String(localized: "继续滚动，完成后点「完成」")
            case .tooFast: return String(localized: "滚动太快了，请慢一点")
            case .full: return String(localized: "已达到最大高度")
            }
        }
    }

    @Published var preview: NSImage?
    @Published var height = 0
    @Published var status = Status.waiting

    func reset() {
        preview = nil
        height = 0
        status = .waiting
    }

    func update(preview frame: CGImage?, height: Int, status: Status) {
        if let frame { preview = NSImage(cgImage: frame, size: .zero) }
        self.height = height
        self.status = status
    }
}

private struct LongScreenshotPanelView: View {
    @ObservedObject var state: LongScreenshotState
    var onFinish: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                if let preview = state.preview {
                    Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit).padding(4)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 110)

            Text(verbatim: String(localized: "已拼接 \(String(state.height)) px"))
                .font(.system(.callout, design: .monospaced))
            Text(state.status.text)
                .font(.caption)
                .foregroundStyle(state.status == .tooFast ? Color.orange : Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "再按截图快捷键也可以完成"))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Button(String(localized: "取消"), action: onCancel)
                Spacer()
                Button(String(localized: "完成"), action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(width: 200)
    }
}

/// 长截图区域外的虚线边框（不接收鼠标，滚轮直接作用到下面的页面）。
private final class DashedBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        OverlayView.accentColor.setStroke()
        path.stroke()
    }
}
