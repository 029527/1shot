import XCTest
@testable import SnapMark

final class SelectionModelTests: XCTestCase {
    /// 主屏 1000×800（scale 2），右侧外接屏 1920×1080（scale 1）。
    let primary = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: 2)
    let external = ScreenGeometry(frame: CGRect(x: 1000, y: 0, width: 1920, height: 1080), scale: 1)
    /// 前面的小窗口压在后面的大窗口上。
    let front = CGRect(x: 100, y: 100, width: 200, height: 150)
    let back = CGRect(x: 50, y: 50, width: 600, height: 500)

    private func makeModel(windows: [CGRect]? = nil) -> SelectionModel {
        var model = SelectionModel(screens: [primary, external], windowFrames: windows ?? [front, back])
        model.begin(at: CGPoint(x: 900, y: 700))
        return model
    }

    private func drag(_ model: inout SelectionModel, from a: CGPoint, to b: CGPoint) {
        model.mouseDown(at: a)
        model.mouseDragged(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        model.mouseDragged(to: b)
        model.mouseUp(at: b)
    }

    // MARK: 悬停

    func testHoverOnDesktopHighlightsWholeScreen() {
        let model = makeModel()
        XCTAssertEqual(model.state, .hovering)
        XCTAssertEqual(model.hoverRect, primary.frame)
        XCTAssertEqual(model.hoverScreenIndex, 0)
    }

    func testHoverPicksFrontmostWindow() {
        var model = makeModel()
        model.mouseMoved(to: CGPoint(x: 150, y: 150))
        XCTAssertEqual(model.hoverRect, front)
        model.mouseMoved(to: CGPoint(x: 500, y: 400))
        XCTAssertEqual(model.hoverRect, back)
    }

    func testHoverClipsWindowToScreen() {
        // 窗口跨在两块屏幕上：只高亮光标所在屏幕的部分。
        let spanning = CGRect(x: 800, y: 100, width: 400, height: 300)
        var model = makeModel(windows: [spanning])
        model.mouseMoved(to: CGPoint(x: 1100, y: 200))
        XCTAssertEqual(model.hoverRect, CGRect(x: 1000, y: 100, width: 200, height: 300))
        XCTAssertEqual(model.hoverScreenIndex, 1)
    }

    // MARK: 单击 / 框选

    func testClickSelectsHoveredWindow() {
        var model = makeModel()
        model.mouseMoved(to: CGPoint(x: 150, y: 150))
        model.mouseDown(at: CGPoint(x: 150, y: 150))
        model.mouseDragged(to: CGPoint(x: 152, y: 152)) // < 4pt，仍算单击
        model.mouseUp(at: CGPoint(x: 152, y: 152))
        XCTAssertEqual(model.state, .selected)
        XCTAssertEqual(model.selection, front)
        XCTAssertNil(model.hoverRect)
    }

    func testDragCreatesSelection() {
        var model = makeModel()
        drag(&model, from: CGPoint(x: 400, y: 600), to: CGPoint(x: 100, y: 300))
        XCTAssertEqual(model.state, .selected)
        XCTAssertEqual(model.selection, CGRect(x: 100, y: 300, width: 300, height: 300))
        XCTAssertEqual(model.selectionPixelSize, CGSize(width: 600, height: 600))
    }

    func testDragStateWhileDragging() {
        var model = makeModel()
        model.mouseDown(at: CGPoint(x: 10, y: 10))
        model.mouseDragged(to: CGPoint(x: 20, y: 20))
        XCTAssertEqual(model.state, .dragging)
        XCTAssertNil(model.hoverRect)
    }

    func testDragIsClampedToStartingScreen() {
        var model = makeModel()
        drag(&model, from: CGPoint(x: 900, y: 100), to: CGPoint(x: 1500, y: 900))
        XCTAssertEqual(model.selection, CGRect(x: 900, y: 100, width: 100, height: 700))
        XCTAssertEqual(model.selectionScreenIndex, 0)
    }

    func testPixelSizeUsesSelectionScreenScale() {
        var model = makeModel()
        drag(&model, from: CGPoint(x: 1100, y: 100), to: CGPoint(x: 1200, y: 150))
        XCTAssertEqual(model.selectionPixelSize, CGSize(width: 100, height: 50))
    }

    func testZeroHeightDragFallsBackToHovering() {
        var model = makeModel()
        drag(&model, from: CGPoint(x: 700, y: 700), to: CGPoint(x: 800, y: 700))
        XCTAssertEqual(model.state, .hovering)
        XCTAssertNil(model.selection)
    }

    // MARK: 调整

    private func selectedModel() -> SelectionModel {
        var model = makeModel()
        drag(&model, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        XCTAssertEqual(model.selection, CGRect(x: 100, y: 100, width: 200, height: 100))
        return model
    }

    func testHandleHitTest() {
        let model = selectedModel()
        XCTAssertEqual(model.handle(at: CGPoint(x: 102, y: 198)), .topLeft)
        XCTAssertEqual(model.handle(at: CGPoint(x: 200, y: 100)), .bottom)
        XCTAssertEqual(model.handle(at: CGPoint(x: 305, y: 150)), .right)
        XCTAssertNil(model.handle(at: CGPoint(x: 200, y: 150)))
        XCTAssertEqual(model.cursorKind(at: CGPoint(x: 200, y: 150)), .openHand)
        XCTAssertEqual(model.cursorKind(at: CGPoint(x: 500, y: 500)), .crosshair)
    }

    func testResizeFromCorner() {
        var model = selectedModel()
        drag(&model, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 350, y: 260))
        XCTAssertEqual(model.selection, CGRect(x: 100, y: 100, width: 250, height: 160))
        XCTAssertEqual(model.state, .selected)
    }

    func testResizeEdgeOnlyChangesOneDimension() {
        var model = selectedModel()
        drag(&model, from: CGPoint(x: 100, y: 150), to: CGPoint(x: 60, y: 400))
        XCTAssertEqual(model.selection, CGRect(x: 60, y: 100, width: 240, height: 100))
    }

    func testResizePastOppositeEdgeFlips() {
        var model = selectedModel()
        drag(&model, from: CGPoint(x: 300, y: 150), to: CGPoint(x: 50, y: 150))
        XCTAssertEqual(model.selection, CGRect(x: 50, y: 100, width: 50, height: 100))
    }

    func testResizeIsClampedToScreen() {
        var model = selectedModel()
        drag(&model, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 1300, y: 2000))
        XCTAssertEqual(model.selection, CGRect(x: 100, y: 100, width: 900, height: 700))
    }

    func testMoveSelection() {
        var model = selectedModel()
        drag(&model, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 250, y: 130))
        XCTAssertEqual(model.selection, CGRect(x: 150, y: 80, width: 200, height: 100))
    }

    func testMoveIsClampedToScreen() {
        var model = selectedModel()
        drag(&model, from: CGPoint(x: 200, y: 150), to: CGPoint(x: -500, y: 2000))
        XCTAssertEqual(model.selection, CGRect(x: 0, y: 700, width: 200, height: 100))
    }

    func testIsAdjustingDuringMove() {
        var model = selectedModel()
        model.mouseDown(at: CGPoint(x: 200, y: 150))
        XCTAssertTrue(model.isAdjusting)
        model.mouseDragged(to: CGPoint(x: 210, y: 150))
        XCTAssertEqual(model.cursorKind(at: CGPoint(x: 210, y: 150)), .closedHand)
        model.mouseUp(at: CGPoint(x: 210, y: 150))
        XCTAssertFalse(model.isAdjusting)
    }

    func testDragOutsideSelectionStartsNewSelection() {
        var model = selectedModel()
        drag(&model, from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 650))
        XCTAssertEqual(model.selection, CGRect(x: 500, y: 500, width: 100, height: 150))
    }

    func testClickOutsideSelectionKeepsIt() {
        var model = selectedModel()
        model.mouseDown(at: CGPoint(x: 500, y: 500))
        model.mouseUp(at: CGPoint(x: 500, y: 500))
        XCTAssertEqual(model.selection, CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertEqual(model.state, .selected)
    }

    func testNudge() {
        var model = selectedModel()
        XCTAssertTrue(model.nudge(dx: 1, dy: 0))
        XCTAssertTrue(model.nudge(dx: 0, dy: -10))
        XCTAssertEqual(model.selection, CGRect(x: 101, y: 90, width: 200, height: 100))
        // 不能超出屏幕
        model.nudge(dx: -5000, dy: 0)
        XCTAssertEqual(model.selection?.minX, 0)
        XCTAssertFalse(model.nudge(dx: -1, dy: 0))
    }

    func testNudgeIgnoredWhileHovering() {
        var model = makeModel()
        XCTAssertFalse(model.nudge(dx: 1, dy: 0))
    }

    // MARK: 右键 / 锁定

    func testRightClickWithSelectionResetsToHovering() {
        var model = selectedModel()
        XCTAssertEqual(model.rightClick(at: CGPoint(x: 150, y: 150)), .resetToHovering)
        XCTAssertEqual(model.state, .hovering)
        XCTAssertNil(model.selection)
        XCTAssertEqual(model.hoverRect, front)
    }

    func testRightClickWithoutSelectionCancels() {
        var model = makeModel()
        XCTAssertEqual(model.rightClick(at: .zero), .cancel)
        XCTAssertEqual(model.state, .cancelled)
    }

    func testLockedSelectionCannotChange() {
        var model = selectedModel()
        model.lock()
        XCTAssertEqual(model.state, .annotating)
        XCTAssertFalse(model.nudge(dx: 1, dy: 0))
        drag(&model, from: CGPoint(x: 200, y: 150), to: CGPoint(x: 260, y: 150))
        XCTAssertEqual(model.selection, CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertNil(model.handle(at: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(model.rightClick(at: .zero), .ignored)
    }

    func testFinishAndCancel() {
        var model = selectedModel()
        model.finish()
        XCTAssertEqual(model.state, .finished)
        var other = selectedModel()
        other.cancel()
        XCTAssertEqual(other.state, .cancelled)
    }

    // MARK: 屏幕查找

    func testScreenIndexFallsBackToNearest() {
        let model = makeModel()
        XCTAssertEqual(model.screenIndex(containing: CGPoint(x: 500, y: 800)), 0) // 主屏上边缘
        XCTAssertEqual(model.screenIndex(containing: CGPoint(x: 3000, y: 500)), 1)
    }
}
