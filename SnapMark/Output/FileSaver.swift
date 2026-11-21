import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 图片编码。
enum ImageEncoder {
    static func data(for image: CGImage, format: ImageFormat, jpegQuality: CGFloat = Preferences.jpegQuality) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil)
        else { return nil }
        var properties: [CFString: Any] = [:]
        if format == .jpg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func tiffData(for image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).tiffRepresentation
    }
}

enum FileSaverError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "图片编码失败。"
        }
    }
}

/// 写入保存目录。
enum FileSaver {
    /// 保存到目录（不存在就创建），返回实际写入的文件。
    @discardableResult
    static func save(
        _ image: CGImage, format: ImageFormat, directory: URL, date: Date = Date(), encoded: Data? = nil
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = FileNamer.uniqueURL(in: directory, date: date, fileExtension: format.fileExtension)
        try write(image, format: format, to: url, encoded: encoded)
        return url
    }

    static func write(_ image: CGImage, format: ImageFormat, to url: URL, encoded: Data? = nil) throws {
        guard let data = encoded ?? ImageEncoder.data(for: image, format: format) else {
            throw FileSaverError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
    }
}

/// 写剪贴板：先 clearContents，再同时写入 PNG 和 TIFF。
enum PasteboardWriter {
    @MainActor
    static func write(png: Data?, tiff: Data?, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png { item.setData(png, forType: .png) }
        if let tiff { item.setData(tiff, forType: .tiff) }
        pasteboard.writeObjects([item])
    }

    @MainActor
    static func write(_ image: CGImage, to pasteboard: NSPasteboard = .general) {
        write(png: ImageEncoder.data(for: image, format: .png), tiff: ImageEncoder.tiffData(for: image), to: pasteboard)
    }
}
