import AppKit
import ApplicationServices
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let scanner = WindowScanner()
    private let bars = WindowBars()
    private var launcher: Launcher?
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var previewMode = false
    private var shuttingDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-preview"), args.indices.contains(index + 1) {
            previewMode = true
            showSettings()
            let output = args[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.renderPreview(to: output)
                NSApp.terminate(nil)
            }
            return
        }
        // Avoid two processes competing to own the Dock recovery snapshot.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            })?.activate(options: [.activateIgnoringOtherApps])
            previewMode = true
            NSApp.terminate(nil)
            return
        }
        model.start()
        launcher = Launcher(model: model)
        model.onShowSettings = { [weak self] in self?.showSettings() }
        model.onChange = { [weak self] in self?.applySettings() }
        bars.bridge.onTracking = { [weak self] tracking in self?.scanner.suspended = tracking }
        bars.bridge.onError = { [weak self] message in self?.model.error = message; self?.showSettings() }
        scanner.onUpdate = { [weak self] targets in
            guard let self, !self.shuttingDown else { return }
            self.bars.update(targets)
            if self.model.windowCount != targets.count { self.model.windowCount = targets.count }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            observe(workspace, name) { [weak self] in self?.launcher?.refresh(); self?.scanner.refresh() }
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.scanner.invalidate()
            self?.scanner.refresh()
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.launcher?.screenChanged()
            self?.scanner.invalidate()
            self?.scanner.refresh()
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.scanner.suspended = true
            self?.scanner.invalidate()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.scanner.suspended = false
            self?.scanner.refresh()
        }
        applySettings()
        scanner.start()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if self.model.trusted != trusted {
                self.model.trusted = trusted
                self.scanner.invalidate()
                self.scanner.refresh()
            }
        }
        if !model.trusted || !UserDefaults.standard.bool(forKey: "hasOpenedSettings") || model.error != nil {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
        }
    }

    private func applySettings() {
        let changed = scanner.enabled != model.menusEnabled || bars.inside != model.insidePlacement ||
            bars.excludedBundleIDs != Set(model.excludedBundleIDs)
        scanner.enabled = model.menusEnabled
        bars.inside = model.insidePlacement
        bars.excludedBundleIDs = Set(model.excludedBundleIDs)
        if changed { scanner.invalidate(); scanner.refresh() }
        launcher?.refresh()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Window Menu"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, launcher: launcher))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if previewMode { return .terminateNow }
        do {
            try model.dock.restore()
            shuttingDown = true
            scanner.enabled = false
            bars.update([])
            return .terminateNow
        } catch {
            model.error = "Dockの復元に失敗しました。復元を再試行してください。\n\(error.localizedDescription)"
            showSettings()
            return .terminateCancel
        }
    }

    private func renderPreview(to path: String) {
        guard let view = settingsWindow?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }
}
