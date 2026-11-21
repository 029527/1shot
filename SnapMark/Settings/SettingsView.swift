import AppKit
import KeyboardShortcuts
import SwiftUI

// MARK: - 页面

/// 设置的各个页面（左侧边栏）。
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, output, effects, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .shortcuts: return "快捷键"
        case .output: return "完成截图后"
        case .effects: return "圆角与阴影"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "开机启动、完成提示与截图历史。"
        case .shortcuts: return "为不同的截图方式设置全局快捷键，在任何 App 里都能使用。"
        case .output: return "截图完成时自动复制、自动保存，以及保存的位置和格式。"
        case .effects: return "给复制和保存的截图加上圆角与投影，分享出去更好看。"
        case .about: return "版本信息与权限状态。"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "command"
        case .output: return "square.and.arrow.down.fill"
        case .effects: return "square.on.square.squareshape.controlhandles"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.55, green: 0.56, blue: 0.6)
        case .shortcuts: return Color(red: 0.2, green: 0.47, blue: 0.96)
        case .output: return Color(red: 0.2, green: 0.72, blue: 0.4)
        case .effects: return Color(red: 0.6, green: 0.36, blue: 0.95)
        case .about: return Color(red: 0.4, green: 0.42, blue: 0.47)
        }
    }
}

/// 系统设置风格的圆角方块图标。
struct SettingsIcon: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

// MARK: - 根视图

/// 设置界面：左侧边栏 + 右侧分组表单（与「系统设置」一致）。修改立即生效。
struct SettingsView: View {
    @State private var pane: SettingsPane?
    var openHistory: () -> Void = {}

    init(pane: SettingsPane = .general, openHistory: @escaping () -> Void = {}) {
        _pane = State(initialValue: pane)
        self.openHistory = openHistory
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(symbol: pane.symbol, tint: pane.tint)
                }
                .tag(pane)
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane(openHistory: openHistory)
                case .shortcuts: ShortcutsPane()
                case .output: OutputPane()
                case .effects: EffectsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
    }
}

/// 页面顶部：大图标 + 标题 + 说明，居中。
private struct PaneHeader: View {
    var pane: SettingsPane

