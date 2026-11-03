import AppKit
import SwiftUI
import Combine

/// The pages the sidebar offers, in the order it shows them.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case interaction
    case pingWheel
    case emoteWheel
    case sounds
    case appearance
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .interaction: return "Interaction"
        case .pingWheel: return "Ping Wheel"
        case .emoteWheel: return "Emote Wheel"
        case .sounds: return "Sounds"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "How PingFlow lives on this Mac."
        case .interaction: return "The keys that open the wheel and the gestures that drive it."
        case .pingWheel: return "Arrange the eight slices, exactly the way you want them."
        case .emoteWheel: return "Pick eight emotes and the key that opens the wheel."
        case .sounds: return "Volume, the hover tick, and which pings make a noise."
        case .appearance: return "Sizes, timing and the wheel's own colour."
        case .permissions: return "Accessibility is the one permission the wheel cannot work without."
        case .about: return "Version, build and what the wheel found on disk."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .interaction: return "command"
        case .pingWheel: return "circle.hexagongrid"
        case .emoteWheel: return "face.smiling"
        case .sounds: return "speaker.wave.2"
        case .appearance: return "paintpalette"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .general: GeneralPane()
        case .interaction: InteractionPane()
        case .pingWheel: PingWheelPane()
        case .emoteWheel: EmoteWheelPane()
        case .sounds: SoundsPane()
        case .appearance: AppearancePane()
        case .permissions: PermissionsPane()
        case .about: AboutPane()
        }
    }
}

/// Where the content column is pointing. A page, or one ping's own detail — the reference's
/// "click a category, land inside it" behaviour.
enum Destination: Hashable, Identifiable {
    case pane(SettingsPane)
    case ping(PingDefinition.ID)

    var id: String {
        switch self {
        case .pane(let pane): return "pane-\(pane.rawValue)"
        case .ping(let ping): return "ping-\(ping.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .pane(let pane): return pane.title
        case .ping(let ping): return PingDefinition.definition(for: ping).name
        }
    }

    var subtitle: String {
        switch self {
        case .pane(let pane): return pane.subtitle
        case .ping(let ping): return PingDefinition.definition(for: ping).usage
        }
    }
}

/// What the list is showing: everything, or one group of pings.
enum Scope: Hashable, Identifiable {
    case all
    case category(PingCategory)

    /// Written out, because a case with a payload is not `CaseIterable`.
    static let allCases: [Scope] = [.all] + PingCategory.allCases.map { .category($0) }

    var id: String {
        switch self {
        case .all: return "all"
        case .category(let category): return category.rawValue
        }
    }

    var label: String {
        switch self {
        case .all: return "All categories"
        case .category(let category): return category.displayName
        }
    }

    func contains(_ ping: PingDefinition) -> Bool {
        switch self {
        case .all: return true
        case .category(let category): return ping.category == category
        }
    }

    /// A hit belongs to a category only when it names a ping; every other setting stays visible
    /// whatever the list is filtered to.
    func contains(_ hit: SettingsCatalog.Hit) -> Bool {
        switch self {
        case .all: return true
        case .category: return hit.ping.map { contains(PingDefinition.definition(for: $0)) } ?? false
        }
    }
}

/// Hands a page to the window that is already open — the menu bar's "About PingFlow" and the
/// first-run jump to Permissions both come through here — and keeps the back/forward list the
/// content column's toolbar drives.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    @Published private(set) var destination: Destination = .pane(.general)
    @Published var query: String = ""
    @Published var scope: Scope = .all
    /// Set by a search result: the row with this id gets a ring for a moment.
    @Published var highlight: String?

    private var history: [Destination] = [.pane(.general)]
    private var cursor = 0

    /// Not private: the history and the scope are worth testing, and a window-sized singleton makes
    /// that impossible. `shared` is still the only instance the app uses.
    init() {}

    var canGoBack: Bool { cursor > 0 }
    var canGoForward: Bool { cursor < history.count - 1 }

    func go(_ next: Destination) {
        guard next != destination else { return }
        if history.indices.contains(cursor + 1) { history.removeSubrange((cursor + 1)...) }
        history.append(next)
        cursor = history.count - 1
        query = ""
        destination = next
    }

    func back() {
        guard canGoBack else { return }
        cursor -= 1
        destination = history[cursor]
    }

    func forward() {
        guard canGoForward else { return }
        cursor += 1
        destination = history[cursor]
    }

    /// Used by the menu bar and by the render harness: show this page, whether or not the window
    /// was already open.
    func open(_ pane: SettingsPane) { go(.pane(pane)) }

    /// A pane the sidebar should mark chosen even when the content is inside a ping.
    var owningPane: SettingsPane {
        switch destination {
        case .pane(let pane): return pane
        case .ping: return .pingWheel
        }
    }
}

