import AppKit
import SwiftUI
import Vision

/// 识别出的一行文字。`box` 为 Vision 的归一化坐标（左下原点，0…1）。
struct RecognizedLine: Equatable {
    var text: String
    var box: CGRect
}

/// 用 Vision 识别图片里的文字（简体中文、繁体中文、英文）。
enum TextRecognizer {
    static let languages = ["zh-Hans", "zh-Hant", "en-US"]

    static func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = languages
                request.automaticallyDetectsLanguage = true
                do {
                    // perform 是同步的，返回时结果已就绪。
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                    let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return RecognizedLine(text: candidate.string, box: observation.boundingBox)
                    }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 按阅读顺序排版：从上到下分行，同一行（垂直方向重叠过半）从左到右。
    /// 同行片段之间：两边都是 CJK 字符时直接相连，否则加空格。
    static func layout(_ lines: [RecognizedLine]) -> String {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let last = rows.last?.first, verticalOverlap(last.box, line.box) > 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.reduce(into: "") { result, line in
                if let lastChar = result.last, let firstChar = line.text.first,
                   !(lastChar.isCJK && firstChar.isCJK) {
                    result += " "
                }
                result += line.text
            }
        }.joined(separator: "\n")
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let base = min(a.height, b.height)
        return base > 0 ? overlap / base : 0
    }
}

private extension Character {
    var isCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3000...0x303F).contains(scalar.value) || (0xFF00...0xFFEF).contains(scalar.value)
        }
    }
}

// MARK: - 识别结果窗口

private struct OCRResultView: View {
    @State var text: String
    var onCopy: (String) -> Void
    var onClose: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 10) {
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            HStack {
                Text(copied ? String(localized: "已复制") : String(localized: "已自动复制全部文字，可编辑后再复制"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "关闭"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "复制")) {
                    onCopy(text)
                    copied = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(minWidth: 360, minHeight: 220)
    }
}

/// 识别结果窗口（浮动，可编辑后复制）。
@MainActor
final class OCRResultWindowController {
    static let shared = OCRResultWindowController()

    private var window: NSPanel?

    func show(text: String, near anchor: CGRect) {
        window?.close()
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "识别结果")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = NSHostingController(rootView: OCRResultView(
            text: text,
            onCopy: { Self.copy($0) },
            onClose: { [weak panel] in panel?.close() }
        ))

        // 放在选区右侧，放不下放左侧，保持在屏幕内。
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = CGPoint(x: anchor.maxX + 12, y: anchor.maxY - size.height)
        if origin.x + size.width > screen.maxX { origin.x = anchor.minX - 12 - size.width }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        panel.setFrameOrigin(origin)

        window = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
