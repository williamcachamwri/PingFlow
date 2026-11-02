import AppKit
import SwiftUI

/// The app's whole front door: a template glyph in the menu bar and four items. Nothing else,
/// because a utility that lives in the menu bar should not have to be navigated.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    enum Action {
        case toggleEnabled
        case openSettings
        case toggleWheel
        case quit
    }

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let onAction: (Action) -> Void
    private var isEnabled = true
    private var wheelHint = "⌃⌥P"

    init(onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
        super.init()
    }

    /// Adds or removes the item as the setting changes, so "Show menu bar icon" is honest.
    func setVisible(_ visible: Bool) {
        guard visible else {
            statusItem.map { NSStatusBar.system.removeStatusItem($0) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image()
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "PingFlow — hold ⌥ and drag"
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuild()
    }

    func setState(enabled: Bool, wheelShortcut: String?) {
        isEnabled = enabled
        wheelHint = wheelShortcut ?? ""
        rebuild()
        // A disabled app should read as disabled without anyone opening the menu.
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.alphaValue = enabled ? 1 : 0.45
    }

    private func rebuild() {
        menu.removeAllItems()

        let enable = NSMenuItem(title: isEnabled ? "Disable Ping Wheel" : "Enable Ping Wheel",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        enable.target = self
        enable.state = isEnabled ? .on : .off
        menu.addItem(enable)

        let toggle = NSMenuItem(title: "Toggle Ping Wheel", action: #selector(toggleWheel),
                                keyEquivalent: "")
        toggle.target = self
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.keyEquivalent = "p"
        toggle.isEnabled = true
        menu.addItem(toggle)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit PingFlow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() { onAction(.toggleEnabled) }
    @objc private func toggleWheel() { onAction(.toggleWheel) }
    @objc private func openSettings() { onAction(.openSettings) }
    @objc private func quit() { onAction(.quit) }

    /// The menu is rebuilt on open so the checkmark always matches the live setting.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }
}

/// A small ping-wheel mark: ring, eight spokes, hub. Drawn, not shipped as a PNG, so it stays
/// crisp at every menu bar scale and takes the system's light/dark tint as a template image.
enum MenuBarIcon {
    static func image(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let outer = rect.width * 0.44
            let inner = outer * 0.42
            NSColor.black.setStroke()
            NSColor.black.setFill()

            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4 - .pi / 2
                let start = CGPoint(x: centre.x + cos(angle) * inner, y: centre.y + sin(angle) * inner)
                let end = CGPoint(x: centre.x + cos(angle) * outer, y: centre.y + sin(angle) * outer)
                let path = NSBezierPath()
                path.move(to: start)
                path.line(to: end)
                path.lineWidth = 1.1
                path.stroke()
            }
            let ring = NSBezierPath(ovalIn: CGRect(x: centre.x - outer, y: centre.y - outer,
                                                   width: outer * 2, height: outer * 2))
            ring.lineWidth = 1.3
            ring.stroke()
            let hub = NSBezierPath(ovalIn: CGRect(x: centre.x - inner * 0.55, y: centre.y - inner * 0.55,
                                                  width: inner * 1.1, height: inner * 1.1))
            hub.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
