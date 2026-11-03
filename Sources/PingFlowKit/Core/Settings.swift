import Foundation
import SwiftUI
import Combine

enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "Follow macOS"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentColorChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case league      // the wheel's own gold/teal identity, no tinting
    case blue, purple, pink, green, yellow, graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .league: return "League"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .graphite: return "Graphite"
        }
    }

    /// Hex for the swatch. `league` uses the wheel's own gold.
    var hex: String {
        switch self {
        case .league: return "#c8aa6e"
        case .blue: return "#3b82f6"
        case .purple: return "#8b5cf6"
        case .pink: return "#ec4899"
        case .green: return "#22c55e"
        case .yellow: return "#eab308"
        case .graphite: return "#71717a"
        }
    }
}

/// What a left click does while the wheel is open.
enum ClickBehaviour: String, Codable, CaseIterable, Identifiable, Sendable {
    case cancel
    case confirm
    case ignore

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .cancel: return "Cancels the wheel"
        case .confirm: return "Sends the ping"
        case .ignore: return "Passes through"
        }
    }
}

struct AppSettings: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion

    // General
    var isEnabled = true
    var showMenuBarIcon = true
    var showDockIconWhileSettingsOpen = true

    // Interaction
    var activationKey: ActivationModifier = .option
    var secondaryActivationKey: ActivationModifier?
    var toggleShortcut: KeyCombo? = .controlOptionP
    var dragThreshold: Double = 8
    var clickBehaviour: ClickBehaviour = .cancel
    var cancelOnRightClick = true
    var cancelOnOtherKeyPress = true

    // Ping wheel
    var wheelSize: Double = 460
    var wheelSlots: [PingDefinition.ID] = PingDefinition.defaultWheel
    var clickPing: PingDefinition.ID = .generic
    var showCentreLabel = true
    var dimUnhoveredIcons = true

    // Sounds
    var volume: Double = 0.7
    var isMuted = false
    var pingSoundsEnabled = true
    var tickSoundEnabled = true
    var tickVolume: Double = 0.5
    var disabledPingSounds: [PingDefinition.ID] = []

    // Emote wheel
    var emoteEnabled = true
    var emoteTrigger: ActivationModifier = .control
    var emoteWheelSlots: [EmoteKey] = EmoteDefinition.defaultWheel
    var emoteClick: EmoteKey = .shipped(.cheeky_poro)
    var emoteSoundsEnabled = true

    // Appearance
    var appearanceMode: AppearanceMode = .system
    var accentColor: AccentColorChoice = .blue
    var pingSize: Double = 110
    var pingDuration: Double = 3.2
    var animationIntensity: Double = 1
    var overlayOpacity: Double = 1

    /// Repairs anything unreadable, so a stale or hand-edited file can never hand the engine
    /// a wheel with two slices on one ping or a slider outside its range.
    func normalized() -> AppSettings {
        var s = self
        s.version = AppSettings.currentVersion
        s.wheelSlots = WheelEditor.normalize(s.wheelSlots)
        s.emoteWheelSlots = EmoteWheelEditor.normalize(s.emoteWheelSlots)
        s.dragThreshold = min(max(s.dragThreshold, 2), 40)
        s.wheelSize = min(max(s.wheelSize, 300), 900)
        s.pingSize = min(max(s.pingSize, 60), 220)
        s.pingDuration = min(max(s.pingDuration, 1), 8)
        s.animationIntensity = min(max(s.animationIntensity, 0), 1.5)
        s.overlayOpacity = min(max(s.overlayOpacity, 0.35), 1)
        s.volume = min(max(s.volume, 0), 1)
        s.tickVolume = min(max(s.tickVolume, 0), 1)
        if let combo = s.toggleShortcut, !combo.isValidGlobalShortcut { s.toggleShortcut = .controlOptionP }
        if s.secondaryActivationKey == s.activationKey { s.secondaryActivationKey = nil }
        // Every known ping keeps its sound choice, whether or not it is on the wheel right now —
        // otherwise moving a slice would quietly erase settings for the pings it no longer holds.
        s.disabledPingSounds = s.disabledPingSounds.filter { PingDefinition.allByID[$0] != nil }
        return s
    }

    func isPingSoundEnabled(_ id: PingDefinition.ID) -> Bool {
        pingSoundsEnabled && !disabledPingSounds.contains(id)
    }

    /// Missing or wrong-typed keys fall back to the default rather than throwing, so one bad
    /// field never costs the user the whole file.
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            let present: T? = (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
            return present ?? fallback
        }
        version = value(.version, AppSettings.currentVersion)
        isEnabled = value(.isEnabled, true)
        showMenuBarIcon = value(.showMenuBarIcon, true)
        showDockIconWhileSettingsOpen = value(.showDockIconWhileSettingsOpen, true)
        activationKey = value(.activationKey, .option)
        secondaryActivationKey = (try? container.decodeIfPresent(ActivationModifier.self, forKey: .secondaryActivationKey)) ?? nil
        toggleShortcut = (try? container.decodeIfPresent(KeyCombo.self, forKey: .toggleShortcut)) ?? nil
        dragThreshold = value(.dragThreshold, 8)
        clickBehaviour = value(.clickBehaviour, .cancel)
        cancelOnRightClick = value(.cancelOnRightClick, true)
        cancelOnOtherKeyPress = value(.cancelOnOtherKeyPress, true)
        wheelSize = value(.wheelSize, 460)
        wheelSlots = value(.wheelSlots, PingDefinition.defaultWheel)
        clickPing = value(.clickPing, .generic)
        showCentreLabel = value(.showCentreLabel, true)
        dimUnhoveredIcons = value(.dimUnhoveredIcons, true)
        volume = value(.volume, 0.7)
        isMuted = value(.isMuted, false)
        pingSoundsEnabled = value(.pingSoundsEnabled, true)
        tickSoundEnabled = value(.tickSoundEnabled, true)
        tickVolume = value(.tickVolume, 0.5)
        disabledPingSounds = value(.disabledPingSounds, [])
        emoteEnabled = value(.emoteEnabled, true)
        emoteTrigger = value(.emoteTrigger, .control)
        emoteWheelSlots = value(.emoteWheelSlots, EmoteDefinition.defaultWheel)
        emoteClick = value(.emoteClick, .shipped(.cheeky_poro))
        emoteSoundsEnabled = value(.emoteSoundsEnabled, true)
        appearanceMode = value(.appearanceMode, .system)
        accentColor = value(.accentColor, .blue)
        pingSize = value(.pingSize, 110)
        pingDuration = value(.pingDuration, 3.2)
        animationIntensity = value(.animationIntensity, 1)
        overlayOpacity = value(.overlayOpacity, 1)
    }
}

