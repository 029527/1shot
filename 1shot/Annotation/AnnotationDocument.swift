import CoreGraphics
import Foundation

/// 所有标注 + 撤销 / 重做（快照式，图形都是值类型）。
struct AnnotationDocument {
    private(set) var shapes: [any AnnotationShape] = []
    private var undoStack: [[any AnnotationShape]] = []
    private var redoStack: [[any AnnotationShape]] = []

    var isEmpty: Bool { shapes.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func add(_ shape: any AnnotationShape) {
        recordUndo()
        shapes.append(shape)
    }

    /// 替换已有图形（第二期「选中再修改」用）。
    mutating func replace(id: UUID, with shape: any AnnotationShape) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        shapes[index] = shape
    }

    mutating func remove(id: UUID) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        shapes.remove(at: index)
    }

    func shape(id: UUID) -> (any AnnotationShape)? {
        shapes.first { $0.id == id }
    }

    // MARK: 连续编辑（拖动、输入）合并成一步撤销

    /// 当前图形列表的快照；编辑结束后交给 `commitEdit(from:)`。
    var snapshot: [any AnnotationShape] { shapes }

    /// 编辑过程中更新图形，不记撤销。
    mutating func updateWithoutUndo(id: UUID, with shape: any AnnotationShape) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        shapes[index] = shape
    }

    mutating func removeWithoutUndo(id: UUID) {
        shapes.removeAll { $0.id == id }
    }

    mutating func appendWithoutUndo(_ shape: any AnnotationShape) {
        shapes.append(shape)
    }

    /// 编辑结束：把编辑前的快照记为一步撤销。
    mutating func commitEdit(from snapshot: [any AnnotationShape]) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    /// 最上层命中的图形。
    func shape(at point: CGPoint, tolerance: CGFloat = 4) -> (any AnnotationShape)? {
        shapes.last { $0.hitTest(point, tolerance: tolerance) }
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(shapes)
        shapes = previous
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(shapes)
        shapes = next
        return true
    }

    mutating func removeAll() {
        shapes = []
        undoStack = []
        redoStack = []
    }

    private mutating func recordUndo() {
        undoStack.append(shapes)
        redoStack.removeAll()
    }
}
