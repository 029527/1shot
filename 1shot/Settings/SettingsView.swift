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
        case .general: return String(localized: "通用")
        case .shortcuts: return String(localized: "快捷键")
        case .output: return String(localized: "完成截图后")
        case .effects: return String(localized: "圆角与阴影")
        case .about: return String(localized: "关于")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(localized: "开机启动、完成提示与截图历史。")
        case .shortcuts: return String(localized: "为不同的截图方式设置全局快捷键，在任何 App 里都能使用。")
        case .output: return String(localized: "截图完成时自动复制、自动保存，以及保存的位置和格式。")
        case .effects: return String(localized: "给复制和保存的截图加上圆角与投影，分享出去更好看。")
        case .about: return String(localized: "版本信息与权限状态。")
        }
    }

    /// 侧边栏用的线条图标（单色，跟随系统强调色）。
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .output: return "square.and.arrow.down"
        case .effects: return "square.on.square"
        case .about: return "info.circle"
        }
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
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
                    .padding(.vertical, 1)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(210)
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

/// 页面顶部：标题 + 一句说明，左对齐，不加卡片背景。
private struct PaneHeader: View {
    var pane: SettingsPane

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(pane.title)
                    .font(.title2.weight(.semibold))
                Text(pane.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }
}

/// 标题 + 说明 + 右侧控件的一行。
private struct SettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
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

    @State private var language = AppLanguage.current()
    /// 启动时的语言设置，与之不同时提示重启。
    @State private var launchLanguage = AppLanguage.current()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchNeedsApproval = LaunchAtLogin.requiresApproval
    @State private var launchError: String?

    var body: some View {
        Form {
            PaneHeader(pane: .general)

            Section {
                Picker(String(localized: "语言"), selection: Binding(get: { language }, set: { newValue in
                    language = newValue
                    newValue.apply()
                })) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.displayName).tag(option)
                    }
                }
                if language != launchLanguage {
                    HStack {
                        Text(String(localized: "重启 1shot 后生效。"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "立即重启")) { AppRelauncher.relaunch() }
                    }
                }
            }

            Section {
                SettingRow(title: String(localized: "开机时自动启动")) {
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if launchNeedsApproval {
                    HStack {
                        Label(String(localized: "需要在「系统设置 › 通用 › 登录项」中允许 1shot。"), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(String(localized: "打开登录项设置")) { LaunchAtLogin.openSystemSettings() }
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                SettingRow(title: String(localized: "显示完成提示"),
                        detail: String(localized: "复制、保存后在选区附近短暂提示。")) {
                    Toggle("", isOn: $showToast).labelsHidden().toggleStyle(.switch)
                }
            }

            Section {
                SettingRow(title: String(localized: "保留截图历史"),
                        detail: String(localized: "保存最近 \(HistoryStore.defaultLimit) 张截图，可以重新复制、贴图。")) {
                    Toggle("", isOn: $keepHistory).labelsHidden().toggleStyle(.switch)
                }
                HStack {
                    Spacer()
                    Button(String(localized: "打开截图历史…"), action: openHistory)
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
            launchError = String(localized: "设置开机启动失败：\(error.localizedDescription)")
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
                SettingRow(title: String(localized: "截图"),
                        detail: String(localized: "选区后显示工具栏，可以标注、贴图、识别文字。")) {
                    KeyboardShortcuts.Recorder(for: .captureScreen)
                }
                SettingRow(title: String(localized: "截图并复制"),
                        detail: String(localized: "松开鼠标（或单击窗口）立即完成并复制，不显示工具栏。")) {
                    KeyboardShortcuts.Recorder(for: .captureAndCopy)
                }
                SettingRow(title: String(localized: "贴图"),
                        detail: String(localized: "把剪贴板里的图片、文字或链接贴到桌面；刚截的图贴回原位置。")) {
                    KeyboardShortcuts.Recorder(for: .pinClipboard)
                }
            } footer: {
                Text(String(localized: "点击右侧录制新的快捷键，点 ⓧ 清除。与其他 App 冲突时，请在其中一边改掉。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "截图时")) {
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
        ("Enter / ⌘C", String(localized: "完成并复制")),
        ("⌘S", String(localized: "另存为")),
        ("⌘T", String(localized: "贴到桌面")),
        ("⌘R", String(localized: "识别文字")),
        ("⌘L", String(localized: "长截图")),
        ("⌘Z / ⇧⌘Z", String(localized: "撤销 / 重做")),
        ("Esc", String(localized: "取消")),
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
                SettingRow(title: String(localized: "自动复制到剪贴板"),
                        detail: String(localized: "同时写入 PNG 和 TIFF，粘贴到任何 App 都清晰。")) {
                    Toggle("", isOn: $autoCopy).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: String(localized: "自动保存到文件")) {
                    Toggle("", isOn: $autoSave).labelsHidden().toggleStyle(.switch)
                }
            }

            Section {
                LabeledContent(String(localized: "保存位置")) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(displayPath(saveDirectory))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(saveDirectory.path)
                        Button(String(localized: "更改…"), action: chooseDirectory)
                        Button {
                            if let url = try? Preferences.ensureSaveDirectory() { NSWorkspace.shared.open(url) }
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "在访达中打开"))
                    }
                }
                Picker(String(localized: "格式"), selection: $formatRaw) {
                    Text("PNG").tag(ImageFormat.png.rawValue)
                    Text("JPG").tag(ImageFormat.jpg.rawValue)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            } header: {
                Text(String(localized: "保存"))
            } footer: {
                Text(String(localized: "文件名形如「截图 2026-01-01 12.00.00.png」。JPG 质量 90%；开启圆角与阴影时始终保存为 PNG。"))
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
        panel.title = String(localized: "选择保存位置")
        panel.prompt = String(localized: "选择")
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
                SettingRow(title: String(localized: "给截图加圆角和阴影"),
                        detail: String(localized: "复制、保存的是四周透明的 PNG；贴图和截图历史保留原图。")) {
                    Toggle("", isOn: $enabled.animation(.easeInOut(duration: 0.2))).labelsHidden().toggleStyle(.switch)
                }
                // 只禁用滑块：开关本身必须始终可点，否则关闭状态下永远打不开。
                Group {
                    SliderRow(title: String(localized: "圆角"), value: $cornerPercent, range: ImageDecoration.cornerRange, step: 1,
                              format: { "\(Int($0))%" })
                    SliderRow(title: String(localized: "阴影"), value: $shadowLength, range: ImageDecoration.shadowRange, step: 2,
                              format: { "\(Int($0)) pt" })
                }
                .disabled(!enabled)
            } footer: {
                Text(String(localized: "圆角按截图短边的百分比计算，截图越大圆角越大。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(Preferences.Key.autoCheckUpdates) private var autoCheck = true
    @AppStorage(Preferences.Key.autoInstallUpdates) private var autoInstall = true

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "版本 \(short)（\(build)）")
    }

    private var isDownloading: Bool {
        if case .downloading = updates.state { return true }
        return false
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 80, height: 80)
                    Text("1shot")
                        .font(.title2.weight(.semibold))
                    Text(verbatim: version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section(String(localized: "更新")) {
                SettingRow(title: String(localized: "自动检查更新"), detail: String(localized: "每天检查一次 GitHub 上的新版本。")) {
                    Toggle("", isOn: $autoCheck).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: String(localized: "自动下载并安装"),
                           detail: String(localized: "在后台下载并校验，1shot 空闲或退出时安装，不打断你。")) {
                    Toggle("", isOn: $autoInstall).labelsHidden().toggleStyle(.switch)
                }
                HStack {
                    Text(verbatim: updates.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if case .ready = updates.state {
                        Button(String(localized: "立即重启")) { updates.installNow(relaunch: true) }
                    }
                    Button(String(localized: "检查更新")) {
                        Task { await updates.check(userInitiated: true) }
                    }
                    .disabled(updates.state == .checking || isDownloading)
                }
            }

            Section(String(localized: "权限")) {
                SettingRow(title: String(localized: "屏幕录制"),
                        detail: String(localized: "截图必需。截图只保存在你的电脑上，不会上传。")) {
                    if hasScreenRecording {
                        Label(String(localized: "已允许"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(String(localized: "前往允许")) { PermissionChecker.openScreenRecordingSettings() }
                    }
                }
                SettingRow(title: String(localized: "辅助功能"),
                        detail: String(localized: "不需要。1shot 不读取键盘输入，也不控制其他 App。")) {
                    Text(String(localized: "不需要"))
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
    static let size = CGSize(width: 740, height: 560)

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
        window?.bringToFront()
    }

    private func makeWindow(rootView: SettingsView) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "1shot 设置")
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.size)
        window.center()
        window.setFrameAutosaveName("1shotSettings")
        return window
    }
}
