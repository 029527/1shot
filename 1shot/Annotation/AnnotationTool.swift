import CoreGraphics
import Foundation

/// 绘图工具。
enum AnnotationTool: String, CaseIterable {
    case rectangle, ellipse, arrow, pen, highlighter, text, counter, mosaic, spotlight, watermark

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
        case .spotlight: self = .spotlight
        case .watermark: self = .watermark
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
        case .spotlight: return .spotlight
        case .watermark: return .watermark
        }
    }

    /// 单字母快捷键。
    init?(shortcut: String) {
        guard let tool = Self.allCases.first(where: { $0.toolbarItem.shortcutHint.lowercased() == shortcut.lowercased() })
        else { return nil }
        self = tool
    }

    /// 马赛克、高亮没有颜色。
    var usesColor: Bool { self != .mosaic && self != .spotlight }

    /// 属性条是否显示粗细（高亮、水印没有；马赛克只有画笔方式有）。
    func usesSize(_ options: ToolOptions) -> Bool {
        switch self {
        case .spotlight, .watermark: return false
        case .mosaic: return options.mosaicMode == .brush
        default: return true
        }
    }

    /// 属性条上滑块的含义（nil 表示没有滑块）。
    var amountTitle: String? {
        switch self {
        case .spotlight, .watermark: return String(localized: "不透明度")
        case .mosaic: return String(localized: "强度")
        default: return nil
        }
    }

    /// 只作用于整张图、不需要在画布上拖动的工具。
    var isDocumentLevel: Bool { self == .watermark }
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

/// 高亮区域的形状。
enum SpotlightShapeKind: Int, CaseIterable {
    case rectangle, ellipse, roundedRectangle
}

/// 马赛克效果：像素化 / 模糊。
enum MosaicEffect: Int, CaseIterable {
    case pixelate, blur
}

/// 马赛克方式：画笔涂抹 / 框选区域。
enum MosaicMode: Int, CaseIterable {
    case brush, area
}

/// 工具专属选项（高亮、马赛克、水印）。
struct ToolOptions: Equatable {
    var spotlightShape: SpotlightShapeKind = .rectangle
    var mosaicEffect: MosaicEffect = .pixelate
    var mosaicMode: MosaicMode = .brush
    /// 0…1：高亮 = 框外变暗的不透明度；马赛克 = 强度；水印 = 不透明度。
    var amount: Double = 0.5
    /// 水印文字（最多 `WatermarkShape.maxLength` 个字符）。
    var text: String = ""
}

/// 某个工具当前的样式。
struct ToolStyle: Equatable {
    var size: SizeLevel
    var colorIndex: Int
    var options = ToolOptions()

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
    /// 像素化的块大小（pt），随强度变化。
    var mosaicBlockSize: CGFloat { MosaicShape.blockSize(amount: options.amount) }
}

/// 每个工具的样式记在 UserDefaults 里，下次截图沿用。
struct StyleStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ tool: AnnotationTool, _ name: String) -> String { "style.\(tool.rawValue).\(name)" }
    private func sizeKey(_ tool: AnnotationTool) -> String { key(tool, "size") }
    private func colorKey(_ tool: AnnotationTool) -> String { key(tool, "color") }

    func style(for tool: AnnotationTool) -> ToolStyle {
        let size = (defaults.object(forKey: sizeKey(tool)) as? Int).flatMap(SizeLevel.init(rawValue:)) ?? .medium
        let color = (defaults.object(forKey: colorKey(tool)) as? Int) ?? Self.defaultColorIndex(for: tool)
        var options = ToolOptions()
        options.amount = (defaults.object(forKey: key(tool, "amount")) as? Double) ?? Self.defaultAmount(for: tool)
        let variant = defaults.integer(forKey: key(tool, "variant"))
        switch tool {
        case .spotlight:
            options.spotlightShape = SpotlightShapeKind(rawValue: variant) ?? .rectangle
        case .mosaic:
            options.mosaicEffect = MosaicEffect(rawValue: variant) ?? .pixelate
            options.mosaicMode = MosaicMode(rawValue: defaults.integer(forKey: key(tool, "mode"))) ?? .brush
        case .watermark:
            options.text = defaults.string(forKey: key(tool, "text")) ?? ""
        default:
            break
        }
        return ToolStyle(size: size, colorIndex: color, options: options)
    }

    /// 高亮 50%、马赛克 50%、水印 30%。
    static func defaultAmount(for tool: AnnotationTool) -> Double {
        tool == .watermark ? 0.3 : 0.5
    }

    /// 荧光笔默认黄色，水印默认黑色，其余默认红色。
    static func defaultColorIndex(for tool: AnnotationTool) -> Int {
        switch tool {
        case .highlighter: return 2 // 黄
        case .watermark: return 6 // 黑（30% 不透明度下是中性灰）
        default: return Palette.defaultIndex
        }
    }

    func setStyle(_ style: ToolStyle, for tool: AnnotationTool) {
        defaults.set(style.size.rawValue, forKey: sizeKey(tool))
        defaults.set(style.colorIndex, forKey: colorKey(tool))
        let options = style.options
        defaults.set(options.amount, forKey: key(tool, "amount"))
        switch tool {
        case .spotlight: defaults.set(options.spotlightShape.rawValue, forKey: key(tool, "variant"))
        case .mosaic:
            defaults.set(options.mosaicEffect.rawValue, forKey: key(tool, "variant"))
            defaults.set(options.mosaicMode.rawValue, forKey: key(tool, "mode"))
        case .watermark: defaults.set(options.text, forKey: key(tool, "text"))
        default: break
        }
    }
}
