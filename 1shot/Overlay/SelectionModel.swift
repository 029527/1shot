import CoreGraphics

/// 选区的 8 个控制点。
enum SelectionHandle: CaseIterable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// 该控制点在矩形上的位置（AppKit 坐标，y 向上）。
    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var movesMaxY: Bool { self == .topLeft || self == .top || self == .topRight }
}

/// 选区状态机（纯逻辑，可单元测试）。
///
/// 所有坐标都是 AppKit 全局坐标（pt）。选区只能在单块屏幕内。
///
/// 状态：idle → hovering → dragging → selected → annotating → finished / cancelled
struct SelectionModel {
    enum State: Equatable {
        case idle, hovering, dragging, selected, annotating, finished, cancelled
    }

    enum CursorKind: Equatable {
        case crosshair
        case openHand
        case closedHand
        case resize(SelectionHandle)
    }

    enum RightClickOutcome: Equatable {
        /// 取消选区，回到悬停识别。
        case resetToHovering
        /// 退出截图。
        case cancel
        /// 不处理（已有标注时）。
        case ignored
    }

    /// 拖动距离小于这个值视为单击。
    static let dragThreshold: CGFloat = 4
    /// 控制点的命中半径。
    static let handleHitRadius: CGFloat = 8

    let screens: [ScreenGeometry]
    /// 可识别的窗口 frame（AppKit 全局坐标），从前到后。
    let windowFrames: [CGRect]

    private(set) var state: State = .idle
    /// 悬停时高亮的区域（窗口或整块屏幕）。
    private(set) var hoverRect: CGRect?
    private(set) var hoverScreenIndex: Int?
    private(set) var selection: CGRect?
    private(set) var selectionScreenIndex: Int?
    /// 有标注后选区锁定，不能再移动或改大小。
    private(set) var isLocked = false

    private enum Interaction: Equatable {
        case none
        /// 已按下，还没超过拖动阈值。
        case pressing(start: CGPoint, screen: Int)
        case creating(anchor: CGPoint, screen: Int)
        case moving(start: CGPoint, original: CGRect)
        case resizing(handle: SelectionHandle, start: CGPoint, original: CGRect)
    }

    private var interaction: Interaction = .none

    init(screens: [ScreenGeometry], windowFrames: [CGRect]) {
        self.screens = screens
        self.windowFrames = windowFrames
    }

    // MARK: 查询

    /// 正在移动或调整选区大小。
    var isAdjusting: Bool {
        switch interaction {
        case .moving, .resizing: return true
        default: return false
        }
    }

    /// 正在拖动选区（移动）。
    var isMoving: Bool {
        if case .moving = interaction { return true }
        return false
    }

    /// 当前要「挖亮」的区域：悬停时是悬停区域，否则是选区。
    var highlightedRect: CGRect? {
        state == .hovering ? hoverRect : selection
    }

    /// 选区所在屏幕的物理像素尺寸。
    var selectionPixelSize: CGSize? {
        guard let selection, let index = selectionScreenIndex else { return nil }
        let geometry = screens[index]
        return geometry.integralPixelRect(fromLocal: geometry.localRect(fromGlobal: selection)).size
    }

    /// 光标下的控制点（仅在可调整时）。
    func handle(at point: CGPoint) -> SelectionHandle? {
        guard state == .selected, !isLocked, let selection else { return nil }
        let radius = Self.handleHitRadius
        var best: (SelectionHandle, CGFloat)?
        for handle in SelectionHandle.allCases {
            let p = handle.point(in: selection)
            let distance = hypot(p.x - point.x, p.y - point.y)
            if distance <= radius, distance < (best?.1 ?? .greatestFiniteMagnitude) {
                best = (handle, distance)
            }
        }
        return best?.0
    }

    func cursorKind(at point: CGPoint) -> CursorKind {
        switch interaction {
        case .moving: return .closedHand
        case .resizing(let handle, _, _): return .resize(handle)
        case .creating: return .crosshair
        default: break
        }
        if let handle = handle(at: point) { return .resize(handle) }
        if state == .selected, !isLocked, let selection, selection.contains(point) { return .openHand }
        return .crosshair
    }

    // MARK: 事件

    /// 开始截图：进入悬停识别。
    mutating func begin(at mouse: CGPoint) {
        state = .hovering
        interaction = .none
        selection = nil
        selectionScreenIndex = nil
        updateHover(at: mouse)
    }

    mutating func mouseMoved(to point: CGPoint) {
        if state == .hovering, interaction == .none {
            updateHover(at: point)
        }
    }

    mutating func mouseDown(at point: CGPoint) {
        switch state {
        case .hovering:
            guard let screen = screenIndex(containing: point) else { return }
            interaction = .pressing(start: point, screen: screen)
        case .selected:
            guard !isLocked, let selection else { return }
            if let handle = handle(at: point) {
                interaction = .resizing(handle: handle, start: point, original: selection)
            } else if selection.contains(point) {
                interaction = .moving(start: point, original: selection)
            } else if let screen = screenIndex(containing: point) {
                // 在选区外按下并拖动：重新框选。
                interaction = .pressing(start: point, screen: screen)
            }
        default:
            break
        }
    }