/// Everything the search field can find, in one flat table. A row that is not in here cannot be
/// jumped to, so adding a setting means adding its entry — which is the honest way to keep the
/// index from promising things the window does not have.
enum SettingsCatalog {
    struct Hit: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let keywords: String
        let destination: Destination
        let ping: PingDefinition.ID?
    }

    /// The reference's own placeholder is "Search by name or alias", so every entry carries the
    /// words a player would actually type, not just its label.
    static let hits: [Hit] = {
        var out: [Hit] = [
            Hit(id: "isEnabled", title: "Enable PingFlow", subtitle: "Turn the whole wheel on or off",
                keywords: "on off disable enable pause active", destination: .pane(.general), ping: nil),
            Hit(id: "launchAtLogin", title: "Launch at login", subtitle: "Start PingFlow when the Mac signs in",
                keywords: "startup boot login item sign in", destination: .pane(.general), ping: nil),
            Hit(id: "showMenuBarIcon", title: "Menu bar icon", subtitle: "Keep the wheel in the menu bar",
                keywords: "status item menu bar icon tray", destination: .pane(.general), ping: nil),
            Hit(id: "showDockIconWhileSettingsOpen", title: "Dock icon while settings open",
                subtitle: "Show PingFlow in the Dock with the window up",
                keywords: "dock icon window", destination: .pane(.general), ping: nil),
            Hit(id: "reset", title: "Reset to defaults", subtitle: "Put every setting back",
                keywords: "reset default restore factory", destination: .pane(.general), ping: nil),

            Hit(id: "activationKey", title: "Activation key", subtitle: "The modifier that opens the wheel",
                keywords: "option alt control shift command modifier hold key", destination: .pane(.interaction), ping: nil),
            Hit(id: "secondaryActivationKey", title: "Second activation key",
                subtitle: "An alternative modifier", keywords: "alt modifier second also",
                destination: .pane(.interaction), ping: nil),
            Hit(id: "dragThreshold", title: "Drag threshold", subtitle: "How far the pointer moves first",
                keywords: "distance sensitivity threshold drag", destination: .pane(.interaction), ping: nil),
            Hit(id: "toggleShortcut", title: "Toggle shortcut", subtitle: "Turn the engine on and off from the keyboard",
                keywords: "hotkey key binding shortcut global", destination: .pane(.interaction), ping: nil),
            Hit(id: "clickBehaviour", title: "Left click", subtitle: "What a click does while the wheel is open",
                keywords: "click mouse confirm cancel", destination: .pane(.interaction), ping: nil),
            Hit(id: "cancelOnRightClick", title: "Right click cancels", subtitle: "Escape hatch for the wheel",
                keywords: "right click cancel abort", destination: .pane(.interaction), ping: nil),
            Hit(id: "cancelOnOtherKeyPress", title: "Other keys cancel", subtitle: "Shortcuts win over the wheel",
                keywords: "key press cancel abort shortcut", destination: .pane(.interaction), ping: nil),

            Hit(id: "wheelSize", title: "Wheel size", subtitle: "Diameter on the display it opens on",
                keywords: "size scale big small diameter", destination: .pane(.appearance), ping: nil),
            Hit(id: "accentColor", title: "Wheel colour", subtitle: "The tint the wheel and its slices draw in",
                keywords: "colour color accent tint league gold blue green pink purple",
                destination: .pane(.appearance), ping: nil),
            Hit(id: "wheelSlots", title: "Wheel slices", subtitle: "Which ping sits in which direction",
                keywords: "slots arrange order compass north east south west", destination: .pane(.pingWheel), ping: nil),
            Hit(id: "clickPing", title: "Centre ping", subtitle: "The mark in the hub of the wheel",
                keywords: "hub centre generic click", destination: .pane(.pingWheel), ping: nil),

            Hit(id: "emoteEnabled", title: "Emote wheel", subtitle: "Turn the emote wheel on or off",
                keywords: "emote wheel enable disable", destination: .pane(.emoteWheel), ping: nil),
            Hit(id: "emoteWheelSlots", title: "Emote slices", subtitle: "Which emote sits in which direction",
                keywords: "emote slots arrange order", destination: .pane(.emoteWheel), ping: nil),
            Hit(id: "emoteTrigger", title: "Emote trigger", subtitle: "The key that opens the emote wheel",
                keywords: "emote trigger key ctrl control modifier", destination: .pane(.emoteWheel), ping: nil),
            Hit(id: "emoteSoundsEnabled", title: "Emote sounds", subtitle: "Play sounds when emotes fire",
                keywords: "emote sound audio", destination: .pane(.emoteWheel), ping: nil),
            Hit(id: "emoteClick", title: "Centre emote", subtitle: "The emote in the hub of the wheel",
                keywords: "emote hub centre click", destination: .pane(.emoteWheel), ping: nil),
            Hit(id: "emoteLibrary", title: "Emote library", subtitle: "Drop a gif, an image or a clip to make one",
                keywords: "import drop custom own gif video image png sound audio mp3 wav m4a voice rename delete library",
                destination: .pane(.emoteWheel), ping: nil),
            Hit(id: "dimUnhoveredIcons", title: "Dim unhovered icons", subtitle: "The slice you pick lights up",
                keywords: "dim highlight icon hover", destination: .pane(.pingWheel), ping: nil),
            Hit(id: "showCentreLabel", title: "Centre label", subtitle: "The ping's name in the hub",
                keywords: "label text name centre", destination: .pane(.pingWheel), ping: nil),

            Hit(id: "volume", title: "Ping volume", subtitle: "How loud the callouts are",
                keywords: "volume loud quiet audio sound level", destination: .pane(.sounds), ping: nil),
            Hit(id: "isMuted", title: "Mute", subtitle: "Silence every sound, keep the wheel",
                keywords: "mute silent off audio", destination: .pane(.sounds), ping: nil),
            Hit(id: "pingSoundsEnabled", title: "Ping sounds", subtitle: "Play the game's callout when a ping lands",
                keywords: "sound callout play audio", destination: .pane(.sounds), ping: nil),
            Hit(id: "tickSoundEnabled", title: "Hover tick", subtitle: "The click when the pointer crosses a slice",
                keywords: "tick hover click button sound", destination: .pane(.sounds), ping: nil),
            Hit(id: "tickVolume", title: "Tick volume", subtitle: "How loud the hover click is",
                keywords: "tick volume hover button", destination: .pane(.sounds), ping: nil),

            Hit(id: "pingSize", title: "Ping size", subtitle: "The mark left on screen",
                keywords: "size scale big small mark", destination: .pane(.appearance), ping: nil),
            Hit(id: "pingDuration", title: "Ping lifetime", subtitle: "How long a ping stays on screen",
                keywords: "duration time long fade", destination: .pane(.appearance), ping: nil),
            Hit(id: "animationIntensity", title: "Animation intensity", subtitle: "Rings, overshoot and bob",
                keywords: "intensity animation motion rings pop", destination: .pane(.appearance), ping: nil),
            Hit(id: "overlayOpacity", title: "Wheel opacity", subtitle: "How solid the overlay draws",
                keywords: "opacity transparent see through fade", destination: .pane(.appearance), ping: nil),
            Hit(id: "previewPing", title: "Preview ping", subtitle: "Which ping plays in the preview",
                keywords: "preview test animation", destination: .pane(.appearance), ping: nil),
            Hit(id: "preview", title: "Animation preview", subtitle: "See the ping animation",
                keywords: "preview animation test play", destination: .pane(.appearance), ping: nil),

            Hit(id: "permissions", title: "Accessibility permission", subtitle: "The one the wheel needs to read keys",
                keywords: "permission access accessibility input monitoring grant", destination: .pane(.permissions), ping: nil),
            Hit(id: "about", title: "About and assets", subtitle: "Version, build and the asset inventory",
                keywords: "version build inventory assets missing emotes pings sounds", destination: .pane(.about), ping: nil),
        ]
        for definition in PingDefinition.all {
            out.append(Hit(id: "ping-\(definition.id.rawValue)", title: definition.name,
                           subtitle: definition.usage,
                           keywords: "\(definition.name) \(definition.usage) \(definition.id.rawValue)",
                           destination: .ping(definition.id), ping: definition.id))
        }
        return out
    }()

    static func results(query: String, scope: Scope) -> [Hit] {
        hits.filter { scope.contains($0) && matchesLocally($0, query: query) }
    }

    private static func matchesLocally(_ hit: Hit, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        let hay = "\(hit.title) \(hit.subtitle) \(hit.keywords)".lowercased()
        return needle.split(separator: " ").allSatisfy { hay.contains($0) }
    }
}
