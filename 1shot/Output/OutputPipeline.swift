import AppKit

/// 完成截图后的输出：剪贴板、自动保存、另存为、截图历史、完成提示。
@MainActor
enum OutputPipeline {
    /// 最近一次完成的截图（快速贴图用）：原图（不含圆角阴影）、选区位置，以及写入剪贴板后的 changeCount。
    struct LastCapture {
        let image: CGImage
        let anchor: CGRect
        let scale: CGFloat
        var pasteboardChangeCount: Int?
    }

    private(set) static var lastCapture: LastCapture?

    /// 完成（Enter / 双击 / ✓ / ⌘C）：按设置复制、保存，然后在选区附近提示。
    /// 编码在后台进行，不阻塞遮罩关闭。`scale` 为截图所在屏幕的 scale（写入历史）。
    /// `forceCopy`：「截图并复制」模式下无论设置如何都复制。
    /// 开启圆角阴影时，复制和保存的是加工后的 PNG；截图历史保留原图。
    static func deliver(_ image: CGImage, anchor: CGRect, scale: CGFloat, forceCopy: Bool = false) {
        let copy = forceCopy || Preferences.autoCopy
        let save = Preferences.autoSave
        let keepHistory = Preferences.keepHistory
        let decoration = Preferences.decoration
        // 圆角阴影需要透明背景，自动保存一律用 PNG。
        let format = decoration.isEffective ? .png : Preferences.imageFormat
        let directory = Preferences.saveDirectory
        let showToast = Preferences.showToast
        let date = Date()
        let stopwatch = Stopwatch()
        lastCapture = LastCapture(image: image, anchor: anchor, scale: scale)

        Task.detached(priority: .userInitiated) {
            let output = ImageDecorator.apply(image, decoration: decoration, scale: scale)
            let decorated = output !== image
            let needsPNG = copy || (save && format == .png)
            let png = needsPNG ? ImageEncoder.data(for: output, format: .png) : nil
            // 历史保留原图：没加工时直接复用同一份 PNG。
            var historyPNG: Data?
            if keepHistory {
                historyPNG = (decorated ? nil : png) ?? ImageEncoder.data(for: image, format: .png)
            }

            if copy {
                let tiff = ImageEncoder.tiffData(for: output)
                await MainActor.run {
                    PasteboardWriter.write(png: png, tiff: tiff)
                    lastCapture?.pasteboardChangeCount = NSPasteboard.general.changeCount
                    Log.app.notice("已写入剪贴板（\(stopwatch.elapsedMs, format: .fixed(precision: 0), privacy: .public) ms）")
                }
            }

            var saveError: Error?
            if save {
                do {
                    let url = try FileSaver.save(output, format: format, directory: directory, date: date,
                                                 encoded: format == .png ? png : nil)
                    Log.app.notice("已保存：\(url.lastPathComponent, privacy: .public)")
                } catch {
                    saveError = error
                    Log.app.error("保存失败：\(error.localizedDescription, privacy: .public)")
                }
            }

            let finalError = saveError
            let finalHistoryPNG = historyPNG
            await MainActor.run {
                if let historyPNG = finalHistoryPNG {
                    addToHistory(png: historyPNG, image: image, scale: scale, date: date)
                }
                if let saveError = finalError {
                    Toast.shared.show(String(localized: "保存失败：\(saveError.localizedDescription)"), near: anchor)
                    return
                }
                guard showToast, let message = toastMessage(copied: copy, saved: save) else { return }
                Toast.shared.show(message, near: anchor)
            }
        }
    }

    nonisolated static func toastMessage(copied: Bool, saved: Bool) -> String? {
        switch (copied, saved) {
        case (true, true): return String(localized: "已复制并保存")
        case (true, false): return String(localized: "已复制")
        case (false, true): return String(localized: "已保存")
        case (false, false): return nil
        }
    }

    /// 只记入截图历史（贴图时用），编码在后台进行。
    static func recordHistory(_ image: CGImage, scale: CGFloat) {
        guard Preferences.keepHistory else { return }
        let date = Date()
        Task.detached(priority: .utility) {
            guard let png = ImageEncoder.data(for: image, format: .png) else { return }
            await MainActor.run {
                addToHistory(png: png, image: image, scale: scale, date: date)
            }
        }
    }

    private static func addToHistory(png: Data, image: CGImage, scale: CGFloat, date: Date) {
        do {
            try HistoryStore.shared.add(pngData: png, width: image.width, height: image.height,
                                        scale: Double(scale), date: date)
        } catch {
            Log.app.error("写入截图历史失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 另存为（工具栏「保存」/ ⌘S）：同时复制到剪贴板，然后弹出 NSSavePanel。
    static func saveAs(_ original: CGImage, anchor: CGRect, scale: CGFloat, completion: @escaping () -> Void) {
        let decoration = Preferences.decoration
        let image = ImageDecorator.apply(original, decoration: decoration, scale: scale)
        let png = ImageEncoder.data(for: image, format: .png)
        PasteboardWriter.write(png: png, tiff: ImageEncoder.tiffData(for: image))
        lastCapture = LastCapture(image: original, anchor: anchor, scale: scale,
                                  pasteboardChangeCount: NSPasteboard.general.changeCount)
        if Preferences.keepHistory {
            let historyPNG = image === original ? png : ImageEncoder.data(for: original, format: .png)
            if let historyPNG {
                addToHistory(png: historyPNG, image: original, scale: scale, date: Date())
            }
        }

        let format = decoration.isEffective ? .png : Preferences.imageFormat
        let panel = NSSavePanel()
        panel.title = String(localized: "保存截图")
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
                if Preferences.showToast { Toast.shared.show(String(localized: "已复制"), near: anchor) }
                return
            }
            do {
                let format = ImageFormat(fileExtension: url.pathExtension)
                try FileSaver.write(image, format: format, to: url, encoded: format == .png ? png : nil)
                if Preferences.showToast { Toast.shared.show(String(localized: "已复制并保存"), near: anchor) }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