    mutating func mouseDragged(to point: CGPoint) {
        switch interaction {
        case .none:
            break

        case .pressing(let start, let screen):
            guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return }
            interaction = .creating(anchor: start, screen: screen)
            state = .dragging
            hoverRect = nil
            hoverScreenIndex = nil
            selectionScreenIndex = screen
            selection = Self.rect(from: start, to: clamp(point, toScreen: screen))

        case .creating(let anchor, let screen):
            selection = Self.rect(from: anchor, to: clamp(point, toScreen: screen))

        case .moving(let start, let original):
            guard let index = selectionScreenIndex else { return }
            let moved = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            selection = Self.keep(moved, inside: screens[index].frame)

        case .resizing(let handle, let start, let original):
            guard let index = selectionScreenIndex else { return }
            selection = Self.resize(original, handle: handle, dx: point.x - start.x, dy: point.y - start.y,
                                    within: screens[index].frame)
        }
    }

    mutating func mouseUp(at point: CGPoint) {
        defer { interaction = .none }

        switch interaction {
        case .pressing:
            // 单击：悬停时把高亮区域作为选区；已有选区时在外面单击不做事。
            if state == .hovering, let hoverRect {
                selection = hoverRect
                selectionScreenIndex = hoverScreenIndex
                self.hoverRect = nil
                hoverScreenIndex = nil
                state = .selected
            }

        case .creating:
            if let selection, selection.width >= 1, selection.height >= 1 {
                state = .selected
            } else {
                // 拖出一条线：当作没选，回到悬停。
                begin(at: point)
            }

        case .moving, .resizing, .none:
            break
        }
    }

    /// 右键：有选区但没有标注时取消选区；没有选区时退出截图。
    mutating func rightClick(at point: CGPoint) -> RightClickOutcome {
        switch state {
        case .selected, .dragging:
            guard !isLocked else { return .ignored }
            begin(at: point)
            return .resetToHovering
        case .annotating:
            return .ignored
        default:
            state = .cancelled
            interaction = .none
            return .cancel
        }
    }

    /// 方向键微调。返回是否移动了。
    @discardableResult
    mutating func nudge(dx: CGFloat, dy: CGFloat) -> Bool {
        guard state == .selected, !isLocked, interaction == .none,
              let selection, let index = selectionScreenIndex else { return false }
        let moved = Self.keep(selection.offsetBy(dx: dx, dy: dy), inside: screens[index].frame)
        guard moved != selection else { return false }
        self.selection = moved
        return true
    }

    /// 出现第一个标注后调用：锁定选区（M3）。
    mutating func lock() {
        guard state == .selected else { return }
        isLocked = true
        state = .annotating
        interaction = .none
    }

    /// 撤销到没有标注时解锁。
    mutating func unlock() {
        guard isLocked else { return }
        isLocked = false
        if state == .annotating { state = .selected }
    }

    mutating func finish() {
        state = .finished
        interaction = .none
    }

    mutating func cancel() {
        state = .cancelled
        interaction = .none
    }

    // MARK: 内部

    private mutating func updateHover(at point: CGPoint) {
        guard let index = screenIndex(containing: point) else {
            hoverRect = nil
            hoverScreenIndex = nil
            return
        }
        let screenFrame = screens[index].frame
        hoverScreenIndex = index
        hoverRect = screenFrame
        if let window = windowFrames.first(where: { $0.contains(point) }) {
            let clipped = window.intersection(screenFrame)
            if !clipped.isNull, clipped.width >= 1, clipped.height >= 1 {
                hoverRect = clipped
            }
        }
    }

    /// 包含该点的屏幕；都不包含时取最近的一块（光标在屏幕边缘时可能出现）。
    func screenIndex(containing point: CGPoint) -> Int? {
        guard !screens.isEmpty else { return nil }
        if let index = screens.firstIndex(where: { $0.frame.contains(point) }) {
            return index
        }
        return screens.indices.min { a, b in
            Self.distance(from: point, to: screens[a].frame) < Self.distance(from: point, to: screens[b].frame)
        }
    }

    private func clamp(_ point: CGPoint, toScreen index: Int) -> CGPoint {
        let frame = screens[index].frame
        return CGPoint(x: min(max(point.x, frame.minX), frame.maxX),
                       y: min(max(point.y, frame.minY), frame.maxY))
    }

    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// 平移矩形使其完全落在 bounds 内（尺寸不变）。
    static func keep(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        var r = rect
        if r.width > bounds.width { r.size.width = bounds.width }
        if r.height > bounds.height { r.size.height = bounds.height }
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }

    /// 拖动控制点改大小：被拖的边跟着走，对边固定；越过对边时翻转；不超出屏幕。
    static func resize(_ rect: CGRect, handle: SelectionHandle, dx: CGFloat, dy: CGFloat,
                       within bounds: CGRect) -> CGRect {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, bounds.minX), bounds.maxX) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, bounds.minY), bounds.maxY) }

        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX { minX = clampX(minX + dx) }
        if handle.movesMaxX { maxX = clampX(maxX + dx) }
        if handle.movesMinY { minY = clampY(minY + dy) }
        if handle.movesMaxY { maxY = clampY(maxY + dy) }

        var result = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        // 至少 1pt，避免选区消失。
        if result.width < 1 { result.size.width = 1 }
        if result.height < 1 { result.size.height = 1 }
        return keep(result, inside: bounds)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
