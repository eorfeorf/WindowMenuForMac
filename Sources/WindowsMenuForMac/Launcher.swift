import AppKit
import SwiftUI
import WindowMenuCore

struct LauncherApp: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let running: NSRunningApplication?
    let pinned: Bool
    let isActive: Bool
    let icon: NSImage
}

final class Launcher: NSObject, ObservableObject {
    let model: AppModel
    @Published private(set) var apps: [LauncherApp] = []
    @Published private(set) var layout = TaskbarLayout(appCount: 0, pinnedCount: 0, iconLimit: 0, availableWidth: 400)
    private let status = NSStatusBar.system.statusItem(withLength: 34)
    private let strip = TaskbarStripView()
    private let popover = NSPopover()
    private var iconCache: [String: NSImage] = [:]
    private var runningOrder: [String] = []
    private var lastActiveID: String?
    private var interactionDepth = 0
    private var refreshPending = false
    private var widthOverride: CGFloat?

    init(model: AppModel) {
        self.model = model
        super.init()
        status.autosaveName = "WindowsMenuForMac.Taskbar"
        if let button = status.button {
            button.title = ""
            button.image = nil
            button.action = nil
            button.setAccessibilityElement(false)
            strip.frame = button.bounds
            strip.autoresizingMask = [.width, .height]
            button.addSubview(strip)
        }
        popover.behavior = .transient
        popover.animates = true
        refresh()
    }

