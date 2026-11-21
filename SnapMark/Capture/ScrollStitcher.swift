import CoreGraphics
import Foundation

/// 长截图拼接（纯逻辑）：把同一区域在页面向下滚动过程中截下的多帧拼成一张长图。
///
/// 做法：每帧按行算哈希（跳过右侧滚动条区域），与「上一张被接受的帧」比较，
/// 找出内容向上移动了多少行（dy），把新帧底部多出来的 dy 行接到长图末尾。
/// 固定在顶部 / 底部的区域（吸顶导航、底栏）在相同位置逐行相等，会被识别出来：
/// 顶部只保留第一帧的，底部只保留最后一帧的。
final class ScrollStitcher {
    enum AddResult: Equatable {
        /// 新增了这么多行。
        case appended(Int)
        /// 没有滚动（或向上滚动后还没回到原位置）。
        case unchanged
        /// 找不到重叠部分（滚得太快）。
        case noMatch
        /// 已达到最大高度，后续帧不再拼接。
        case limitReached
        case sizeMismatch
    }

    struct Frame {
        let bytes: [UInt8]
        let hashes: [UInt64]
        let uniform: [Bool]
    }

    let width: Int
    let frameHeight: Int
    let maxHeight: Int

    /// 至少需要重叠的行数比例。
    static let minimumOverlapRatio = 0.12
    /// 判定为匹配所需的行相等比例。
    static let matchThreshold = 0.8

    private var body: [UInt8]
    private(set) var bodyRows: Int
    private var footer: [UInt8] = []
    private(set) var headerHeight = 0
    private(set) var footerHeight = 0
    private var fixedAreasKnown = false
    private var last: Frame
    private(set) var isFull = false

    var totalHeight: Int { bodyRows + footerHeight }

    init?(firstFrame: CGImage, maxHeight: Int = 20_000) {
        guard let frame = Self.frame(from: firstFrame) else { return nil }
        width = firstFrame.width
        frameHeight = firstFrame.height
        self.maxHeight = max(maxHeight, firstFrame.height)
        body = frame.bytes
        bodyRows = firstFrame.height
        last = frame
    }

    // MARK: 拼接

    func add(_ image: CGImage) -> AddResult {
        guard !isFull else { return .limitReached }
        guard image.width == width, image.height == frameHeight else { return .sizeMismatch }
        guard let next = Self.frame(from: image) else { return .sizeMismatch }

        let fixed = Self.fixedRows(previous: last, next: next)
        if fixed.top >= frameHeight { return .unchanged }

        let header = fixedAreasKnown ? headerHeight : fixed.top
        let footerRows = fixedAreasKnown ? footerHeight : fixed.bottom
        guard let dy = Self.offset(previous: last, next: next, header: header, footer: footerRows) else {
            return .noMatch
        }
        guard dy > 0 else { return .unchanged }

        let rowBytes = width * 4
        if !fixedAreasKnown {
            // 第一次成功匹配时确定吸顶 / 底栏高度；把长图末尾的底栏挪出来，最后再接上。
            fixedAreasKnown = true
            headerHeight = header
            footerHeight = footerRows
            if footerRows > 0 {
                bodyRows -= footerRows
                body.removeLast(footerRows * rowBytes)
            }
        }

        var rows = dy
        var result = AddResult.appended(dy)
        if bodyRows + rows + footerHeight > maxHeight {
            rows = max(0, maxHeight - footerHeight - bodyRows)
            isFull = true
            result = .limitReached
        }
        let end = frameHeight - footerHeight
        let start = end - dy
        if rows > 0 {
            body.append(contentsOf: next.bytes[(start * rowBytes)..<((start + rows) * rowBytes)])
            bodyRows += rows
        }
        footer = Array(next.bytes[(end * rowBytes)...])
        last = next
        return result
    }

    func makeImage() -> CGImage? {
        let rows = bodyRows + footerHeight
        guard rows > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let data = Data(body + footer) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: 分析

    /// 把图片转成 RGBA 字节，并按行计算哈希与「是否纯色」。
    static func frame(from image: CGImage) -> Frame? {
        let width = image.width, height = image.height
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: rowBytes, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // 跳过左侧 2% 和右侧 10%（滚动条在滚动时会出现、移动）。
        let startX = width / 50
        let endX = max(startX + 1, width - width / 10)
        var hashes = [UInt64](repeating: 0, count: height)
        var uniform = [Bool](repeating: true, count: height)
        bytes.withUnsafeBytes { raw in
            let pixels = raw.bindMemory(to: UInt32.self)
            for y in 0..<height {
                let row = y * width
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325
                let first = pixels[row + startX]
                var isUniform = true
                var x = startX
                while x < endX {
                    let value = pixels[row + x]
                    hash = (hash ^ UInt64(value)) &* 0x0000_0100_0000_01B3
                    if value != first { isUniform = false }
                    x += 1
                }
                hashes[y] = hash
                uniform[y] = isUniform
            }
        }
        return Frame(bytes: bytes, hashes: hashes, uniform: uniform)
    }

    /// 同一位置逐行相等的行数：顶部（吸顶区域）与底部（底栏）。
    static func fixedRows(previous: Frame, next: Frame) -> (top: Int, bottom: Int) {
        let height = next.hashes.count
        var top = 0
        while top < height, previous.hashes[top] == next.hashes[top] { top += 1 }
        if top == height { return (height, 0) }
        var bottom = 0
        while bottom < height - top, previous.hashes[height - 1 - bottom] == next.hashes[height - 1 - bottom] {
            bottom += 1
        }
        return (top, bottom)
    }

    /// 内容向上移动的行数（next 的第 i 行 = previous 的第 i + dy 行）。0 表示没动，nil 表示找不到。
    static func offset(previous: Frame, next: Frame, header: Int, footer: Int) -> Int? {
        let height = next.hashes.count
        let low = header
        let high = height - footer
        let region = high - low
        guard region >= 16 else { return nil }
        let minimumOverlap = max(8, Int(Double(region) * minimumOverlapRatio))
        guard region - minimumOverlap >= 0 else { return nil }

        var best: (dy: Int, score: Double)?
        var bestConsidered = 0
        previous.hashes.withUnsafeBufferPointer { prev in
            next.hashes.withUnsafeBufferPointer { cur in
                next.uniform.withUnsafeBufferPointer { flat in
                    for dy in 0...(region - minimumOverlap) {
                        var matched = 0
                        var considered = 0
                        var i = low
                        while i < high - dy {
                            if !flat[i] {
                                considered += 1
                                if prev[i + dy] == cur[i] { matched += 1 }
                            }
                            i += 1
                        }
                        guard considered >= 4 else { continue }
                        let score = Double(matched) / Double(considered)
                        if score > (best?.score ?? 0) {
                            best = (dy, score)
                            bestConsidered = considered
                            if score == 1 { break }
                        }
                    }
                }
            }
        }
        guard let best, best.score >= matchThreshold, bestConsidered >= 4 else { return nil }
        return best.dy
    }
}
