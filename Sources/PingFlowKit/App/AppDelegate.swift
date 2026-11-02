import AppKit
import SwiftUI
import Combine

/// App shell. There is no main window: the app lives in the menu bar and the settings window is
/// a panel that opens when asked. The Dock icon only appears while that window is on screen,
/// which is what makes a menu bar utility feel like one.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine: PingFlowEngine
    private var cancellables: Set<AnyCancellable> = []
    private var didFinishLaunching = false

    public override init() {
        engine = PingFlowEngine(store: .shared)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        engine.start()

        let settings = engine.store.settings
        let firstRun = !FileManager.default.fileExists(atPath: engine.store.fileURL.path)
        if firstRun || !engine.permissions.isGranted {
            // Never leave someone with a dead app and no explanation: open the settings, land on
            // Permissions, and let the page do the talking.
            openSettings(selecting: firstRun ? .general : .permissions)
        }

        engine.permissions.$isGranted
            .dropFirst()
            .sink { [weak self] granted in
                guard let self, granted else { return }
                self.engine.permissions.stopPolling()
            }
            .store(in: &cancellables)
        _ = settings
    }

    /// Reopening from the Dock, or `open -a PingFlow` a second time, shows the settings.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationWillTerminate(_ notification: Notification) {
        engine.store.flushSave()
    }

    // MARK: - Windows

    func openSettings(selecting pane: SettingsPane? = nil) {
        if let pane { SettingsRouter.shared.open(pane) }
        SettingsWindowController.shared.show(engine: engine)
        setDockVisible(engine.store.settings.showDockIconWhileSettingsOpen)
    }

    private func setDockVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    /// A minimal menu so ⌘Q, W and the clipboard work in text fields. Anything more would be
    /// noise in a menu bar app.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About PingFlow", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PingFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettings() { openSettings() }

    @objc private func showAbout() { openSettings(selecting: .about) }
}