    private func identity(_ path: String) -> String {
        Bundle(path: path)?.bundleIdentifier ?? URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    func refresh() {
        if interactionDepth > 0 { refreshPending = true; return }
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        if let active = NSWorkspace.shared.frontmostApplication,
           active.activationPolicy == .regular, let path = active.bundleURL?.path {
            lastActiveID = identity(path)
        }
        var runningByID: [String: NSRunningApplication] = [:]
        for app in running {
            if let path = app.bundleURL?.path { runningByID[identity(path)] = app }
        }
        // Keep running applications in stable positions when focus changes.
        runningOrder = runningOrder.filter { runningByID[$0] != nil }
        for app in running.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
            if let path = app.bundleURL?.path {
                let key = identity(path)
                if !runningOrder.contains(key) { runningOrder.append(key) }
            }
        }
        var seen = Set<String>()
        var entries: [LauncherApp] = []
        func append(_ path: String, pinned: Bool) {
            let key = identity(path)
            guard !seen.contains(key), FileManager.default.fileExists(atPath: path) else { return }
            seen.insert(key)
            let app = runningByID[key]
            let icon = iconCache[path] ?? NSWorkspace.shared.icon(forFile: path)
            iconCache[path] = icon
            entries.append(LauncherApp(path: path,
                name: app?.localizedName ?? FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""),
                running: app, pinned: pinned, isActive: app != nil && key == lastActiveID, icon: icon))
        }
        model.pinnedPaths.forEach { append($0, pinned: true) }
        for key in runningOrder {
            if let path = runningByID[key]?.bundleURL?.path { append(path, pinned: false) }
        }
        iconCache = iconCache.filter { key, _ in entries.contains { $0.path == key } }
        apps = entries
        updateLayout()
    }

    func screenChanged() {
        widthOverride = nil
        refresh()
    }

    private var availableWidth: CGFloat {
        guard let screen = status.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return 274 }
        // Leave space for the clock, Control Center, and other menu extras.
        let safeWidth = screen.auxiliaryTopRightArea?.width ?? screen.frame.width * 0.48
        return max(94, min(514, safeWidth - 230))
    }

    private func updateLayout() {
        let newLayout = TaskbarLayout(appCount: model.launcherEnabled ? apps.count : 0,
            pinnedCount: apps.filter(\.pinned).count, iconLimit: model.iconLimit,
            availableWidth: Double(min(availableWidth, widthOverride ?? .greatestFiniteMagnitude)))
        layout = newLayout
        status.length = newLayout.width
        configure(strip)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.checkPlacement() }
    }

    private func checkPlacement() {
        guard interactionDepth == 0, let window = status.button?.window,
              let screen = window.screen ?? NSScreen.main, layout.visibleCount > 0 else { return }
        let leading = screen.auxiliaryTopRightArea?.minX ?? screen.frame.minX
        let rect = window.frame
        if rect.minX < leading || rect.maxX > screen.frame.maxX + 1 || rect.width < 1 {
            widthOverride = max(34, CGFloat(layout.width) - 30)
            updateLayout()
        }
    }

    func configure(_ view: TaskbarStripView) {
        view.configure(apps: model.launcherEnabled ? Array(apps.prefix(layout.visibleCount)) : [], layout: layout)
        view.onOpen = { [weak self] app in self?.open(app) }
        view.onDrawer = { [weak self] anchor in self?.showDrawer(from: anchor) }
        view.onContext = { [weak self] app, anchor in self?.showContext(app, from: anchor) }
        view.onSettings = { [weak self] anchor in self?.showSettingsMenu(from: anchor) }
        view.onMove = { [weak self] source, target in self?.model.movePin(source, before: target) }
        view.onInteraction = { [weak self] active in self?.interacting(active) }
    }

    private func interacting(_ active: Bool) {
        interactionDepth = max(0, interactionDepth + (active ? 1 : -1))
        if interactionDepth == 0 && refreshPending {
            refreshPending = false
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    func showDrawer(from anchor: NSView? = nil) {
        if popover.isShown { popover.performClose(nil); return }
        guard let anchor = anchor ?? status.button, anchor.window?.isVisible == true else {
            model.onShowSettings?()
            return
        }
        // Do not rebuild the clicked button while it anchors the popover.
        popover.contentViewController = NSHostingController(rootView: LauncherDrawer(launcher: self, model: model))
        popover.contentSize = NSSize(width: 416, height: 470)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func open(_ app: LauncherApp) {
        popover.performClose(nil)
        if let running = app.running, !running.isTerminated {
            running.unhide()
            running.activate(options: [.activateIgnoringOtherApps])
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { [weak self] _, error in
                if let error {
                    DispatchQueue.main.async {
                        self?.model.error = error.localizedDescription
                        self?.model.onShowSettings?()
                    }
                }
            }
        }
    }

    func settings() { popover.performClose(nil); model.onShowSettings?() }

    private func showContext(_ app: LauncherApp, from anchor: NSView) {
        let menu = NSMenu()
        add(app.name, to: menu, enabled: false) {}
        add("開く", to: menu) { [weak self] in self?.open(app) }
        menu.addItem(.separator())
        add(app.pinned ? "固定を解除" : "タスクバーに固定", to: menu) { [weak self] in self?.model.togglePin(app.path) }
        if app.pinned {
            add("左へ移動", to: menu, enabled: model.pinnedPaths.first != app.path) { [weak self] in self?.model.movePin(app.path, offset: -1) }
            add("右へ移動", to: menu, enabled: model.pinnedPaths.last != app.path) { [weak self] in self?.model.movePin(app.path, offset: 1) }
        }
        if let running = app.running {
            menu.addItem(.separator())
            add("終了", to: menu) { running.terminate() }
        }
        track(menu, from: anchor)
    }

    private func showSettingsMenu(from anchor: NSView) {
        let menu = NSMenu()
        add("Window Menu", to: menu, enabled: false) {}
        add("アプリ一覧", to: menu) { [weak self] in self?.showDrawer() }
        add("設定…", to: menu) { [weak self] in self?.settings() }
        add(model.menusEnabled ? "ウィンドウメニューを一時停止" : "ウィンドウメニューを再開", to: menu) { [weak self] in
            guard let self else { return }; self.model.setMenus(!self.model.menusEnabled)
        }
        add(model.dockHidden ? "Dockを元に戻す" : "下のDockを自動非表示にする", to: menu) { [weak self] in
            guard let self else { return }; self.model.setDockHidden(!self.model.dockHidden)
        }
        menu.addItem(.separator())
        add("終了してDockを復元", to: menu) { NSApp.terminate(nil) }
        track(menu, from: anchor)
    }

    private func track(_ menu: NSMenu, from anchor: NSView) {
        interacting(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: anchor)
        interacting(false)
    }

    private func add(_ title: String, to menu: NSMenu, enabled: Bool = true, action: @escaping () -> Void) {
        let item = ClosureMenuItem(title: title, enabled: enabled, action: action)
        menu.autoenablesItems = false
        menu.addItem(item)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let invoke: () -> Void
    init(title: String, enabled: Bool, action: @escaping () -> Void) {
        invoke = action
        super.init(title: title, action: #selector(chosen), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func chosen() {
        let action = invoke
        DispatchQueue.main.async { action() }
    }
}
