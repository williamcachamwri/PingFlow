import SwiftUI
import Combine

/// Where the wheel is in its life. Named for what the user sees, so the view can animate a
/// transition per edge instead of guessing from booleans.
enum WheelPhase: Equatable {
    case hidden
    case opening
    case active
    case closing
}

/// Everything the wheel view draws. The input layer writes it, the view reads it; neither knows
/// about the other, which is what keeps gesture recognition and rendering independent.
@MainActor
final class WheelScene: ObservableObject {
    @Published private(set) var phase: WheelPhase = .hidden
    /// Slice under the pointer, or nil inside the dead zone.
    @Published private(set) var hoveredSlice: Int?
    /// Slot contents, north first, clockwise.
    @Published private(set) var slots: [PingDefinition.ID] = PingDefinition.defaultWheel
    /// Centre text: the hovered ping's name, or the idle label.
    @Published private(set) var centreText: String = "PING"
    @Published private(set) var size: CGFloat = 460
    @Published private(set) var dimUnhoveredIcons = true
    @Published private(set) var showCentreLabel = true
    @Published private(set) var overlayOpacity = 1.0
    @Published private(set) var accentHex = "#c8aa6e"
    /// The texture in the hub — the chosen centre ping, not always the logo.
    @Published private(set) var hubImageName = PingDefinition.logoTexture
    /// Set for one frame after a ping is sent, so the wheel can flash the slice it chose.
    @Published private(set) var confirmedSlice: Int?

    /// Global press point in CoreGraphics space, kept so the input layer can measure the drag.
    private(set) var origin: CGPoint = .zero

    private var lastAppliedSettings: AppSettings?

    var isOpen: Bool { phase == .opening || phase == .active }

    var hoveredDefinition: PingDefinition? {
        guard let hoveredSlice, slots.indices.contains(hoveredSlice) else { return nil }
        return PingDefinition.definition(for: slots[hoveredSlice])
    }

    /// Pulls the numbers the view needs out of the settings. Cheap and idempotent, so the
    /// coordinator can call it on every gesture without touching the store again.
    func sync(settings: AppSettings) {
        guard settings != lastAppliedSettings else { return }
        lastAppliedSettings = settings
        slots = settings.wheelSlots
        size = CGFloat(settings.wheelSize)
        dimUnhoveredIcons = settings.dimUnhoveredIcons
        showCentreLabel = settings.showCentreLabel
        overlayOpacity = settings.overlayOpacity
        accentHex = settings.accentColor.hex
        hubImageName = PingDefinition.definition(for: settings.clickPing).iconTexture
    }

    // MARK: - Transitions written by the input layer

    func open(at point: CGPoint, settings: AppSettings) {
        sync(settings: settings)
        origin = point
        hoveredSlice = nil
        centreText = "PING"
        confirmedSlice = nil
        phase = .opening
        // The view animates 0.85 → 1 over 120 ms; by the next runloop it is live.
        DispatchQueue.main.async { [weak self] in self?.phase = .active }
    }

    /// Returns true when the slice changed, which is when the tick plays.
    @discardableResult
    func setHovered(_ index: Int?) -> Bool {
        guard index != hoveredSlice else { return false }
        hoveredSlice = index
        if let index, slots.indices.contains(index) {
            centreText = PingDefinition.definition(for: slots[index]).name
        } else {
            centreText = "PING"
        }
        return true
    }

    func flashConfirmed(_ index: Int?) {
        confirmedSlice = index
        guard index != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.confirmedSlice = nil
        }
    }

    func close() {
        guard phase != .hidden else { return }
        phase = .closing
        hoveredSlice = nil
        centreText = "PING"
    }

    func markHidden() {
        phase = .hidden
        hoveredSlice = nil
        confirmedSlice = nil
    }
}

/// The pings currently animating on screen. Separate from the wheel so an animation can outlive
/// the gesture that made it, and several can overlap.
@MainActor
final class PingStage: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let definition: PingDefinition
        /// Position in the panel's SwiftUI space (y down from the top of the display).
        let position: CGPoint
        let size: CGFloat
        let duration: Double
        let intensity: Double
        let accentHex: String
        let startedAt = Date()
    }

    /// Safety ceiling: past this many pings on screen the oldest go early, so a flood cannot
    /// bog the overlay down. Same idea as the reference's `MAX_PINGS`.
    static let maximumSimultaneous = 60

    @Published private(set) var items: [Item] = []

    var isEmpty: Bool { items.isEmpty }

    @discardableResult
    func spawn(definition: PingDefinition, at position: CGPoint, settings: AppSettings) -> Item {
        let item = Item(definition: definition,
                        position: position,
                        size: CGFloat(settings.pingSize),
                        duration: settings.pingDuration,
                        intensity: settings.animationIntensity,
                        accentHex: settings.accentColor.hex)
        items.append(item)
        while items.count > Self.maximumSimultaneous { items.removeFirst() }
        // A ping flood trimming the queue still has to clear the survivors.
        scheduleRemoval(of: item.id, after: settings.pingDuration + 0.2)
        return item
    }

    func remove(_ id: PingStage.Item.ID) {
        items.removeAll { $0.id == id }
    }

    func clear() { items.removeAll() }

    private func scheduleRemoval(of id: PingStage.Item.ID, after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }
}
