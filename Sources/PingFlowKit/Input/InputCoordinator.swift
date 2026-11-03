import AppKit
import Combine

/// Turns raw tap events into wheel gestures. It knows nothing about windows or drawing, and the
/// renderer knows nothing about key codes: the only thing between them is `WheelScene`.
///
/// Rules that keep the app honest about not interfering:
/// * Nothing is ever swallowed. The tap is listen-only, so a keystroke that cancels a wheel is
///   still delivered to whatever the user is typing into.
/// * Any other key pressed while the wheel is open cancels it, so `⌥⌘X` and friends keep working.
/// * The trigger is re-checked on every event, including mouse ones, because macOS hides
///   keyboard events from taps in secure text fields — the mouse flags are the fallback the
///   reference relies on for the same reason.
///
/// Two wheels share the gesture model: the ping wheel on Option (by default) and the emote wheel
/// on Control (by default). Both are configurable.
@MainActor
final class InputCoordinator {
    private let store: SettingsStore
    private let scene: WheelScene
    private let emoteScene: EmoteScene
    private let overlay: OverlayController
    private let audio: AudioEngine

    /// How many shortcut recorders are capturing keys right now. The global tap stands down for
    /// exactly that window. It used to stand down for as long as the settings window was open,
    /// which meant the wheel went dead whenever Settings happened to be on screen — and, because
    /// hiding the window never ran the close notification, sometimes stayed dead after it.
    private var recorders = 0
    var isSuspended: Bool { recorders > 0 }

    func recorderBegan() { recorders += 1 }
    func recorderEnded() { recorders = max(0, recorders - 1) }
    /// A window that goes away mid-recording must not leave the tap asleep forever.
    func releaseAllRecorders() { recorders = 0 }

    // MARK: - Ping wheel state

    private var triggerIsDown = false
    private var pressPoint = CGPoint.zero
    private var awaitingDrag = false
    private var sentThisGesture = false

    // MARK: - Emote wheel state

    private var emoteTriggerIsDown = false
    private var emotePressPoint = CGPoint.zero
    private var emoteAwaitingDrag = false
    private var emoteSentThisGesture = false

    init(store: SettingsStore, scene: WheelScene, emoteScene: EmoteScene,
         overlay: OverlayController, audio: AudioEngine) {
        self.store = store
        self.scene = scene
        self.emoteScene = emoteScene
        self.overlay = overlay
        self.audio = audio
    }

    // MARK: - Entry point, called on the main actor from the tap thread

    func handle(_ event: EventTap.Event) {
        let settings = store.settings
        guard settings.isEnabled, !isSuspended else {
            if scene.isOpen { cancelPingWheel() }
            if emoteScene.isOpen { cancelEmoteWheel() }
            return
        }

        // Secure input can hide the key-up, so every event re-reads the modifier state.
        if triggerIsDown, !isHoldingPingTrigger(in: event.flags) {
            releasePingTrigger(settings: settings)
        }
        if emoteTriggerIsDown, !isHoldingEmoteTrigger(in: event.flags) {
            releaseEmoteTrigger(settings: settings)
        }

        switch event.kind {
        case .flagsChanged:
            handleFlags(event, settings: settings)
        case .keyDown:
            handleKeyDown(event, settings: settings)
        case .mouseDown:
            handleMouseDown(event, settings: settings)
        case .mouseUp, .mouseMoved, .mouseDragged:
            handleMove(event, settings: settings)
        case .keyUp, .other:
            break
        }
    }

    // MARK: - Ping wheel trigger

    private var pingTriggerKeys: [ActivationModifier] {
        let settings = store.settings
        var keys = [settings.activationKey]
        if let secondary = settings.secondaryActivationKey, !keys.contains(secondary) { keys.append(secondary) }
        return keys
    }

    private func isHoldingPingTrigger(in flags: CGEventFlags) -> Bool {
        pingTriggerKeys.contains { flags.contains($0.cgFlag) }
    }

    // MARK: - Emote wheel trigger

    private func isHoldingEmoteTrigger(in flags: CGEventFlags) -> Bool {
        flags.contains(store.settings.emoteTrigger.cgFlag)
    }

    // MARK: - Flags

