import AppKit
import ImageIO
import SwiftUI

/// 截图历史窗口：缩略图网格，可复制、贴图、在访达中显示、删除。
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var copiedID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)]

    var body: some View {
        Group {
            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "还没有截图历史"))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "完成、另存为、贴图和长截图都会记录在这里（最多 \(store.limit) 条）。"))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.items) { item in
                            HistoryCard(item: item, url: store.url(for: item), copied: copiedID == item.id,
                                        onCopy: { copy(item) },
                                        onPin: { pin(item) },
                                        onReveal: { NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)]) },
                                        onDelete: { store.remove(item) })
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .toolbar {
            SwiftUI.ToolbarItem(placement: .automatic) {
                Button(String(localized: "清空历史"), role: .destructive) { confirmClear() }
                    .disabled(store.items.isEmpty)
            }
        }
    }

    private func copy(_ item: HistoryItem) {
        guard let image = store.image(for: item) else { return }
        PasteboardWriter.write(image)
        copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == item.id { copiedID = nil }
        }
    }

    private func pin(_ item: HistoryItem) {
        guard let image = store.image(for: item) else { return }
        PinManager.shared.pin(image, scale: CGFloat(item.scale))
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = String(localized: "清空全部截图历史？")
        alert.informativeText = String(localized: "将删除 \(store.items.count) 张历史截图，不影响保存目录里的文件。此操作无法撤销。")
        alert.addButton(withTitle: String(localized: "清空"))
        alert.addButton(withTitle: String(localized: "取消"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.removeAll()
        }
    }
}

private struct HistoryCard: View {
    let item: HistoryItem
    let url: URL
    let copied: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        // 按当前语言的习惯排列（中文「11月22日 05:01:02」，英文「Nov 22, 05:01:02」）。
        formatter.setLocalizedDateFormatFromTemplate("MMMdHHmmss")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                }
                if copied {
                    Text(String(localized: "已复制"))
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 140)
            .onTapGesture(count: 2, perform: onCopy)

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.dateFormatter.string(from: item.date))
                        .font(.callout)
                    Text(verbatim: "\(item.width) × \(item.height)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                iconButton("doc.on.doc", String(localized: "复制（双击缩略图也可以）"), onCopy)
                iconButton("pin", String(localized: "贴图到桌面"), onPin)
                iconButton("folder", String(localized: "在访达中显示"), onReveal)
                iconButton("trash", String(localized: "删除"), onDelete)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(hovering ? 0.6 : 0), lineWidth: 1.5))
        .onHover { hovering = $0 }
        .contextMenu {
            Button(String(localized: "复制"), action: onCopy)
            Button(String(localized: "贴图到桌面"), action: onPin)
            Button(String(localized: "在访达中显示"), action: onReveal)
            Divider()
            Button(String(localized: "删除"), role: .destructive, action: onDelete)
        }
        .task(id: item.id) {
            thumbnail = await Self.loadThumbnail(url)
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private static func loadThumbnail(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 520,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }
}

/// 历史窗口。
@MainActor
final class HistoryWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: HistoryView(store: .shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "截图历史")
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(CGSize(width: 760, height: 540))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.bringToFront()
    }
}