    var body: some View {
        Section {
            VStack(spacing: 8) {
                SettingsIcon(symbol: pane.symbol, tint: pane.tint, size: 52)
                Text(pane.title)
                    .font(.title2.weight(.semibold))
                Text(pane.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

/// 带小图标、标题和说明的一行。
private struct IconRow<Trailing: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsIcon(symbol: symbol, tint: tint, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 通用

private struct GeneralPane: View {
    var openHistory: () -> Void

    @AppStorage(Preferences.Key.showToast) private var showToast = true
    @AppStorage(Preferences.Key.keepHistory) private var keepHistory = true

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchNeedsApproval = LaunchAtLogin.requiresApproval
    @State private var launchError: String?

    var body: some View {
        Form {
            PaneHeader(pane: .general)

            Section {
                IconRow(symbol: "power", tint: .orange, title: "开机时自动启动") {
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if launchNeedsApproval {
                    HStack {
                        Label("需要在「系统设置 › 通用 › 登录项」中允许 SnapMark。", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("打开登录项设置") { LaunchAtLogin.openSystemSettings() }
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                IconRow(symbol: "bell.badge.fill", tint: .red, title: "显示完成提示",
                        detail: "复制、保存后在选区附近短暂提示。") {
                    Toggle("", isOn: $showToast).labelsHidden().toggleStyle(.switch)
                }
            }

            Section {
                IconRow(symbol: "clock.arrow.circlepath", tint: .teal, title: "保留截图历史",
                        detail: "保存最近 \(HistoryStore.defaultLimit) 张截图，可以重新复制、贴图。") {
                    Toggle("", isOn: $keepHistory).labelsHidden().toggleStyle(.switch)
                }
                HStack {
                    Spacer()
                    Button("打开截图历史…", action: openHistory)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshLaunchState()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchError = nil
        } catch {
            launchError = "设置开机启动失败：\(error.localizedDescription)"
        }
        refreshLaunchState()
    }

    private func refreshLaunchState() {
        launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.requiresApproval
        launchNeedsApproval = LaunchAtLogin.requiresApproval
    }
}

// MARK: - 快捷键

private struct ShortcutsPane: View {
    var body: some View {
        Form {
            PaneHeader(pane: .shortcuts)

            Section {
                IconRow(symbol: "crop", tint: .blue, title: "截图",
                        detail: "选区后显示工具栏，可以标注、贴图、识别文字。") {
                    KeyboardShortcuts.Recorder(for: .captureScreen)
                }
                IconRow(symbol: "doc.on.clipboard.fill", tint: .green, title: "截图并复制",
                        detail: "松开鼠标（或单击窗口）立即完成并复制，不显示工具栏。") {
                    KeyboardShortcuts.Recorder(for: .captureAndCopy)
                }
                IconRow(symbol: "pin.fill", tint: .pink, title: "贴图",
                        detail: "把剪贴板里的图片、文字或链接贴到桌面；刚截的图贴回原位置。") {
                    KeyboardShortcuts.Recorder(for: .pinClipboard)
                }
            } footer: {
                Text("点击右侧录制新的快捷键，点 ⓧ 清除。与其他 App 冲突时，请在其中一边改掉。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("截图时") {
                ForEach(Self.tips, id: \.0) { keys, text in
                    LabeledContent(text) {
                        Text(keys)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.07)))
                    }
                }
            }
        }
    }

    private static let tips: [(String, String)] = [
        ("Enter / ⌘C", "完成并复制"),
        ("⌘S", "另存为"),
        ("⌘T", "贴到桌面"),
        ("⌘R", "识别文字"),
        ("⌘L", "长截图"),
        ("⌘Z / ⇧⌘Z", "撤销 / 重做"),
        ("Esc", "取消"),
    ]
}

// MARK: - 完成截图后

private struct OutputPane: View {
    @AppStorage(Preferences.Key.autoCopy) private var autoCopy = true
    @AppStorage(Preferences.Key.autoSave) private var autoSave = true
    @AppStorage(Preferences.Key.imageFormat) private var formatRaw = ImageFormat.png.rawValue
    @State private var saveDirectory = Preferences.saveDirectory

    var body: some View {
        Form {
            PaneHeader(pane: .output)

            Section {
                IconRow(symbol: "doc.on.doc.fill", tint: .blue, title: "自动复制到剪贴板",
                        detail: "同时写入 PNG 和 TIFF，粘贴到任何 App 都清晰。") {
                    Toggle("", isOn: $autoCopy).labelsHidden().toggleStyle(.switch)
                }
                IconRow(symbol: "externaldrive.fill", tint: .indigo, title: "自动保存到文件") {
                    Toggle("", isOn: $autoSave).labelsHidden().toggleStyle(.switch)
                }
            }

            Section {
                LabeledContent("保存位置") {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(displayPath(saveDirectory))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(saveDirectory.path)
                        Button("更改…", action: chooseDirectory)
                        Button {
                            if let url = try? Preferences.ensureSaveDirectory() { NSWorkspace.shared.open(url) }
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderless)
                        .help("在访达中打开")
                    }
                }
                Picker("格式", selection: $formatRaw) {
                    Text("PNG").tag(ImageFormat.png.rawValue)
                    Text("JPG").tag(ImageFormat.jpg.rawValue)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            } header: {
                Text("保存")
            } footer: {
                Text("文件名形如「截图 2026-01-01 12.00.00.png」。JPG 质量 90%；开启圆角与阴影时始终保存为 PNG。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!autoSave)
        }
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择保存位置"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Preferences.saveDirectory = url
        saveDirectory = url
    }
}

// MARK: - 圆角与阴影

private struct EffectsPane: View {
    @AppStorage(Preferences.Key.decorationEnabled) private var enabled = false
    @AppStorage(Preferences.Key.cornerPercent) private var cornerPercent = 3.0
    @AppStorage(Preferences.Key.shadowLength) private var shadowLength = 20.0

    var body: some View {
        Form {
            PaneHeader(pane: .effects)

            Section {
                DecorationPreview(decoration: ImageDecoration(
                    isEnabled: enabled, cornerRatio: cornerPercent / 100, shadowLength: shadowLength
                ))
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
            }

            Section {
                IconRow(symbol: "sparkles", tint: .purple, title: "给截图加圆角和阴影",
                        detail: "复制、保存的是四周透明的 PNG；贴图和截图历史保留原图。") {
                    Toggle("", isOn: $enabled.animation(.easeInOut(duration: 0.2))).labelsHidden().toggleStyle(.switch)
                }
                SliderRow(title: "圆角", value: $cornerPercent, range: ImageDecoration.cornerRange, step: 1,
                          format: { "\(Int($0))%" })
                SliderRow(title: "阴影", value: $shadowLength, range: ImageDecoration.shadowRange, step: 2,
                          format: { "\(Int($0)) pt" })
            } footer: {
                Text("圆角按截图短边的百分比计算，截图越大圆角越大。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)
        }
    }
}

private struct SliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 220)
                Text(verbatim: format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

/// 用示例图实际跑一遍 `ImageDecorator`，放在柔和的渐变背景上，所见即所得。
private struct DecorationPreview: View {
    var decoration: ImageDecoration

    private static let scale: CGFloat = 2
    private static let sample = makeSample()

    var body: some View {
        let image = ImageDecorator.apply(Self.sample, decoration: decoration, scale: Self.scale)
        ZStack {
            LinearGradient(colors: [Color(red: 0.78, green: 0.86, blue: 1), Color(red: 0.93, green: 0.84, blue: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(nsImage: NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / Self.scale,
                                                                height: CGFloat(image.height) / Self.scale)))
                .interpolation(.high)
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 示例截图：浅色窗口样式（标题栏 + 几行内容），200 × 120 pt。
    private static func makeSample() -> CGImage {
        let width = Int(200 * scale), height = Int(120 * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 98, width: 200, height: 22))
        for (index, color) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.79, 0.25)].enumerated() {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: 10 + CGFloat(index) * 14, y: 104, width: 10, height: 10))
        }
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.47, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 14, y: 70, width: 90, height: 12))
        context.setFillColor(CGColor(srgbRed: 0.82, green: 0.83, blue: 0.86, alpha: 1))
        for row in 0..<3 {
            context.fill(CGRect(x: 14, y: 50 - CGFloat(row) * 16, width: CGFloat(170 - row * 30), height: 8))
        }
        return context.makeImage()!
    }
}

// MARK: - 关于

private struct AboutPane: View {
    @State private var hasScreenRecording = PermissionChecker.hasScreenRecordingAccess

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "版本 \(short)（\(build)）"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    // App 还没有正式图标，先用与侧边栏一致的图标。
                    SettingsIcon(symbol: "scissors", tint: Color(red: 0.2, green: 0.47, blue: 0.96), size: 64)
                    Text("SnapMark")
                        .font(.title2.weight(.semibold))
                    Text(verbatim: version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section("权限") {
                IconRow(symbol: "rectangle.dashed.badge.record", tint: .red, title: "屏幕录制",
                        detail: "截图必需。截图只保存在你的电脑上，不会上传。") {
                    if hasScreenRecording {
                        Label("已允许", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("前往允许") { PermissionChecker.openScreenRecordingSettings() }
                    }
                }
                IconRow(symbol: "hand.raised.fill", tint: .blue, title: "辅助功能",
                        detail: "不需要。SnapMark 不读取键盘输入，也不控制其他 App。") {
                    Text("不需要")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasScreenRecording = PermissionChecker.hasScreenRecordingAccess
        }
    }
}

// MARK: - 窗口

/// 用 AppKit 窗口承载 SwiftUI 设置界面：透明标题栏，侧边栏延伸到顶部。
@MainActor
final class SettingsWindowController {
    static let size = CGSize(width: 720, height: 560)

    var openHistory: () -> Void = {}
    private var window: NSWindow?

    func show(pane: SettingsPane? = nil) {
        if window == nil || pane != nil {
            let rootView = SettingsView(pane: pane ?? .general, openHistory: { [weak self] in self?.openHistory() })
            if let window {
                window.contentViewController = NSHostingController(rootView: rootView)
            } else {
                window = makeWindow(rootView: rootView)
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(rootView: SettingsView) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapMark 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.size)
        window.center()
        window.setFrameAutosaveName("SnapMarkSettings")
        return window
    }
}