/// Owns the settings file. Loads once, saves debounced and atomically, publishes every change.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var settings: AppSettings
    /// Set when the file could not be read or written, so the About pane can say so out loud.
    @Published private(set) var fileIssue: String?

    private let url: URL
    private var saveTask: Task<Void, Never>?

    init(filename: String = "settings.json") {
        url = AppPaths.supportDirectory.appendingPathComponent(filename)
        settings = AppSettings()
        load()
    }

    /// Test entry point: an isolated store that never touches the user's file.
    init(in directory: URL, filename: String = "settings-test.json") {
        url = directory.appendingPathComponent(filename)
        settings = AppSettings()
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            settings = try JSONDecoder().decode(AppSettings.self, from: data).normalized()
            fileIssue = nil
        } catch {
            fileIssue = "Settings could not be read (\(error.localizedDescription)). Defaults are in use."
            settings = AppSettings()
        }
    }

    /// The only mutation entry point. Everything downstream observes `settings`.
    func update(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        next = next.normalized()
        guard next != settings else { return }
        settings = next
        scheduleSave()
    }

    /// Applies a change and writes it immediately — for controls whose value must survive a quit.
    func commit(_ mutate: (inout AppSettings) -> Void) {
        update(mutate)
        flushSave()
    }

    func resetToDefaults() {
        settings = AppSettings()
        flushSave()
    }

    func reload() { load() }

    var fileURL: URL { url }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.write()
        }
    }

    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            // Atomic: write a temp file, then rename, so a crash mid-write cannot eat the settings.
            try data.write(to: url, options: [.atomic])
            fileIssue = nil
        } catch {
            fileIssue = "Settings could not be saved (\(error.localizedDescription))."
        }
    }
}

enum AppPaths {
    /// `PINGFLOW_SUPPORT_DIR` puts the whole writable area somewhere else, which is how the tests
    /// and the render harness stay off the user's real library and settings.
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["PINGFLOW_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PingFlow", isDirectory: true)
    }

    static var logsDirectory: URL { supportDirectory.appendingPathComponent("Logs", isDirectory: true) }

    /// Imports live here, one folder per emote, so deleting one cannot touch another's files.
    static var emoteLibraryDirectory: URL { supportDirectory.appendingPathComponent("Emotes", isDirectory: true) }
}
