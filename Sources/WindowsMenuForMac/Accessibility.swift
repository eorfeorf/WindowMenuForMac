import AppKit
import ApplicationServices
import WindowMenuCore

enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    static func element(_ source: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(source, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ source: AXUIElement, _ attribute: String, limit: Int = 200) -> [AXUIElement] {
        var count = 0
        guard AXUIElementGetAttributeValueCount(source, attribute as CFString, &count) == .success, count > 0 else { return [] }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(source, attribute as CFString, 0, min(count, limit), &values) == .success else { return [] }
        return (values as? [AXUIElement]) ?? []
    }

    static func string(_ source: AXUIElement, _ attribute: String) -> String? { value(source, attribute) as? String }
    static func bool(_ source: AXUIElement, _ attribute: String) -> Bool? { value(source, attribute) as? Bool }

    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = value(window, kAXPositionAttribute), let size = value(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func menuChildren(_ item: AXUIElement) -> [AXUIElement] {
        let children = elements(item, kAXChildrenAttribute)
        if let menu = children.first(where: { string($0, kAXRoleAttribute) == kAXMenuRole }) {
            return elements(menu, kAXChildrenAttribute)
        }
        return children.filter { string($0, kAXRoleAttribute) == kAXMenuItemRole }
    }
}

struct MenuHeading {
    let title: String
    let element: AXUIElement
}

struct WindowTarget {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let element: AXUIElement
    let frame: CGRect
    let headings: [MenuHeading]
}

final class WindowScanner {
    var onUpdate: (([WindowTarget]) -> Void)?
    var enabled = true
    var suspended = false
    private let queue = DispatchQueue(label: "WindowsMenuForMac.accessibility", qos: .userInitiated)
    private var timer: Timer?
    private var busy = false
    private var generation = 0
    private var cachedMenus: [pid_t: (Date, [MenuHeading])] = [:]

    func start() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.12)
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.08
        refresh()
    }

    func invalidate() {
        generation += 1
        onUpdate?([])
    }

    func refresh() {
        guard !suspended else { return }
        guard enabled, AXIsProcessTrusted() else { invalidate(); return }
        guard !busy else { return }
        busy = true
        let revision = generation
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isHidden
        }.map { ($0.processIdentifier, $0.localizedName ?? "アプリ") }
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        queue.async { [weak self] in
            guard let self else { return }
            let targets = self.scan(apps: apps, screenTop: screenTop)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                if self.generation == revision, self.enabled, !self.suspended { self.onUpdate?(targets) }
            }
        }
    }

    private func scan(apps: [(pid_t, String)], screenTop: CGFloat) -> [WindowTarget] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let visible: [WindowGeometry] = info.compactMap { row in
            guard (row[kCGWindowLayer as String] as? Int) == 0,
                  (row[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = row[kCGWindowNumber as String] as? UInt32,
                  let pid = row[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 140, rect.height >= 80 else { return nil }
            return WindowGeometry(id: id, pid: pid, bounds: rect, title: row[kCGWindowName as String] as? String)
        }
        let pids = Set(visible.map(\.pid))
        cachedMenus = cachedMenus.filter { pids.contains($0.key) }
        var targets: [WindowTarget] = []
        var matched = Set<CGWindowID>()
        for (pid, name) in apps where pids.contains(pid) {
            let application = AXUIElementCreateApplication(pid)
            let windows = AX.elements(application, kAXWindowsAttribute, limit: 80)
            let headings: [MenuHeading]
            if let (date, cached) = cachedMenus[pid], Date().timeIntervalSince(date) < 3 {
                headings = cached
            } else {
                headings = Self.headings(application)
                cachedMenus[pid] = (Date(), headings)
            }
            guard !headings.isEmpty else { continue }
            for window in windows {
                guard AX.bool(window, kAXMinimizedAttribute) != true,
                      AX.bool(window, "AXFullScreen") != true,
                      let rect = AX.frame(window),
                      let match = WindowMatching.match(pid: pid, bounds: rect, title: AX.string(window, kAXTitleAttribute), candidates: visible),
                      !matched.contains(match.id) else { continue }
                matched.insert(match.id)
                targets.append(WindowTarget(id: match.id, pid: pid, appName: name, element: window,
                                            frame: BarPlacement.cocoaRect(fromAccessibility: rect, primaryScreenTop: screenTop),
                                            headings: headings))
            }
        }
        // Rear-to-front ordering keeps each overlay at its owner's stacking position.
        let order = Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($0.element.id, $0.offset) })
        return targets.sorted { (order[$0.id] ?? 0) > (order[$1.id] ?? 0) }
    }

    static func headings(_ application: AXUIElement) -> [MenuHeading] {
        guard let menuBar = AX.element(application, kAXMenuBarAttribute) else { return [] }
        return AX.elements(menuBar, kAXChildrenAttribute, limit: 40).compactMap {
            guard let title = AX.string($0, kAXTitleAttribute), !title.isEmpty,
                  title != "Apple", title != "アップル", title != "" else { return nil }
            return MenuHeading(title: title, element: $0)
        }
    }
}
