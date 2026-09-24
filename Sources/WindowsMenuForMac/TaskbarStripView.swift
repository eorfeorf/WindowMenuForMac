import AppKit
import SwiftUI
import WindowMenuCore

private let pinnedDragType = NSPasteboard.PasteboardType("local.ef.WindowsMenuForMac.pinned-app")

final class TaskbarStripView: NSView {
    var onOpen: ((LauncherApp) -> Void)?
    var onDrawer: ((NSView) -> Void)?
    var onContext: ((LauncherApp, NSView) -> Void)?
    var onSettings: ((NSView) -> Void)?
    var onMove: ((String, String) -> Void)?
    var onInteraction: ((Bool) -> Void)?
    private var buttons: [TaskbarIconButton] = []
    private var dividerX: CGFloat?
    private var installedLayout: TaskbarLayout?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    convenience init() { self.init(frame: .zero) }

    func configure(apps: [LauncherApp], layout: TaskbarLayout) {
        let appButtons = buttons.filter { $0.app != nil }
        if installedLayout == layout && appButtons.compactMap({ $0.app?.path }) == apps.map(\.path) {
            zip(appButtons, apps).forEach { $0.0.update($0.1) }
            return
        }
        installedLayout = layout
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        dividerX = nil
        func install(_ button: TaskbarIconButton, x: CGFloat, width: CGFloat) {
            button.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            button.autoresizingMask = [.height]
            buttons.append(button)
            addSubview(button)
        }
        let drawer = TaskbarIconButton(symbol: "square.grid.2x2.fill", label: "Window Menu · すべてのアプリ")
        drawer.onClick = { [weak self, weak drawer] in if let drawer { self?.onDrawer?(drawer) } }
        drawer.onRightClick = { [weak self, weak drawer] in if let drawer { self?.onSettings?(drawer) } }
        install(drawer, x: 2, width: 28)
        var x: CGFloat = TaskbarLayout.controlWidth
        for (index, app) in apps.enumerated() {
            if index == layout.separatorIndex { dividerX = x + 4; x += TaskbarLayout.separatorWidth }
            let button = TaskbarIconButton(app: app)
            button.onClick = { [weak self, weak button] in if let app = button?.app { self?.onOpen?(app) } }
            button.onRightClick = { [weak self, weak button] in if let button, let app = button.app { self?.onContext?(app, button) } }
            button.onMove = { [weak self] source in self?.onMove?(source, app.path) }
            button.onInteraction = { [weak self] active in self?.onInteraction?(active) }
            install(button, x: x, width: TaskbarLayout.slotWidth)
            x += TaskbarLayout.slotWidth
        }
        if layout.hiddenCount > 0 && !apps.isEmpty {
            let more = TaskbarIconButton(symbol: "chevron.down", label: "残り\(layout.hiddenCount)個のアプリを表示")
            more.onClick = { [weak self, weak more] in if let more { self?.onDrawer?(more) } }
            install(more, x: x, width: TaskbarLayout.overflowWidth)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSRect(x: 1, y: max(1, (bounds.height - 24) / 2), width: max(0, bounds.width - 2), height: max(0, min(24, bounds.height - 2)))
        NSColor.labelColor.withAlphaComponent(0.055).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        if let x = dividerX {
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSRect(x: x, y: bounds.midY - 6, width: 1, height: 12).fill()
        }
    }
}

private final class TaskbarIconButton: NSButton, NSDraggingSource {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMove: ((String) -> Void)?
    var onInteraction: ((Bool) -> Void)?
    private(set) var app: LauncherApp?
    private var symbol: NSImage?
    private var hovered = false
    private var dropHighlighted = false
    private var dragging = false
    private var dragOrigin = NSPoint.zero
    private var tracking: NSTrackingArea?

    init(app: LauncherApp) {
        super.init(frame: .zero)
        setup(label: app.name)
        update(app)
    }
    init(symbol: String, label: String) {
        self.symbol = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        super.init(frame: .zero)
        setup(label: label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ app: LauncherApp) {
        self.app = app
        let label = "\(app.name)\(app.isActive ? " · 選択中" : app.running != nil ? " · 起動中" : "")"
        setAccessibilityLabel(label)
        setAccessibilityHelp(app.pinned ? "クリックで開く。ドラッグで固定アプリを並べ替え。右クリックでその他の操作。" : "クリックで開く。右クリックでその他の操作。")
        toolTip = label
        if app.pinned { registerForDraggedTypes([pinnedDragType]) } else { unregisterDraggedTypes() }
        needsDisplay = true
    }
    private func setup(label: String) {
        isBordered = false
        title = ""
        target = self
        action = #selector(chosen)
        setAccessibilityLabel(label)
        toolTip = label
    }
    @objc private func chosen() { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onRightClick?(); return }
        dragOrigin = convert(event.locationInWindow, from: nil)
        isHighlighted = true
        dragging = false
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let shouldOpen = isHighlighted && !dragging && bounds.contains(convert(event.locationInWindow, from: nil))
        isHighlighted = false
        needsDisplay = true
        if shouldOpen { performClick(nil) }
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let app, app.pinned else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) > 4 else { return }
        dragging = true
        isHighlighted = false
        onInteraction?(true)
        let data = NSPasteboardItem()
        data.setString(app.path, forType: pinnedDragType)
        let item = NSDraggingItem(pasteboardWriter: data)
        item.setDraggingFrame(NSRect(x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20), contents: app.icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        isHighlighted = false
        onInteraction?(false)
        needsDisplay = true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let source = sender.draggingPasteboard.string(forType: pinnedDragType), source != app?.path else { return [] }
        dropHighlighted = true
        needsDisplay = true
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropHighlighted = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlighted = false
        needsDisplay = true
        guard let source = sender.draggingPasteboard.string(forType: pinnedDragType), source != app?.path else { return false }
        onMove?(source)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let tile = NSRect(x: 2, y: max(1, (bounds.height - 23) / 2), width: bounds.width - 4, height: max(0, min(23, bounds.height - 2)))
        if hovered || isHighlighted || app?.isActive == true || dropHighlighted {
            let color = app?.isActive == true || dropHighlighted ? NSColor.controlAccentColor : NSColor.labelColor
            color.withAlphaComponent(isHighlighted ? 0.23 : hovered ? 0.15 : 0.1).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 5, yRadius: 5).fill()
        }
        let iconSize: CGFloat = app == nil ? 13 : 19
        let iconRect = NSRect(x: bounds.midX - iconSize / 2, y: bounds.midY - iconSize / 2 + (isFlipped ? -1 : 1), width: iconSize, height: iconSize)
        if let app { app.icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        else if let symbol {
            symbol.withSymbolConfiguration(.init(paletteColors: [.labelColor]))?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let app, app.running != nil {
            let width: CGFloat = app.isActive ? 13 : 4
            (app.isActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - width / 2, y: isFlipped ? tile.maxY - 2 : tile.minY, width: width, height: 2), xRadius: 1, yRadius: 1).fill()
        }
        if dropHighlighted {
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: tile.minY + 2, width: 2, height: tile.height - 4).fill()
        }
    }
}

struct TaskbarPreview: NSViewRepresentable {
    @ObservedObject var launcher: Launcher
    func makeNSView(context: Context) -> TaskbarStripView { TaskbarStripView() }
    func updateNSView(_ view: TaskbarStripView, context: Context) { launcher.configure(view) }
}
