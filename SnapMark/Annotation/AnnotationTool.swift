import CoreGraphics
import Foundation

/// 绘图工具。
enum AnnotationTool: String, CaseIterable {
    case rectangle, ellipse, arrow, pen, highlighter, text, counter, mosaic

    init?(item: ToolbarItem) {
        switch item {
        case .rectangle: self = .rectangle
        case .ellipse: self = .ellipse
        case .arrow: self = .arrow
        case .pen: self = .pen
        case .highlighter: self = .highlighter
        case .counter: self = .counter
        case .text: self = .text
        case .mosaic: self = .mosaic
        default: return nil
        }
    }

    var toolbarItem: ToolbarItem {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .arrow: return .arrow
        case .pen: return .pen
        case .highlighter: return .highlighter
        case .counter: return .counter
        case .text: return .text
        case .mosaic: return .mosaic
        }
    }

    /// 单字母快捷键。
    init?(shortcut: String) {
        guard let tool = Self.allCases.first(where: { $0.toolbarItem.shortcutHint.lowercased() == shortcut.lowercased() })
        else { return nil }
        self = tool
    }

    /// 马赛克没有颜色。
    var usesColor: Bool { self != .mosaic }
}

/// 3 档粗细 / 字号。
enum SizeLevel: Int, CaseIterable {
    case small, medium, large
}

/// 预设颜色（8 个，默认红色）。
enum Palette {
    static let colors: [PaletteColor] = [
        PaletteColor(0xFF3B30), // 红
        PaletteColor(0xFF9500), // 橙
        PaletteColor(0xFFCC00), // 黄
        PaletteColor(0x34C759), // 绿
        PaletteColor(0x007AFF), // 蓝
        PaletteColor(0xAF52DE), // 紫
        PaletteColor(0x000000), // 黑
        PaletteColor(0xFFFFFF), // 白
    ]
    static let names = [String(localized: "红色"), String(localized: "橙色"), String(localized: "黄色"), String(localized: "绿色"), String(localized: "蓝色"), String(localized: "紫色"), String(localized: "黑色"), String(localized: "白色")]
    static let defaultIndex = 0
}

/// 某个工具当前的样式。
struct ToolStyle: Equatable {
    var size: SizeLevel
    var colorIndex: Int

    var color: PaletteColor { Palette.colors[min(max(colorIndex, 0), Palette.colors.count - 1)] }

    static let lineWidths: [CGFloat] = [2, 4, 8]
    static let fontSizes: [CGFloat] = [14, 20, 28]
    static let mosaicBrushWidths: [CGFloat] = [14, 26, 40]
    static let highlighterWidths: [CGFloat] = [10, 18, 28]
    static let counterDiameters: [CGFloat] = [20, 26, 34]

    var lineWidth: CGFloat { Self.lineWidths[size.rawValue] }
    var fontSize: CGFloat { Self.fontSizes[size.rawValue] }
    var mosaicBrushWidth: CGFloat { Self.mosaicBrushWidths[size.rawValue] }
    var highlighterWidth: CGFloat { Self.highlighterWidths[size.rawValue] }
    var counterDiameter: CGFloat { Self.counterDiameters[size.rawValue] }
    /// 马赛克块大小随粗细变化。
    var mosaicBlockSize: CGFloat { (mosaicBrushWidth / 2.5).rounded() }
}

/// 每个工具的样式记在 UserDefaults 里，下次截图沿用。
struct StyleStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func sizeKey(_ tool: AnnotationTool) -> String { "style.\(tool.rawValue).size" }
    private func colorKey(_ tool: AnnotationTool) -> String { "style.\(tool.rawValue).color" }

    func style(for tool: AnnotationTool) -> ToolStyle {
        let size = (defaults.object(forKey: sizeKey(tool)) as? Int).flatMap(SizeLevel.init(rawValue:)) ?? .medium
        let color = (defaults.object(forKey: colorKey(tool)) as? Int) ?? Self.defaultColorIndex(for: tool)
        return ToolStyle(size: size, colorIndex: color)
    }

    /// 荧光笔默认黄色，其余默认红色。
    static func defaultColorIndex(for tool: AnnotationTool) -> Int {
        tool == .highlighter ? 2 : Palette.defaultIndex
    }

    func setStyle(_ style: ToolStyle, for tool: AnnotationTool) {
        defaults.set(style.size.rawValue, forKey: sizeKey(tool))
        defaults.set(style.colorIndex, forKey: colorKey(tool))
    }
}
