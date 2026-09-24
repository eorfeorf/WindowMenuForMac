import Foundation

public struct TaskbarLayout: Equatable {
    public let visibleCount: Int
    public let hiddenCount: Int
    public let width: Double
    public let separatorIndex: Int?
    public static let controlWidth = 30.0
    public static let slotWidth = 30.0
    public static let overflowWidth = 26.0
    public static let padding = 4.0
    public static let separatorWidth = 8.0

    /// Keep a single, contiguous status item within its budget; overflow is always reachable.
    public init(appCount: Int, pinnedCount: Int, iconLimit: Int, availableWidth: Double) {
        let total = max(0, appCount)
        let pinned = min(total, max(0, pinnedCount))
        let limit = iconLimit <= 0 ? total : min(total, iconLimit)
        let budget = max(Self.controlWidth + Self.padding, availableWidth)
        func size(_ count: Int) -> Double {
            Self.controlWidth + Self.padding + Double(count) * Self.slotWidth +
            (count > pinned && pinned > 0 ? Self.separatorWidth : 0) +
            (count > 0 && count < total ? Self.overflowWidth : 0)
        }
        var count = limit
        while count > 0 && size(count) > budget { count -= 1 }
        visibleCount = count
        hiddenCount = total - count
        width = size(count)
        separatorIndex = count > pinned && pinned > 0 ? pinned : nil
    }
}

public enum PinnedOrder {
    public static func moving(_ path: String, before target: String, in paths: [String]) -> [String] {
        guard path != target, paths.contains(path), paths.contains(target) else { return paths }
        var result = paths.filter { $0 != path }
        guard let index = result.firstIndex(of: target) else { return paths }
        result.insert(path, at: index)
        return result
    }

    public static func moving(_ path: String, offset: Int, in paths: [String]) -> [String] {
        guard let source = paths.firstIndex(of: path), !paths.isEmpty else { return paths }
        let destination = min(paths.count - 1, max(0, source + offset))
        var result = paths
        result.remove(at: source)
        result.insert(path, at: destination)
        return result
    }
}
