import Foundation

/// Names the emote sitting in one wheel slot: one of the shipped set, or something imported.
///
/// It encodes as a bare string, so a settings file written before imports existed still loads —
/// `poro_snax` names a shipped emote, `custom:8E1C…` names one the user dropped in.
struct EmoteKey: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    enum Kind: String, Codable, Hashable, Sendable {
        case shipped
        case custom
    }

    static let customPrefix = "custom:"

    let kind: Kind
    /// A shipped id raw value, or an imported emote's id.
    let token: String

    var id: String { rawValue }
    var rawValue: String { kind == .shipped ? token : Self.customPrefix + token }
    var description: String { rawValue }

    init(kind: Kind, token: String) {
        self.kind = kind
        self.token = token
    }

    var shippedID: EmoteDefinition.ID? {
        kind == .shipped ? EmoteDefinition.ID(rawValue: token) : nil
    }

    var customID: String? { kind == .custom ? token : nil }

    /// nil for anything that is neither a shipped name nor a well-formed import reference, so a
    /// hand-edited settings file cannot smuggle a slot the wheel can never draw.
    init?(rawValue string: String) {
        if string.hasPrefix(Self.customPrefix) {
            let token = String(string.dropFirst(Self.customPrefix.count))
            guard !token.isEmpty else { return nil }
            self.init(kind: .custom, token: token)
        } else if EmoteDefinition.ID(rawValue: string) != nil {
            self.init(kind: .shipped, token: string)
        } else {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let key = EmoteKey(rawValue: string) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Unknown emote \(string)")
        }
        self = key
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension EmoteKey {
    static func shipped(_ id: EmoteDefinition.ID) -> EmoteKey {
        EmoteKey(kind: .shipped, token: id.rawValue)
    }

    static func custom(_ id: String) -> EmoteKey {
        EmoteKey(kind: .custom, token: id)
    }
}

extension EmoteDefinition {
    var key: EmoteKey { .shipped(id) }

    /// Default 8-slot wheel, matching the reference layout.
    static let defaultWheel: [EmoteKey] = [
        .shipped(.unworthy_cn), .shipped(.poro_snax), .shipped(.sad_kitten), .shipped(.cheeky_poro),
        .shipped(.angry_kitty), .shipped(.gg_heart), .shipped(.bee_happy), .shipped(.bee_mad),
    ]
}

extension EmoteDefinition.ID {
    var emoteKey: EmoteKey { .shipped(self) }
}
