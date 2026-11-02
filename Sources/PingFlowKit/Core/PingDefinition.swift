import Foundation

/// A ping the wheel can hold. Names, textures and sounds follow the reference asset layout
/// (`assets/textures`, `assets/sounds`) so the extracted files drop in without renaming.
struct PingDefinition: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier. Persisted in settings — never renumber, only append.
    enum ID: String, Codable, Hashable, CaseIterable, Sendable {
        case danger
        case push
        case onMyWay = "omw"
        case allIn = "allin"
        case assist
        case needVision = "needvision"
        case enemyMissing = "missing"
        case enemyVision = "enemyvision"
        case generic
        case bait
        case visionCleared = "visioncleared"
        case upsideDownMissing = "missingflip"
    }

    let id: ID
    let name: String
    /// Texture drawn on the wheel slice (a file in `Assets/textures`, without the extension).
    let iconTexture: String
    /// Textures drawn at the pinged spot. Two entries = All In's clashing halves.
    let artTextures: [String]
    /// A file in `Assets/sounds`, without the extension.
    let sound: String
    /// Ring, ground and glow colour.
    let colorHex: String
    /// One-line description, shown in the editor's inspector.
    let usage: String
    /// What the call is for, which is how the settings list groups and filters them.
    let category: PingCategory
}

/// The four kinds of call the wheel carries. Named for what a player is doing, not for the
/// game's internal signal table.
enum PingCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case engage
    case defend
    case vision
    case map

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .engage: return "Engage"
        case .defend: return "Defend"
        case .vision: return "Vision"
        case .map: return "Map info"
        }
    }
}

extension PingDefinition {
    /// Every ping, in the order the Sounds page lists them: the default wheel first, then the extras.
    static let all: [PingDefinition] = [
        .init(id: .danger, name: "Danger", iconTexture: "pingwheel_retreatrender",
              artTextures: ["pingwheel_retreatrender"], sound: "SRP_12", colorHex: "#ff3b55",
              usage: "Danger — retreat, an engage is coming.", category: .defend),
        .init(id: .push, name: "Push", iconTexture: "pingwheel_pushrender",
              artTextures: ["pingwheel_pushrender"], sound: "SRP_9", colorHex: "#35d27a",
              usage: "Push this lane now, with numbers.", category: .engage),
        .init(id: .onMyWay, name: "On My Way", iconTexture: "omw_cyan",
              artTextures: ["omw_cyan"], sound: "OnMyWay", colorHex: "#2e8bff",
              usage: "Heading there. League's upright icon is the colourblind-blue one.", category: .map),
        .init(id: .allIn, name: "All In", iconTexture: "png_all_in",
              artTextures: ["pingwheel_allin_render_01", "pingwheel_allin_render_02"],
              sound: "SRP_4", colorHex: "#f2b320",
              usage: "Fight now — two halves clash, then a flash.", category: .engage),
        .init(id: .assist, name: "Assist Me", iconTexture: "png_assist_me_128x128",
              artTextures: ["png_assist_me_128x128"], sound: "ComeHere", colorHex: "#35d27a",
              usage: "Come here and help.", category: .defend),
        .init(id: .needVision, name: "Need Vision", iconTexture: "mt11_18_vision",
              artTextures: ["mt11_18_vision"], sound: "SRP_7", colorHex: "#35d27a",
              usage: "Ward this spot.", category: .vision),
        .init(id: .enemyMissing, name: "Enemy Missing", iconTexture: "png_enemymissing_128x128",
              artTextures: ["png_enemymissing_128x128"], sound: "MIA", colorHex: "#f2c518",
              usage: "They are gone from lane.", category: .map),
        .init(id: .enemyVision, name: "Enemy Vision", iconTexture: "pingwheel_enemyvisionrender",
              artTextures: ["pingwheel_enemyvisionrender"], sound: "AreaIsWarded", colorHex: "#ff3b55",
              usage: "A ward sits here.", category: .vision),
        .init(id: .generic, name: "Generic", iconTexture: "pingwheel_basicpingrender",
              artTextures: ["pingwheel_basicpingrender"], sound: "Base", colorHex: "#2e8bff",
              usage: "A plain ping: look at this spot.", category: .map),
        .init(id: .bait, name: "Bait", iconTexture: "pingwheel_baitrender",
              artTextures: ["pingwheel_baitrender"], sound: "SRP_11", colorHex: "#efbc12",
              usage: "Bait the engage from here.", category: .engage),
        .init(id: .visionCleared, name: "Vision Cleared", iconTexture: "pingwheel_visionclearedrender",
              artTextures: ["pingwheel_visionclearedrender"], sound: "SRP_6", colorHex: "#2b80ff",
              usage: "The ward here is down.", category: .vision),
        .init(id: .upsideDownMissing, name: "Upside-down Missing", iconTexture: "enemy_missing_flipped",
              artTextures: ["enemy_missing_flipped"], sound: "MIA", colorHex: "#f2c518",
              usage: "Enemy Missing turned 180° — the ¿ ping. Derived, not a game file.", category: .map),
    ]

    static let allByID: [ID: PingDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func definition(for id: ID) -> PingDefinition { allByID[id] ?? all[0] }

    /// The wheel as League ships it: top (north), then clockwise.
    static let defaultWheel: [ID] = [
        .danger, .push, .onMyWay, .allIn, .assist, .needVision, .enemyMissing, .enemyVision,
    ]

    static let wheelSlotCount = 8
    /// `button.wav` — the tick played when the pointer crosses into a new slice.
    static let tickSound = "button"
    /// Drawn when a real texture is missing, and used for the app icon.
    static let fallbackTexture = "pingwheel_basicpingrender"
    static let logoTexture = "generic_ping"

    var isAllIn: Bool { artTextures.count == 2 }
}
