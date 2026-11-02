import AppKit
import SwiftUI
import Combine

/// A window that draws over everything, takes no focus and takes no clicks.
///
/// * `.nonactivatingPanel` + `.borderless` — the app underneath keeps the keyboard.
/// * `ignoresMouseEvents` — the pointer passes straight through to the user's app, which is how
///   a wheel that follows the cursor can coexist with normal mouse use.
/// * `.screenSaver` level with `.fullScreenAuxiliary` — sits above ordinary windows and above
///   most full-screen apps. Exclusive-mode games are still out of reach; that is macOS, not us.
/// * `hidesOnDeactivate = false` — a ping must not vanish because the user alt-tabbed.
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .readOnly
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns one overlay panel per connected display and moves wheel and ping drawing onto the right
/// one. Screens can come and go at any moment, so panels are created lazily and swept when idle.
@MainActor
final class OverlayController: ObservableObject {
    private struct Managed {
        let panel: OverlayPanel
        let screen: NSScreen
        let host: OverlayHost
    }

    private var managed: [OverlayKey: Managed] = [:]
    private let sweepQueue = DispatchQueue.main
    private var pendingSweeps: [OverlayKey: DispatchWorkItem] = [:]

    /// Screen identifier that survives a re-plug for as long as macOS keeps the same display.
    private typealias OverlayKey = UInt32

    let scene: WheelScene
    let emoteScene: EmoteScene
    private let store: SettingsStore
    private var screenObserver: NSObjectProtocol?

    init(scene: WheelScene, emoteScene: EmoteScene, store: SettingsStore) {
        self.scene = scene
        self.emoteScene = emoteScene
        self.store = store
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screensChanged() }
            }
    }

    deinit { screenObserver.map { NotificationCenter.default.removeObserver($0) } }

    private func key(for screen: NSScreen) -> OverlayKey {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func panel(for screen: NSScreen) -> Managed {
        let identifier = key(for: screen)
        if let existing = managed[identifier] {
            // Resolution and placement can change under a live display; the panel must follow.
            if existing.panel.frame != screen.frame {
                existing.panel.setFrame(screen.frame, display: false)
                existing.host.resize(to: screen.frame.size)
            }
            return existing
        }
        let panel = OverlayPanel(screen: screen)
        let host = OverlayHost(scene: scene, emoteScene: emoteScene, store: store, screenFrame: screen.frame)
        panel.contentView = host.rootView
        let managed = Managed(panel: panel, screen: screen, host: host)
        self.managed[identifier] = managed
        Log.overlay.info("Created overlay panel for \(screen.localizedName, privacy: .public)")
        return managed
    }

    /// The display holding a CoreGraphics global point, or the primary one.
    private func screen(containing point: CGPoint) -> NSScreen? {
        let appKitPoint = CoordinateSpace.appKitPoint(from: point)
        return NSScreen.screens.first { $0.frame.contains(appKitPoint) } ?? NSScreen.screens.first
    }

    // MARK: - Wheel

    func presentWheel(at globalPoint: CGPoint) {
        guard let screen = screen(containing: globalPoint) else {
            Log.overlay.warning("No screen under the press point; the wheel stayed hidden")
            return
        }
        let target = panel(for: screen)
        cancelSweep(for: key(for: screen))
        target.host.placeWheel(at: globalPoint)
        target.panel.orderFrontRegardless()
    }

    func dismissWheel() {
        for entry in managed.values {
            entry.host.retireWheel()
        }
        sweepIdlePanels(after: 0.2)
    }

    // MARK: - Emote wheel

    func presentEmoteWheel(at globalPoint: CGPoint) {
        guard let screen = screen(containing: globalPoint) else {
            Log.overlay.warning("No screen under the press point; the emote wheel stayed hidden")
            return
        }
        let target = panel(for: screen)
        cancelSweep(for: key(for: screen))
        target.host.placeEmoteWheel(at: globalPoint)
        target.panel.orderFrontRegardless()
    }

    func dismissEmoteWheel() {
        for entry in managed.values {
            entry.host.retireEmoteWheel()
        }
        sweepIdlePanels(after: 0.2)
    }

    // MARK: - Emotes

    func spawnEmote(_ definition: EmoteDefinition, at globalPoint: CGPoint) {
        guard let screen = screen(containing: globalPoint) else { return }
        let identifier = key(for: screen)
        let target = panel(for: screen)
        cancelSweep(for: identifier)
        target.host.spawnEmote(definition, at: globalPoint)
        target.panel.orderFrontRegardless()
        let lifetime = EmoteStage.displayDuration + 0.4
        sweepIdlePanels(for: identifier, after: lifetime)
    }

    // MARK: - Pings

    func spawnPing(_ definition: PingDefinition, at globalPoint: CGPoint) {
        guard let screen = screen(containing: globalPoint) else { return }
        let identifier = key(for: screen)
        let target = panel(for: screen)
        cancelSweep(for: identifier)
        target.host.spawnPing(definition, at: globalPoint)
        target.panel.orderFrontRegardless()
        // The longest animation decides when the panel can go back to sleep.
        let lifetime = store.settings.pingDuration + 0.4
        sweepIdlePanels(for: identifier, after: lifetime)
    }

    /// A preview from the settings window lands on a chosen display rather than under a cursor.
    func spawnPingOnMainDisplay(_ definition: PingDefinition) {
        guard let screen = NSScreen.screens.first else { return }
        let centre = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        spawnPing(definition, at: CoordinateSpace.cgPoint(fromAppKit: centre))
    }

    // MARK: - Housekeeping

    private func screensChanged() {
        let live = Set(NSScreen.screens.map { key(for: $0) })
        for identifier in managed.keys where !live.contains(identifier) {
            managed[identifier]?.panel.orderOut(nil)
            managed[identifier] = nil
            pendingSweeps[identifier]?.cancel()
            pendingSweeps[identifier] = nil
            Log.overlay.info("Dropped overlay panel for a disconnected display")
        }
        for screen in NSScreen.screens {
            let identifier = key(for: screen)
            guard let entry = managed[identifier] else { continue }
            if entry.panel.frame != screen.frame {
                entry.panel.setFrame(screen.frame, display: false)
                entry.host.resize(to: screen.frame.size)
            }
        }
    }

    /// Panels with nothing to draw are ordered out, so the app never leaves invisible windows
    /// sitting at screen-saver level.
    private func sweepIdlePanels(after delay: TimeInterval) {
        for identifier in managed.keys { sweepIdlePanels(for: identifier, after: delay) }
    }

    private func sweepIdlePanels(for identifier: OverlayKey, after delay: TimeInterval) {
        pendingSweeps[identifier]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let entry = self.managed[identifier] else { return }
            if !entry.host.isBusy {
                entry.panel.orderOut(nil)
                Log.overlay.debug("Swept idle overlay panel")
            }
        }
        pendingSweeps[identifier] = work
        sweepQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelSweep(for identifier: OverlayKey) {
        pendingSweeps[identifier]?.cancel()
        pendingSweeps[identifier] = nil
    }

    func hideEverything() {
        for entry in managed.values {
            entry.host.retireWheel()
            entry.host.retireEmoteWheel()
            entry.panel.orderOut(nil)
        }
    }

    /// The panel currently carrying the wheel, for `--live-wheel`. Photographing the real window
    /// is the only way to prove the overlay paints, and an off-screen render cannot show it.
    func debugWheelPanel() -> (panel: OverlayPanel, host: OverlayHost)? {
        managed.values.first { $0.host.scene.phase != .hidden }.map { ($0.panel, $0.host) }
    }
}
