import CoreGraphics
import Foundation

/// 截图那一刻屏幕上的一个窗口。
struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    /// 窗口层级（`kCGWindowLayer`），普通窗口为 0。
    let layer: Int
    /// CG 全局坐标（主屏左上角为原点），单位 pt。
    let frame: CGRect
    let alpha: CGFloat
}

/// 截图那一刻的窗口列表，**从前到后**排序（与 `CGWindowListCopyWindowInfo` 的返回顺序一致）。
struct WindowListSnapshot: Equatable {
    let windows: [WindowInfo]

    init(windows: [WindowInfo]) {
        self.windows = windows
    }

    /// 读取当前屏幕上的窗口列表。`excludingPID` 的窗口里，`includingWindowIDs` 中的仍保留（如本 App 的设置窗口）。
    static func capture(excludingPID: pid_t, includingWindowIDs: Set<CGWindowID> = []) -> WindowListSnapshot {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return WindowListSnapshot(windows: [])
        }
        return WindowListSnapshot(rawList: raw, excludingPID: excludingPID, includingWindowIDs: includingWindowIDs)
    }

    /// 解析 `CGWindowListCopyWindowInfo` 的原始字典，过滤掉自己、透明和过小的窗口。
    init(rawList: [[String: Any]], excludingPID: pid_t, includingWindowIDs: Set<CGWindowID> = []) {
        var result: [WindowInfo] = []
        result.reserveCapacity(rawList.count)

        for entry in rawList {
            guard
                let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            if pid == excludingPID && !includingWindowIDs.contains(number) { continue }

            let alpha = CGFloat((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            if alpha <= 0.01 { continue }
            if bounds.width < 2 || bounds.height < 2 { continue }

            result.append(WindowInfo(
                windowID: number,
                ownerPID: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
                title: entry[kCGWindowName as String] as? String ?? "",
                layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                frame: bounds,
                alpha: alpha
            ))
        }
        windows = result
    }

    /// 悬停识别用的窗口 frame（AppKit 全局坐标），从前到后。
    ///
    /// 只保留层级在 [0, Dock 层级) 的窗口：普通窗口、浮动面板等；
    /// 排除 Dock、菜单栏、通知等系统层（它们常常是透明的整屏窗口）。
    func selectableFrames(converter: CoordinateConverter) -> [CGRect] {
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        return windows
            .filter { $0.layer >= 0 && $0.layer < dockLevel }
            .map { converter.appKitRect(fromCG: $0.frame) }
    }

    /// 包含该点（CG 全局坐标）的最前面的窗口。
    func topmostWindow(containingCG point: CGPoint) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
