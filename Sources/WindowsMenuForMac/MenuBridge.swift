import AppKit
import ApplicationServices

private final class MenuCommand {
    let element: AXUIElement
    let pid: pid_t
    init(_ element: AXUIElement, pid: pid_t) { self.element = element; self.pid = pid }
}

final class MenuBridge: NSObject, NSMenuDelegate {
    var onTracking: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    private var sources: [ObjectIdentifier: AXUIElement] = [:]
    private var target: WindowTarget?
    private var pendingAction: (() -> Void)?
    private var rootMenu: NSMenu?

    func show(heading: MenuHeading, target: WindowTarget, button: NSButton) {
        guard rootMenu == nil, let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else { return }
        self.target = target
        onTracking?(true)
        button.isEnabled = false
        app.activate(options: [.activateIgnoringOtherApps])
        let raised = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
        guard raised == .success else {
            button.isEnabled = true
            onTracking?(false)
            onError?("このウィンドウを操作対象にできませんでした。対象のウィンドウを一度クリックしてから再試行してください。")
            return
        }
        // Let the target application validate its window-specific menu items.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak button] in
            guard let self, let button else { self?.onTracking?(false); return }
            button.isEnabled = true
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                  let focused = AX.element(AXUIElementCreateApplication(target.pid), kAXFocusedWindowAttribute),
                  CFEqual(focused, target.element), button.window?.isVisible == true else {
                self.onTracking?(false)
                return
            }
            // Refresh the source after activation; apps can rebuild their menu bar per window.
            let fresh = WindowScanner.headings(AXUIElementCreateApplication(target.pid))
                .first(where: { $0.title == heading.title }) ?? heading
            let menu = self.makeMenu(title: fresh.title, source: fresh.element)
            self.rootMenu = menu
            self.populate(menu)
            menu.addItem(.separator())
            let original = NSMenuItem(title: "上部の元のメニューを開く", action: #selector(self.performCommand(_:)), keyEquivalent: "")
            original.target = self
            original.representedObject = MenuCommand(fresh.element, pid: target.pid)
            menu.addItem(original)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 3), in: button)
            self.rootMenu = nil
            self.sources.removeAll()
            self.target = nil
            self.onTracking?(false)
            let action = self.pendingAction
            self.pendingAction = nil
            // AXPress runs after our NSMenu has released menu tracking.
            DispatchQueue.main.async { action?() }
        }
    }

    private func makeMenu(title: String, source: AXUIElement) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.delegate = self
        sources[ObjectIdentifier(menu)] = source
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu !== rootMenu { populate(menu) }
    }

    private func populate(_ menu: NSMenu) {
        guard let source = sources[ObjectIdentifier(menu)], let target else { return }
        menu.removeAllItems()
        let deadline = Date().addingTimeInterval(0.8)
        let children = AX.menuChildren(source)
        var truncated = false
        for element in children {
            if Date() > deadline { truncated = true; break }
            let title = AX.string(element, kAXTitleAttribute) ?? ""
            if title.isEmpty { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: #selector(performCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuCommand(element, pid: target.pid)
            item.isEnabled = AX.bool(element, kAXEnabledAttribute) ?? false
            if let mark = AX.string(element, kAXMenuItemMarkCharAttribute), !mark.isEmpty { item.state = .on }
            if let key = AX.string(element, kAXMenuItemCmdCharAttribute), !key.isEmpty {
                item.keyEquivalent = key.lowercased()
                let raw = (AX.value(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
                var modifiers: NSEvent.ModifierFlags = []
                if raw & 8 == 0 { modifiers.insert(.command) }
                if raw & 1 != 0 { modifiers.insert(.shift) }
                if raw & 2 != 0 { modifiers.insert(.option) }
                if raw & 4 != 0 { modifiers.insert(.control) }
                item.keyEquivalentModifierMask = modifiers
            }
            let descendants = AX.elements(element, kAXChildrenAttribute, limit: 1)
            if descendants.contains(where: { AX.string($0, kAXRoleAttribute) == kAXMenuRole }) {
                item.submenu = makeMenu(title: title, source: element)
                item.action = nil
            }
            menu.addItem(item)
        }
        if menu.items.isEmpty || truncated {
            let note = NSMenuItem(title: truncated ? "残りの項目は元のメニューで開いてください" : "このメニューは元のメニューから開いてください", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? MenuCommand, let target else { return }
        pendingAction = { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == command.pid,
                  let focused = AX.element(AXUIElementCreateApplication(command.pid), kAXFocusedWindowAttribute),
                  CFEqual(focused, target.element) else {
                self?.onError?("操作対象のウィンドウが変わったため、メニュー操作を中止しました。")
                return
            }
            let result = AXUIElementPerformAction(command.element, kAXPressAction as CFString)
            if result != .success {
                self?.onError?("このアプリはメニューの外部操作に対応していないか、項目が更新されました。上部の元のメニューから操作してください。")
            }
        }
    }
}
