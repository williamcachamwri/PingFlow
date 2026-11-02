import AppKit
import Combine
import SwiftUI

/// The composition root. Every subsystem is constructed here and nowhere else, so the graph is
/// readable in one screen: settings → input → gesture → overlay → audio, with assets behind them.
@MainActor
final class PingFlowEngine: ObservableObject {
    let store: SettingsStore
    let scene: WheelScene
    let emoteScene: EmoteScene
    let overlay: OverlayController
    let audio: AudioEngine
    let permissions: PermissionManager
    let loginItems: LoginItemController
    let coordinator: InputCoordinator
    let tap: EventTap

    @Published private(set) var tapStatus: EventTap.Status = .stopped
    @Published private(set) var isWheelActive = false
    @Published private(set) var isEmoteWheelActive = false

    private var cancellables: Set<AnyCancellable> = []
    private var menuBar: MenuBarController?

    init(store: SettingsStore) {
        let scene = WheelScene()
        let emoteScene = EmoteScene()
        let overlay = OverlayController(scene: scene, emoteScene: emoteScene, store: store)
        let audio = AudioEngine()
        let permissions = PermissionManager()
        let loginItems = LoginItemController()
        let coordinator = InputCoordinator(store: store, scene: scene, emoteScene: emoteScene,
                                           overlay: overlay, audio: audio)
        let tap = EventTap()

        self.store = store
        self.scene = scene
        self.emoteScene = emoteScene
        self.overlay = overlay
        self.audio = audio
        self.permissions = permissions
        self.loginItems = loginItems
        self.coordinator = coordinator
        self.tap = tap

        wire()
    }

    private func wire() {
        audio.bind(to: store)

        tap.setHandler { [weak coordinator] event in
            // The tap thread never touches UI; it hands the decoded event to the main actor.
            Task { @MainActor [weak coordinator] in coordinator?.handle(event) }
        }

        store.$settings
            .sink { [weak self] settings in self?.apply(settings: settings) }
            .store(in: &cancellables)

        permissions.$isGranted
            .removeDuplicates()
            .sink { [weak self] granted in self?.permissionChanged(granted: granted) }
            .store(in: &cancellables)

        scene.$phase
            .map { $0 == .opening || $0 == .active }
            .removeDuplicates()
            .sink { [weak self] active in self?.isWheelActive = active }
            .store(in: &cancellables)

        emoteScene.$phase
            .map { $0 == .opening || $0 == .active }
            .removeDuplicates()
            .sink { [weak self] active in self?.isEmoteWheelActive = active }
            .store(in: &cancellables)

        // Sleep/wake is delivered by the workspace, not the app; after a wake the tap has often
        // been dropped by macOS and has to be rebuilt.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterWake() }
        }
    }

    // MARK: - Startup

    func start() {
        Log.lifecycle.info("PingFlow starting")
        loginItems.refresh()
        audio.warmUp()
        apply(settings: store.settings)
        // Ask once at launch. A prompt here is worse than the Permissions page, which explains
        // why the key is needed, so the prompt only comes when the user asks for access.
        if permissions.isGranted {
            startTap()
        } else {
            tapStatus = .noAccess
            permissions.startPolling()
        }
        menuBar = MenuBarController { [weak self] action in self?.handle(action: action) }
        menuBar?.setVisible(store.settings.showMenuBarIcon)
        menuBar?.setState(enabled: store.settings.isEnabled,
                          wheelShortcut: store.settings.toggleShortcut?.displayString)
    }

    func startTap() {
        let ok = tap.start()
        tapStatus = tap.currentStatus
        if ok {
            permissions.stopPolling()
            permissions.refresh()
        } else if tapStatus == .noAccess {
            permissions.startPolling()
        }
        Log.lifecycle.info("Event tap start \(ok ? "succeeded" : "refused", privacy: .public)")
    }

    /// Called by the Permissions page's retry. A refused tap must never become a restart loop.
    func retryTap() {
        startTap()
    }

    private func permissionChanged(granted: Bool) {
        if granted {
            if tapStatus != .running { startTap() }
        } else {
            coordinator.forceClose()
            tap.stop()
            tapStatus = .noAccess
            permissions.startPolling()
            Log.lifecycle.warning("Accessibility revoked; the wheel is paused until it returns")
        }
    }

    private func resumeAfterWake() {
        guard store.settings.isEnabled else { return }
        if tapStatus != .running, permissions.isGranted { startTap() }
    }

    // MARK: - Settings fan-out

    private func apply(settings: AppSettings) {
        menuBar?.setVisible(settings.showMenuBarIcon)
        menuBar?.setState(enabled: settings.isEnabled, wheelShortcut: settings.toggleShortcut?.displayString)
        scene.sync(settings: settings)
        emoteScene.sync(settings: settings)

        if !settings.isEnabled {
            coordinator.forceClose()
        }
        if settings.isEnabled, tapStatus != .running, permissions.isGranted {
            startTap()
        }
        if !settings.isEnabled, tapStatus == .running {
            tap.stop()
            tapStatus = .stopped
        }

        // The appearance of the whole app, including the overlay's materials. `nil` means
        // "follow the system", which is what the System choice has to mean.
        switch settings.appearanceMode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Menu bar

    private func handle(action: MenuBarController.Action) {
        switch action {
        case .toggleEnabled:
            coordinator.toggleEnabled()
        case .toggleWheel:
            coordinator.toggleEnabled()
        case .openSettings:
            SettingsWindowController.shared.show(engine: self)
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// A wheel opened by the user, not by a gesture: used by the menu and by tests.
    func presentWheelAtCurrentPointer() {
        let point = CoordinateSpace.cgPoint(fromAppKit: NSEvent.mouseLocation)
        overlay.presentWheel(at: point)
        scene.open(at: point, settings: store.settings)
    }

    func retractWheel() {
        coordinator.forceClose()
    }
}
