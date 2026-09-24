import Foundation
import CoreGraphics

public struct WindowGeometry: Equatable {
    public var id: UInt32
    public var pid: Int32
    public var bounds: CGRect
    public var title: String?

    public init(id: UInt32, pid: Int32, bounds: CGRect, title: String? = nil) {
        self.id = id
        self.pid = pid
        self.bounds = bounds
        self.title = title
    }
}

public enum WindowMatching {
    /// Without screen-recording permission, CG window titles may be absent.
    /// An ambiguous match is skipped instead of directing a command to the wrong window.
    public static func match(pid: Int32, bounds: CGRect, title: String?, candidates: [WindowGeometry]) -> WindowGeometry? {
        let matches = candidates.filter {
            $0.pid == pid && abs($0.bounds.minX - bounds.minX) < 3 &&
            abs($0.bounds.minY - bounds.minY) < 3 && abs($0.bounds.width - bounds.width) < 3 &&
            abs($0.bounds.height - bounds.height) < 3
        }
        if matches.count == 1 { return matches[0] }
        if let title, !title.isEmpty {
            let titled = matches.filter { $0.title == title }
            if titled.count == 1 { return titled[0] }
        }
        return nil
    }
}

public enum BarPlacement {
    public static let height: CGFloat = 28

    public static func cocoaRect(fromAccessibility rect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func frame(window: CGRect, visibleScreen: CGRect, preferredWidth: CGFloat, inside: Bool) -> CGRect? {
        guard window.width >= 140, window.height >= 80,
              window.intersects(visibleScreen), visibleScreen.width >= 140 else { return nil }
        let width = min(max(140, preferredWidth), window.width, visibleScreen.width)
        let x = max(visibleScreen.minX, min(window.minX, visibleScreen.maxX - width))
        let above = window.maxY + 2
        let y: CGFloat
        if !inside && above + height <= visibleScreen.maxY {
            y = above
        } else {
            // Keep the traffic-light buttons and window dragging area available.
            y = min(window.maxY - 32 - height, visibleScreen.maxY - height)
        }
        guard y >= visibleScreen.minY else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
