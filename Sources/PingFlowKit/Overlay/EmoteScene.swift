import SwiftUI
import Combine

/// The emote wheel's own scene: same lifecycle as the ping wheel, but carrying emote slots and
/// drawing circular-clipped icons instead of tinted ones.
@MainActor
final class EmoteScene: ObservableObject {
    @Published private(set) var phase: WheelPhase = .hidden
    @Published private(set) var hoveredSlice: Int?
    @Published private(set) var slots: [EmoteDefinition.ID] = EmoteDefinition.defaultWheel
    @Published private(set) var centreText: String = "EMOTE"
    @Published private(set) var size: CGFloat = 460
    @Published private(set) var overlayOpacity = 1.0
    @Published private(set) var confirmedSlice: Int?

    private(set) var origin: CGPoint = .zero
    private var lastAppliedSettings: AppSettings?

    var isOpen: Bool { phase == .opening || phase == .active }

    var hoveredDefinition: EmoteDefinition? {
        guard let hoveredSlice, slots.indices.contains(hoveredSlice) else { return nil }
        return EmoteDefinition.definition(for: slots[hoveredSlice])
    }

    func sync(settings: AppSettings) {
        guard settings != lastAppliedSettings else { return }
        lastAppliedSettings = settings
        slots = settings.emoteWheelSlots
        size = CGFloat(settings.wheelSize)
        overlayOpacity = settings.overlayOpacity
    }

    func open(at point: CGPoint, settings: AppSettings) {
        sync(settings: settings)
        origin = point
        hoveredSlice = nil
        centreText = "EMOTE"
        confirmedSlice = nil
        phase = .opening
        DispatchQueue.main.async { [weak self] in self?.phase = .active }
    }

    @discardableResult
    func setHovered(_ index: Int?) -> Bool {
        guard index != hoveredSlice else { return false }
        hoveredSlice = index
        if let index, slots.indices.contains(index) {
            centreText = EmoteDefinition.definition(for: slots[index]).name
        } else {
            centreText = "EMOTE"
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
        centreText = "EMOTE"
    }

    func markHidden() {
        phase = .hidden
        hoveredSlice = nil
        confirmedSlice = nil
    }
}

/// An emote showing on screen after the wheel fires it. Lives for a few seconds, then auto-removes.
@MainActor
final class EmoteStage: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let definition: EmoteDefinition
        let position: CGPoint
        let size: CGFloat
        let startedAt = Date()
    }

    static let maximumSimultaneous = 30
    static let displayDuration: Double = 3.0

    @Published private(set) var items: [Item] = []

    var isEmpty: Bool { items.isEmpty }

    @discardableResult
    func spawn(definition: EmoteDefinition, at position: CGPoint, settings: AppSettings) -> Item {
        let item = Item(definition: definition,
                        position: position,
                        size: CGFloat(settings.pingSize))
        items.append(item)
        while items.count > Self.maximumSimultaneous { items.removeFirst() }
        scheduleRemoval(of: item.id, after: Self.displayDuration + 0.2)
        return item
    }

    func remove(_ id: Item.ID) {
        items.removeAll { $0.id == id }
    }

    func clear() { items.removeAll() }

    private func scheduleRemoval(of id: Item.ID, after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }
}
