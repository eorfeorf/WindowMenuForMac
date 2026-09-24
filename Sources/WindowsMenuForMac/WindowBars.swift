import AppKit
import WindowMenuCore

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HeadingButton: NSButton {
    var invoke: (() -> Void)?
    init(title: String, action: @escaping () -> Void) {
        self.invoke = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(clicked)
        isBordered = false
        bezelStyle = .inline
        font = .menuFont(ofSize: 12)
        setButtonType(.momentaryChange)
        toolTip = title
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func clicked() { invoke?() }
}

private final class WindowBar: NSObject {
    let panel: MenuPanel
    var target: WindowTarget
    let bridge: MenuBridge
    private let background = NSVisualEffectView()
    private var buttons: [HeadingButton] = []
    private let overflow = HeadingButton(title: "»", action: {})
    private var hiddenHeadings: [MenuHeading] = []
    private var labels: [String] = []
    var preferredWidth: CGFloat { min(900, buttons.reduce(12) { $0 + width(of: $1) }) }

    init(target: WindowTarget, bridge: MenuBridge) {
        self.target = target
        self.bridge = bridge
        panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .transient]
        panel.isMovable = false
        panel.title = "\(target.appName) のウィンドウメニュー"
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.contentView = background
        overflow.invoke = { [weak self] in self?.showOverflow() }
        overflow.toolTip = "その他のメニュー"
        overflow.setAccessibilityLabel("その他のメニュー")
        update(target)
    }

    func update(_ target: WindowTarget) {
        self.target = target
        let titles = target.headings.map(\.title)
        guard titles != labels else { return }
        labels = titles
        buttons.forEach { $0.removeFromSuperview() }
        buttons = target.headings.enumerated().map { index, heading in
            let button = HeadingButton(title: heading.title, action: {})
            if index == 0 { button.font = .boldSystemFont(ofSize: 12) }
            button.invoke = { [weak self, weak button] in
                guard let self, let button, self.target.headings.indices.contains(index) else { return }
                self.bridge.show(heading: self.target.headings[index], target: self.target, button: button)
            }
            background.addSubview(button)
            return button
        }
        background.addSubview(overflow)
    }

    func position(_ frame: CGRect) {
        panel.setFrame(frame, display: true)
        background.frame = CGRect(origin: .zero, size: frame.size)
        var x: CGFloat = 6
        hiddenHeadings = []
        for (index, button) in buttons.enumerated() {
            let w = width(of: button)
            let reserve: CGFloat = index == buttons.count - 1 ? 6 : 30
            let fits = hiddenHeadings.isEmpty && x + w <= frame.width - reserve
            button.isHidden = !fits
            if fits {
                button.frame = CGRect(x: x, y: 2, width: w, height: 24)
                x += w
            } else { hiddenHeadings.append(target.headings[index]) }
        }
        overflow.isHidden = hiddenHeadings.isEmpty
        overflow.frame = CGRect(x: frame.width - 30, y: 2, width: 26, height: 24)
        panel.order(.above, relativeTo: Int(target.id))
    }

    private func width(of button: NSButton) -> CGFloat {
        min(160, max(32, (button.title as NSString).size(withAttributes: [.font: button.font!]).width + 18))
    }

    private func showOverflow() {
        let menu = NSMenu()
        for (index, heading) in hiddenHeadings.enumerated() {
            let item = NSMenuItem(title: heading.title, action: #selector(selectOverflow(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        bridge.onTracking?(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -3), in: overflow)
        bridge.onTracking?(false)
    }

    @objc private func selectOverflow(_ sender: NSMenuItem) {
        guard hiddenHeadings.indices.contains(sender.tag) else { return }
        let heading = hiddenHeadings[sender.tag]
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bridge.show(heading: heading, target: self.target, button: self.overflow)
        }
    }
}

final class WindowBars {
    var inside = false
    var excludedBundleIDs: Set<String> = []
    let bridge = MenuBridge()
    private var bars: [CGWindowID: WindowBar] = [:]

    func update(_ targets: [WindowTarget]) {
        var retained = Set<CGWindowID>()
        for target in targets {
            if let id = NSRunningApplication(processIdentifier: target.pid)?.bundleIdentifier,
               excludedBundleIDs.contains(id) { continue }
            guard let screen = NSScreen.screens.max(by: {
                area($0.frame.intersection(target.frame)) < area($1.frame.intersection(target.frame))
            }) else { continue }
            // Fullscreen apps sometimes omit AXFullScreen; also check their actual geometry.
            if abs(target.frame.width - screen.frame.width) < 2 && abs(target.frame.height - screen.frame.height) < 2 { continue }
            let bar = bars[target.id] ?? WindowBar(target: target, bridge: bridge)
            bar.update(target)
            guard let frame = BarPlacement.frame(window: target.frame, visibleScreen: screen.visibleFrame,
                                                preferredWidth: bar.preferredWidth, inside: inside) else { continue }
            bars[target.id] = bar
            bar.position(frame)
            retained.insert(target.id)
        }
        for id in Array(bars.keys) where !retained.contains(id) {
            bars.removeValue(forKey: id)?.panel.close()
        }
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