    private func handleFlags(_ event: EventTap.Event, settings: AppSettings) {
        // Ping wheel
        let pingDown = isHoldingPingTrigger(in: event.flags)
        if pingDown, !triggerIsDown {
            triggerIsDown = true
            pressPoint = event.location
            sentThisGesture = false
            awaitingDrag = true
            scene.sync(settings: settings)
        } else if !pingDown, triggerIsDown {
            releasePingTrigger(settings: settings)
        }

        // Emote wheel
        let emoteDown = isHoldingEmoteTrigger(in: event.flags)
        if emoteDown, !emoteTriggerIsDown, settings.emoteEnabled {
            emoteTriggerIsDown = true
            emotePressPoint = event.location
            emoteSentThisGesture = false
            emoteAwaitingDrag = true
            emoteScene.sync(settings: settings)
        } else if !emoteDown, emoteTriggerIsDown {
            releaseEmoteTrigger(settings: settings)
        }
    }

    private func releasePingTrigger(settings: AppSettings) {
        triggerIsDown = false
        awaitingDrag = false
        guard scene.isOpen else { return }
        if !sentThisGesture, let slice = scene.hoveredSlice {
            firePing(slice: slice, settings: settings)
        }
        scene.close()
        overlay.dismissWheel()
    }

    private func releaseEmoteTrigger(settings: AppSettings) {
        emoteTriggerIsDown = false
        emoteAwaitingDrag = false
        guard emoteScene.isOpen else { return }
        if !emoteSentThisGesture, let slice = emoteScene.hoveredSlice {
            fireEmote(slice: slice, settings: settings)
        }
        emoteScene.close()
        overlay.dismissEmoteWheel()
    }

    // MARK: - Movement

    private func handleMove(_ event: EventTap.Event, settings: AppSettings) {
        // Ping wheel movement
        if triggerIsDown {
            let dx = event.location.x - pressPoint.x
            let dy = event.location.y - pressPoint.y

            if awaitingDrag {
                switch event.kind {
                case .mouseDragged:
                    if hypot(dx, dy) >= settings.dragThreshold {
                        awaitingDrag = false
                        overlay.presentWheel(at: pressPoint)
                        scene.open(at: pressPoint, settings: settings)
                    }
                case .mouseUp:
                    firePingHub(settings: settings)
                    awaitingDrag = true
                default:
                    break
                }
            }

            if scene.isOpen {
                let deadZone = WheelGeometry.reference.innerRadius(atSize: CGFloat(settings.wheelSize))
                let index = WheelGeometry.sliceIndex(dx: dx, dy: dy, deadZone: deadZone)
                if scene.setHovered(index >= 0 ? index : nil) {
                    if index >= 0 { audio.playTick(settings: settings) }
                }
            }
        }

        // Emote wheel movement
        if emoteTriggerIsDown {
            let dx = event.location.x - emotePressPoint.x
            let dy = event.location.y - emotePressPoint.y

            if emoteAwaitingDrag {
                switch event.kind {
                case .mouseDragged:
                    if hypot(dx, dy) >= settings.dragThreshold {
                        emoteAwaitingDrag = false
                        overlay.presentEmoteWheel(at: emotePressPoint)
                        emoteScene.open(at: emotePressPoint, settings: settings)
                    }
                case .mouseUp:
                    fireEmoteHub(settings: settings)
                    emoteAwaitingDrag = true
                default:
                    break
                }
            }

            if emoteScene.isOpen {
                let deadZone = WheelGeometry.reference.innerRadius(atSize: CGFloat(settings.wheelSize))
                let index = WheelGeometry.sliceIndex(dx: dx, dy: dy, deadZone: deadZone)
                if emoteScene.setHovered(index >= 0 ? index : nil) {
                    if index >= 0 { audio.playTick(settings: settings) }
                }
            }
        }
    }

    // MARK: - Keys and buttons

    private func handleKeyDown(_ event: EventTap.Event, settings: AppSettings) {
        if let combo = settings.toggleShortcut,
           combo.matches(eventFlags: event.flags, keyCode: event.keyCode) {
            if scene.isOpen { cancelPingWheel() }
            if emoteScene.isOpen { cancelEmoteWheel() }
            toggleEnabled()
            return
        }

        // Escape cancels whichever wheel is open
        if event.keyCode == KeyboardKey.escape {
            if scene.isOpen { cancelPingWheel() }
            if emoteScene.isOpen { cancelEmoteWheel() }
            return
        }

        // Any other key cancels open wheels if configured
        if settings.cancelOnOtherKeyPress, !KeyboardKey.isModifierKey(Int(event.keyCode)) {
            if scene.isOpen { cancelPingWheel() }
            if emoteScene.isOpen { cancelEmoteWheel() }
        }
    }

