import AppKit

/// 完成截图后的输出：剪贴板、自动保存、另存为、完成提示。
@MainActor
enum OutputPipeline {
    /// 完成（Enter / 双击 / ✓ / ⌘C）：按设置复制、保存，然后在选区附近提示。
    /// 编码在后台进行，不阻塞遮罩关闭。
    static func deliver(_ image: CGImage, anchor: CGRect) {
        let copy = Preferences.autoCopy
        let save = Preferences.autoSave
        let format = Preferences.imageFormat
        let directory = Preferences.saveDirectory
        let showToast = Preferences.showToast
        let date = Date()
        let stopwatch = Stopwatch()

        Task.detached(priority: .userInitiated) {
            let png = (copy || (save && format == .png)) ? ImageEncoder.data(for: image, format: .png) : nil

            if copy {
                let tiff = ImageEncoder.tiffData(for: image)
                await MainActor.run {
                    PasteboardWriter.write(png: png, tiff: tiff)
                    Log.app.notice("已写入剪贴板（\(stopwatch.elapsedMs, format: .fixed(precision: 0), privacy: .public) ms）")
                }
            }

            var saveError: Error?
            if save {
                do {
                    let url = try FileSaver.save(image, format: format, directory: directory, date: date,
                                                 encoded: format == .png ? png : nil)
                    Log.app.notice("已保存：\(url.lastPathComponent, privacy: .public)")
                } catch {
                    saveError = error
                    Log.app.error("保存失败：\(error.localizedDescription, privacy: .public)")
                }
            }

            let finalError = saveError
            await MainActor.run {
                if let saveError = finalError {
                    Toast.shared.show("保存失败：\(saveError.localizedDescription)", near: anchor)
                    return
                }
                guard showToast, let message = toastMessage(copied: copy, saved: save) else { return }
                Toast.shared.show(message, near: anchor)
            }
        }
    }

    nonisolated static func toastMessage(copied: Bool, saved: Bool) -> String? {
        switch (copied, saved) {
        case (true, true): return "已复制并保存"
        case (true, false): return "已复制"
        case (false, true): return "已保存"
        case (false, false): return nil
        }
    }

    /// 另存为（工具栏「保存」/ ⌘S）：同时复制到剪贴板，然后弹出 NSSavePanel。
    static func saveAs(_ image: CGImage, anchor: CGRect, completion: @escaping () -> Void) {
        PasteboardWriter.write(image)

        let format = Preferences.imageFormat
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.nameFieldStringValue = FileNamer.fileName(for: Date(), fileExtension: format.fileExtension)
        panel.directoryURL = try? Preferences.ensureSaveDirectory()
        panel.allowedContentTypes = [ImageFormat.png.utType, ImageFormat.jpg.utType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.level = .modalPanel

        NSApp.activate()
        panel.begin { response in
            defer { completion() }
            guard response == .OK, let url = panel.url else {
                if Preferences.showToast { Toast.shared.show("已复制", near: anchor) }
                return
            }
            do {
                try FileSaver.write(image, format: ImageFormat(fileExtension: url.pathExtension), to: url)
                if Preferences.showToast { Toast.shared.show("已复制并保存", near: anchor) }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
