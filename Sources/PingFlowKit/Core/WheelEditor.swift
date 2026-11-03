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

/// Same rules as WheelEditor, over slots that may hold a shipped emote or an import.
enum EmoteWheelEditor {
    enum Slot: Hashable, Sendable {
        case slice(Int)
        case hub
    }

    static func slotSliceIndex(of slot: Slot) -> Int? {
        if case .slice(let index) = slot { return index }
        return nil
    }

    static func assign(_ wheel: [EmoteKey], emote: EmoteKey, to slot: Slot) -> [EmoteKey]? {
        guard let index = slotSliceIndex(of: slot), index >= 0, index < wheel.count else { return nil }
        if wheel[index] == emote { return nil }
        guard let from = wheel.firstIndex(of: emote) else { return nil }
        var next = wheel
        next[from] = wheel[index]
        next[index] = emote
        return next
    }

    static func place(_ wheel: [EmoteKey], emote: EmoteKey, at index: Int) -> [EmoteKey]? {
        guard wheel.indices.contains(index), wheel[index] != emote else { return nil }
        var next = wheel
        if let from = next.firstIndex(of: emote) { next[from] = wheel[index] }
        next[index] = emote
        return EmoteWheelEditor.normalize(next)
    }

    static func swap(_ wheel: [EmoteKey], _ a: Int, _ b: Int) -> [EmoteKey]? {
        guard a != b, a >= 0, b >= 0, a < wheel.count, b < wheel.count else { return nil }
        var next = wheel
        next.swapAt(a, b)
        return next
    }

    static let slotCount = 8

    static func isValid(_ wheel: [EmoteKey]) -> Bool {
        wheel.count == Self.slotCount && Set(wheel).count == wheel.count
    }

    static func normalize(_ wheel: [EmoteKey]?) -> [EmoteKey] {
        let defaults = EmoteDefinition.defaultWheel
        guard let wheel, !wheel.isEmpty else { return defaults }
        var out: [EmoteKey] = []
        for key in wheel where !out.contains(key) {
            out.append(key)
            if out.count == Self.slotCount { break }
        }
        if out.isEmpty { return defaults }
        for key in defaults where out.count < Self.slotCount {
            if !out.contains(key) { out.append(key) }
        }
        return out.count == Self.slotCount ? out : defaults
    }

    /// Takes one emote off the wheel everywhere it sits, refilling the hole with a shipped emote
    /// that is not already on the wheel — a deleted import must not leave a dead slice.
    static func evict(_ wheel: [EmoteKey], _ key: EmoteKey) -> [EmoteKey] {
        guard wheel.contains(key) else { return wheel }
        var next = wheel
        for index in next.indices where next[index] == key {
            next[index] = firstVacantSlot(on: next)
        }
        return normalize(next)
    }

    private static func firstVacantSlot(on wheel: [EmoteKey]) -> EmoteKey {
        let candidates = EmoteDefinition.defaultWheel + EmoteDefinition.all.map(\.key)
        return candidates.first { !wheel.contains($0) } ?? EmoteDefinition.defaultWheel[0]
    }
}
