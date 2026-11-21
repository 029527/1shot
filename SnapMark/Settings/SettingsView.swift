import AppKit
import KeyboardShortcuts
import SwiftUI

/// 设置界面（UserDefaults 保存，修改立即生效）。
struct SettingsView: View {
    @AppStorage(Preferences.Key.autoCopy) private var autoCopy = true
    @AppStorage(Preferences.Key.autoSave) private var autoSave = true
    @AppStorage(Preferences.Key.imageFormat) private var formatRaw = ImageFormat.png.rawValue
    @AppStorage(Preferences.Key.showToast) private var showToast = true
    @AppStorage(Preferences.Key.keepHistory) private var keepHistory = true

    @State private var saveDirectory = Preferences.saveDirectory
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchNeedsApproval = LaunchAtLogin.requiresApproval
    @State private var launchError: String?

    @AppStorage(Preferences.Key.decorationEnabled) private var decorationEnabled = false
    @AppStorage(Preferences.Key.cornerPercent) private var cornerPercent = 3.0
    @AppStorage(Preferences.Key.shadowLength) private var shadowLength = 20.0

    enum Tab: Hashable { case general, shortcuts, effects }

    @State private var tab: Tab

    init(tab: Tab = .general) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            generalTab.tabItem { Label("通用", systemImage: "gearshape") }.tag(Tab.general)
            shortcutsTab.tabItem { Label("快捷键", systemImage: "keyboard") }.tag(Tab.shortcuts)
            effectsTab.tabItem { Label("圆角与阴影", systemImage: "square.on.square.dashed") }.tag(Tab.effects)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshLaunchState()
        }
    }

    // MARK: 快捷键

    private var shortcutsTab: some View {
        Form {
            Section {
                shortcutRow("截图", name: .captureScreen,
                            detail: "选区后显示工具栏，可以标注、贴图、识别文字，按 Enter 完成。")
                shortcutRow("截图并复制", name: .captureAndCopy,
                            detail: "松开鼠标（或单击窗口）就完成，直接复制到剪贴板，不显示工具栏。")
                shortcutRow("贴图", name: .pinClipboard,
                            detail: "把剪贴板里的图片或文字贴到桌面；刚截的图会贴回原位置。剪贴板里没有可贴的内容时，贴最近一次截图。")
            } footer: {
                Text("点击右侧录制新的快捷键，按 Delete 清除。与其他 App 冲突时，请在其中一边改掉。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, name: KeyboardShortcuts.Name, detail: String) -> some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name)
        } label: {
            Text(title)
            Text(detail)
        }
    }

    // MARK: 圆角与阴影

    private var effectsTab: some View {
        Form {
            Section {
                Toggle("给截图加圆角和阴影", isOn: $decorationEnabled)
                LabeledContent("圆角") {
                    HStack {
                        Slider(value: $cornerPercent, in: ImageDecoration.cornerRange, step: 1)
                        Text(verbatim: "\(Int(cornerPercent))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!decorationEnabled)
                LabeledContent("阴影") {
                    HStack {
                        Slider(value: $shadowLength, in: ImageDecoration.shadowRange, step: 2)
                        Text(verbatim: "\(Int(shadowLength)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!decorationEnabled)
            } footer: {
                Text("圆角按截图短边的百分比计算。开启后，复制和自动保存的是四周透明的 PNG；贴图和截图历史保留原图。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("预览") {
                DecorationPreview(decoration: ImageDecoration(
                    isEnabled: decorationEnabled,
                    cornerRatio: cornerPercent / 100,
                    shadowLength: shadowLength
                ))
                .frame(maxWidth: .infinity)
                .frame(height: 190)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 通用

    private var generalTab: some View {
        Form {
            Section("完成截图后") {
                Toggle("自动复制到剪贴板", isOn: $autoCopy)
                Toggle("自动保存到文件", isOn: $autoSave)

                LabeledContent("保存目录") {
                    HStack(spacing: 8) {
                        Text(displayPath(saveDirectory))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(saveDirectory.path)
                        Button("选择…", action: chooseDirectory)
                        Button {
                            openDirectory()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("在访达中打开")
                    }
                }

                Picker("保存格式", selection: $formatRaw) {
                    Text("PNG").tag(ImageFormat.png.rawValue)
                    Text("JPG（质量 90%）").tag(ImageFormat.jpg.rawValue)
                }
                .pickerStyle(.segmented)

                Toggle("显示完成提示", isOn: $showToast)
                Toggle("保留截图历史（最近 \(HistoryStore.defaultLimit) 条）", isOn: $keepHistory)
            }

            Section("通用") {
                Toggle("开机时自动启动", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if launchNeedsApproval {
                    HStack {
                        Text("需要在「系统设置 › 通用 › 登录项」中允许 SnapMark。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("打开登录项设置") { LaunchAtLogin.openSystemSettings() }
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择保存目录"
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

    private func openDirectory() {
        if let url = try? Preferences.ensureSaveDirectory() {
            NSWorkspace.shared.open(url)
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
        saveDirectory = Preferences.saveDirectory
    }
}

/// 用一张示例图实际跑一遍 `ImageDecorator`，所见即所得。
private struct DecorationPreview: View {
    var decoration: ImageDecoration

    private static let scale: CGFloat = 2
    private static let sample = makeSample()

    var body: some View {
        let image = ImageDecorator.apply(Self.sample, decoration: decoration, scale: Self.scale)
        Image(nsImage: NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / Self.scale,
                                                            height: CGFloat(image.height) / Self.scale)))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    /// 示例截图：浅色窗口样式（标题栏 + 几行内容），200 × 120 pt。
    private static func makeSample() -> CGImage {
        let width = Int(200 * scale), height = Int(120 * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.91, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 98, width: 200, height: 22))
        for (index, color) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.79, 0.25)].enumerated() {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: 10 + CGFloat(index) * 14, y: 104, width: 10, height: 10))
        }
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.47, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 14, y: 70, width: 90, height: 12))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.81, blue: 0.84, alpha: 1))
        for row in 0..<3 {
            context.fill(CGRect(x: 14, y: 50 - CGFloat(row) * 16, width: CGFloat(170 - row * 30), height: 8))
        }
        return context.makeImage()!
    }
}

/// 用 AppKit 窗口承载 SwiftUI 设置界面。
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "SnapMark 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
