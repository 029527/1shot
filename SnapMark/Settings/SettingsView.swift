import AppKit
import KeyboardShortcuts
import SwiftUI

/// 设置界面（UserDefaults 保存，修改立即生效）。
struct SettingsView: View {
    @AppStorage(Preferences.Key.autoCopy) private var autoCopy = true
    @AppStorage(Preferences.Key.autoSave) private var autoSave = true
    @AppStorage(Preferences.Key.imageFormat) private var formatRaw = ImageFormat.png.rawValue
    @AppStorage(Preferences.Key.showToast) private var showToast = true

    @State private var saveDirectory = Preferences.saveDirectory
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchNeedsApproval = LaunchAtLogin.requiresApproval
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("快捷键") {
                KeyboardShortcuts.Recorder("截图：", name: .captureScreen)
            }

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
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshLaunchState()
        }
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
