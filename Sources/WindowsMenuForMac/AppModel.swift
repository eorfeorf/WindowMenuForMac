import AppKit
import ApplicationServices
import SwiftUI
import WindowMenuCore

final class AppModel: ObservableObject {
    @Published var menusEnabled: Bool
    @Published var launcherEnabled: Bool
    @Published var dockHidden: Bool
    @Published var insidePlacement: Bool
    @Published var iconLimit: Int
    @Published var trusted = AXIsProcessTrusted()
    @Published var windowCount = 0
    @Published var error: String?
    @Published var pinnedPaths: [String]
    @Published var excludedBundleIDs: [String]
    var onChange: (() -> Void)?
    var onShowSettings: (() -> Void)?
    let dock = DockSession(preferences: SystemDockPreferences(), recovery: SavedDockRecovery())
    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["menusEnabled": true, "launcherEnabled": true, "iconLimit": 4])
        menusEnabled = defaults.bool(forKey: "menusEnabled")
        launcherEnabled = defaults.bool(forKey: "launcherEnabled")
        dockHidden = defaults.bool(forKey: "dockHidden")
        insidePlacement = defaults.bool(forKey: "insidePlacement")
        // v0.1 used four independent icons by default. The grouped taskbar defaults to automatic sizing.
        if defaults.object(forKey: "taskbarIconLimit") == nil {
            let old = defaults.integer(forKey: "iconLimit")
            iconLimit = old == 4 ? 0 : min(16, max(0, old))
        } else { iconLimit = min(16, max(0, defaults.integer(forKey: "taskbarIconLimit"))) }
        pinnedPaths = defaults.stringArray(forKey: "pinnedPaths") ?? Self.dockAppPaths()
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
    }

    func start() {
        do {
            try dock.restore()
            if dockHidden && launcherEnabled { try dock.hide() }
            else if dockHidden { dockHidden = false; save() }
        } catch {
            dockHidden = false
            save()
            self.error = error.localizedDescription
        }
    }

    func setMenus(_ value: Bool) { menusEnabled = value; save() }
    func setLauncher(_ value: Bool) {
        if !value && dockHidden {
            setDockHidden(false)
            guard !dockHidden else { return }
        }
        launcherEnabled = value
        save()
    }
    func setInside(_ value: Bool) { insidePlacement = value; save() }
    func setIconLimit(_ value: Int) { iconLimit = min(16, max(0, value)); save() }

    func movePin(_ path: String, before target: String) {
        pinnedPaths = PinnedOrder.moving(path, before: target, in: pinnedPaths)
        save()
    }

    func movePin(_ path: String, offset: Int) {
        pinnedPaths = PinnedOrder.moving(path, offset: offset, in: pinnedPaths)
        save()
    }

    func setDockHidden(_ value: Bool) {
        do {
            if value {
                launcherEnabled = true
                try dock.hide()
            } else { try dock.restore() }
            dockHidden = value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        save()
    }

    func restoreDock() {
        do {
            try dock.restore()
            dockHidden = false
            error = nil
            save()
        } catch { self.error = error.localizedDescription }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func togglePin(_ path: String) {
        if pinnedPaths.contains(path) { pinnedPaths.removeAll { $0 == path } }
        else { pinnedPaths.append(path) }
        save()
    }

    func addApplications() {
        let panel = NSOpenPanel()
        panel.title = "上部ランチャーに固定するアプリを選択"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            for url in panel.urls where !pinnedPaths.contains(url.path) { pinnedPaths.append(url.path) }
            save()
        }
    }

    func importDock() {
        for path in Self.dockAppPaths() where !pinnedPaths.contains(path) { pinnedPaths.append(path) }
        save()
    }

    func toggleExclusion(_ bundleID: String) {
        if excludedBundleIDs.contains(bundleID) { excludedBundleIDs.removeAll { $0 == bundleID } }
        else { excludedBundleIDs.append(bundleID) }
        save()
    }

    func save() {
        defaults.set(menusEnabled, forKey: "menusEnabled")
        defaults.set(launcherEnabled, forKey: "launcherEnabled")
        defaults.set(dockHidden, forKey: "dockHidden")
        defaults.set(insidePlacement, forKey: "insidePlacement")
        defaults.set(iconLimit, forKey: "iconLimit")
        defaults.set(iconLimit, forKey: "taskbarIconLimit")
        defaults.set(pinnedPaths, forKey: "pinnedPaths")
        defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs")
        onChange?()
    }

    private static func dockAppPaths() -> [String] {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let items = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
        var paths: [String] = []
        for item in items {
            guard let tile = item["tile-data"] as? [String: Any],
                  let file = tile["file-data"] as? [String: Any],
                  let raw = file["_CFURLString"] as? String,
                  let url = URL(string: raw), url.isFileURL, url.pathExtension == "app",
                  FileManager.default.fileExists(atPath: url.path), !paths.contains(url.path) else { continue }
            paths.append(url.path)
        }
        return paths
    }
}