    private func handleMouseDown(_ event: EventTap.Event, settings: AppSettings) {
        switch event.mouseButton {
        case 1:
            if settings.cancelOnRightClick {
                if scene.isOpen { cancelPingWheel() }
                if emoteScene.isOpen { cancelEmoteWheel() }
            }
        case 0:
            // Ping wheel click
            if scene.isOpen {
                switch settings.clickBehaviour {
                case .cancel:
                    cancelPingWheel()
                case .confirm:
                    if let slice = scene.hoveredSlice {
                        firePing(slice: slice, settings: settings)
                        sentThisGesture = true
                    } else {
                        firePingHub(settings: settings)
                        sentThisGesture = true
                    }
                    scene.close()
                    overlay.dismissWheel()
                    triggerIsDown = false
                case .ignore:
                    break
                }
            }

            // Emote wheel click
            if emoteScene.isOpen {
                if let slice = emoteScene.hoveredSlice {
                    fireEmote(slice: slice, settings: settings)
                    emoteSentThisGesture = true
                } else {
                    fireEmoteHub(settings: settings)
                    emoteSentThisGesture = true
                }
                emoteScene.close()
                overlay.dismissEmoteWheel()
                emoteTriggerIsDown = false
            }
        default:
            break
        }
    }

    // MARK: - Ping outcomes

    private func firePing(slice: Int, settings: AppSettings) {
        guard settings.wheelSlots.indices.contains(slice) else { return }
        let definition = PingDefinition.definition(for: settings.wheelSlots[slice])
        scene.flashConfirmed(slice)
        sendPing(definition: definition, at: pressPoint, settings: settings)
    }

    private func firePingHub(settings: AppSettings) {
        let definition = PingDefinition.definition(for: settings.clickPing)
        scene.flashConfirmed(nil)
        sendPing(definition: definition, at: pressPoint, settings: settings)
    }

    private func sendPing(definition: PingDefinition, at point: CGPoint, settings: AppSettings) {
        overlay.spawnPing(definition, at: point)
        if settings.isPingSoundEnabled(definition.id) {
            audio.play(definition)
        }
        Log.input.info("Ping \(definition.name, privacy: .public) sent")
    }

    // MARK: - Emote outcomes

    private func fireEmote(slice: Int, settings: AppSettings) {
        guard settings.emoteWheelSlots.indices.contains(slice) else { return }
        emoteScene.flashConfirmed(slice)
        sendEmote(key: settings.emoteWheelSlots[slice], at: emotePressPoint, settings: settings)
    }

    private func fireEmoteHub(settings: AppSettings) {
        emoteScene.flashConfirmed(nil)
        sendEmote(key: settings.emoteClick, at: emotePressPoint, settings: settings)
    }

    private func sendEmote(key: EmoteKey, at point: CGPoint, settings: AppSettings) {
        guard let asset = EmoteLibrary.shared.asset(for: key) else {
            Log.input.warning("Emote \(key.rawValue, privacy: .public) has no files on disk")
            return
        }
        overlay.spawnEmote(asset, at: point)
        if settings.emoteSoundsEnabled {
            audio.playEmote(asset)
        }
        Log.input.info("Emote \(asset.name, privacy: .public) sent")
    }

    // MARK: - Cancel

    private func cancelPingWheel() {
        scene.close()
        overlay.dismissWheel()
    }

    private func cancelEmoteWheel() {
        emoteScene.close()
        overlay.dismissEmoteWheel()
    }

    func toggleEnabled() {
        store.update { $0.isEnabled.toggle() }
        let enabled = store.settings.isEnabled
        if !enabled {
            triggerIsDown = false
            emoteTriggerIsDown = false
            cancelPingWheel()
            cancelEmoteWheel()
        }
        Log.lifecycle.info("Ping wheel \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    /// Sends a ping from the settings window, at the pointer, without touching the wheel.
    func preview(definition: PingDefinition) {
        let settings = store.settings
        let point = CoordinateSpace.cgPoint(fromAppKit: NSEvent.mouseLocation)
        overlay.spawnPing(definition, at: point)
        audio.play(definition)
        _ = settings
    }

    /// Sends an emote from the settings window, at the pointer, without touching the wheel.
    func previewEmote(key: EmoteKey) {
        let point = CoordinateSpace.cgPoint(fromAppKit: NSEvent.mouseLocation)
        sendEmote(key: key, at: point, settings: store.settings)
    }

    /// Called when Accessibility disappears under us: do not leave a half-open wheel on screen.
    func forceClose() {
        triggerIsDown = false
        awaitingDrag = false
        emoteTriggerIsDown = false
        emoteAwaitingDrag = false
        cancelPingWheel()
        cancelEmoteWheel()
    }
}
