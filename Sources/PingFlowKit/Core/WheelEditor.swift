import Foundation

/// Rules for editing the eight wheel slots. Pure, so the editor and its tests share one source.
/// A ping never appears twice: dropping a ping onto a slot that holds another swaps them.
enum WheelEditor {
    enum Slot: Hashable, Sendable {
        case slice(Int)
        /// The centre: the click ping, which lives beside the eight slices rather than in them.
        case hub
    }

    /// Which slice a drop landed on, or nil for the hub.
    static func slotSliceIndex(of slot: Slot) -> Int? {
        if case .slice(let index) = slot { return index }
        return nil
    }

    /// Places `ping` in a slice, moving the occupant to `ping`'s old slice so nothing repeats.
    /// Returns nil when the drop changes nothing (same slice, or the ping is not on the wheel).
    static func assign(_ wheel: [PingDefinition.ID], ping: PingDefinition.ID, to slot: Slot) -> [PingDefinition.ID]? {
        guard let index = slotSliceIndex(of: slot), index >= 0, index < wheel.count else { return nil }
        if wheel[index] == ping { return nil }
        guard let from = wheel.firstIndex(of: ping) else { return nil }
        var next = wheel
        next[from] = wheel[index]
        next[index] = ping
        return next
    }

    /// Drops `ping` on a slice whether or not it is already on the wheel. A ping from the library
    /// simply replaces the occupant; a ping already on the wheel swaps, so the wheel never repeats.
    static func place(_ wheel: [PingDefinition.ID], ping: PingDefinition.ID, at index: Int) -> [PingDefinition.ID]? {
        guard wheel.indices.contains(index), wheel[index] != ping else { return nil }
        var next = wheel
        if let from = next.firstIndex(of: ping) { next[from] = wheel[index] }
        next[index] = ping
        return WheelEditor.normalize(next)
    }

    /// Swaps two slices; nil when the two are the same slot.
    static func swap(_ wheel: [PingDefinition.ID], _ a: Int, _ b: Int) -> [PingDefinition.ID]? {
        guard a != b, a >= 0, b >= 0, a < wheel.count, b < wheel.count else { return nil }
        var next = wheel
        next.swapAt(a, b)
        return next
    }

    /// Every wheel the settings accept: eight slots, no repeats, all known pings.
    static func isValid(_ wheel: [PingDefinition.ID]) -> Bool {
        wheel.count == PingDefinition.wheelSlotCount
            && Set(wheel).count == wheel.count
            && wheel.allSatisfy { PingDefinition.allByID[$0] != nil }
    }

    /// Repairs a stored wheel: keeps the first eight distinct known pings, then fills the
    /// remaining slots from the default arrangement. Anything unusable falls back to the default.
    static func normalize(_ wheel: [PingDefinition.ID]?) -> [PingDefinition.ID] {
        let defaults = PingDefinition.defaultWheel
        guard let wheel, !wheel.isEmpty else { return defaults }
        var out: [PingDefinition.ID] = []
        for id in wheel where PingDefinition.allByID[id] != nil && !out.contains(id) {
            out.append(id)
            if out.count == PingDefinition.wheelSlotCount { break }
        }
        if out.isEmpty { return defaults }
        for id in defaults where out.count < PingDefinition.wheelSlotCount {
            if !out.contains(id) { out.append(id) }
        }
        return out.count == PingDefinition.wheelSlotCount ? out : defaults
    }
}

/// Same rules as WheelEditor, but for the emote wheel.
enum EmoteWheelEditor {
    enum Slot: Hashable, Sendable {
        case slice(Int)
        case hub
    }

    static func slotSliceIndex(of slot: Slot) -> Int? {
        if case .slice(let index) = slot { return index }
        return nil
    }

    static func assign(_ wheel: [EmoteDefinition.ID], emote: EmoteDefinition.ID, to slot: Slot) -> [EmoteDefinition.ID]? {
        guard let index = slotSliceIndex(of: slot), index >= 0, index < wheel.count else { return nil }
        if wheel[index] == emote { return nil }
        guard let from = wheel.firstIndex(of: emote) else { return nil }
        var next = wheel
        next[from] = wheel[index]
        next[index] = emote
        return next
    }

    static func place(_ wheel: [EmoteDefinition.ID], emote: EmoteDefinition.ID, at index: Int) -> [EmoteDefinition.ID]? {
        guard wheel.indices.contains(index), wheel[index] != emote else { return nil }
        var next = wheel
        if let from = next.firstIndex(of: emote) { next[from] = wheel[index] }
        next[index] = emote
        return EmoteWheelEditor.normalize(next)
    }

    static func swap(_ wheel: [EmoteDefinition.ID], _ a: Int, _ b: Int) -> [EmoteDefinition.ID]? {
        guard a != b, a >= 0, b >= 0, a < wheel.count, b < wheel.count else { return nil }
        var next = wheel
        next.swapAt(a, b)
        return next
    }

    static let slotCount = 8

    static func isValid(_ wheel: [EmoteDefinition.ID]) -> Bool {
        wheel.count == Self.slotCount
            && Set(wheel).count == wheel.count
            && wheel.allSatisfy { EmoteDefinition.allByID[$0] != nil }
    }

    static func normalize(_ wheel: [EmoteDefinition.ID]?) -> [EmoteDefinition.ID] {
        let defaults = EmoteDefinition.defaultWheel
        guard let wheel, !wheel.isEmpty else { return defaults }
        var out: [EmoteDefinition.ID] = []
        for id in wheel where EmoteDefinition.allByID[id] != nil && !out.contains(id) {
            out.append(id)
            if out.count == Self.slotCount { break }
        }
        if out.isEmpty { return defaults }
        for id in defaults where out.count < Self.slotCount {
            if !out.contains(id) { out.append(id) }
        }
        return out.count == Self.slotCount ? out : defaults
    }
}
