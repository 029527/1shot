import Foundation
import OSLog
import QuartzCore

/// 统一的日志入口。查看方式：
/// `/usr/bin/log stream --predicate 'subsystem == "com.1shot.app"'`
enum Log {
    static let subsystem = "com.1shot.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
}

/// 简单的毫秒计时工具。
struct Stopwatch {
    let start: CFTimeInterval

    init(start: CFTimeInterval = CACurrentMediaTime()) {
        self.start = start
    }

    /// 从 `start` 到现在经过的毫秒数。
    var elapsedMs: Double {
        (CACurrentMediaTime() - start) * 1000
    }
}

