import AppKit
import SwiftUI

/// The window that holds the settings. Titled but with the title hidden, so the content runs to
/// the top edge like a native utility, and `fullSizeContentView` lets the sidebar material show
/// through the way System Settings does.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var hosting: NSHostingView<AnyView>?
    private var engine: PingFlowEngine?
    private var closeObserver: NSObjectProtocol?

    private init() {
        // The wheel and the library that feeds it share a row, so the window keeps a width that
        // holds both; any narrower and the library falls below the wheel again.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.title = "PingFlow Settings"
        window.minSize = NSSize(width: 1000, height: 620)
        window.setContentSize(NSSize(width: 1060, height: 680))
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "PingFlowSettings"
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("PingFlowSettingsWindow")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(engine: PingFlowEngine) {
        self.engine = engine
        if hosting == nil {
            let root = SettingsRootView()
                .environmentObject(engine.store)
                .environmentObject(engine)
                .environmentObject(SettingsRouter.shared)
                .environmentObject(engine.scene)
                .environmentObject(engine.permissions)
                .environmentObject(engine.audio)
                .environmentObject(engine.loginItems)
            let view = AnyView(root.preferredColorScheme(engine.store.settings.appearanceMode.colorScheme))
            let hosting = NSHostingView(rootView: view)
            hosting.frame = window?.contentView?.bounds ?? .zero
            hosting.autoresizingMask = [.width, .height]
            window?.contentView?.addSubview(hosting)
            self.hosting = hosting
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        engine?.coordinator.releaseAllRecorders()
        engine?.permissions.stopPolling()
    }

    /// ⌘W and the red button must not destroy the window; closing hides it, the app keeps running.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window?.orderOut(nil)
        // Hiding is not a close, so nothing else would hand the tap back. A recorder left mid-flight
        // must never keep the wheel dead behind a window the user can no longer see.
        engine?.coordinator.releaseAllRecorders()
        return true
    }
}
