import Foundation
import AppKit

/// A modifier that can open the wheel on its own. Caps Lock is deliberately absent: macOS
/// cannot reliably suppress its LED and case toggle, so the reference excludes it too.
enum ActivationModifier: String, Codable, CaseIterable, Identifiable, Sendable {
    case option
    case control
    case shift
    case command

    var id: String { rawValue }

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        case .command: return .command
        }
    }

    /// `CGEventFlags` bit for the same key, used by the event tap.
    var cgFlag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        case .command: return .maskCommand
        }
    }

    var glyph: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }

    var displayName: String {
        switch self {
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        case .command: return "Command"
        }
    }

    /// Keycodes the tap reports for these keys, left and right.
    static let keyCodes: [Int: ActivationModifier] = [
        58: .option, 61: .option,      // left / right Option
        59: .control, 62: .control,    // left / right Control
        56: .shift, 60: .shift,        // left / right Shift
        54: .command, 55: .command,    // left / right Command
    ]
}

/// A recorded key combination: one key plus any of ⌃⌥⇧⌘.
struct KeyCombo: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: ModifierSet

    init(keyCode: UInt16, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    static let controlOptionP = KeyCombo(keyCode: UInt16(KeyboardKey.p), modifiers: .init(control: true, option: true))

    var keyName: String { KeyboardKey.name(for: Int(keyCode)) }

    /// `⌃⌥P`, the way macOS writes a shortcut.
    var displayString: String { modifiers.glyphs + keyName }

    /// One keycap per part, for the keycap row in the settings.
    var keycaps: [String] {
        var caps: [String] = []
        if modifiers.containsControl { caps.append("⌃") }
        if modifiers.containsOption { caps.append("⌥") }
        if modifiers.containsShift { caps.append("⇧") }
        if modifiers.containsCommand { caps.append("⌘") }
        caps.append(keyName)
        return caps
    }

    /// A global shortcut needs a modifier: a bare letter would swallow every keystroke.
    var isValidGlobalShortcut: Bool {
        !modifiers.isEmpty
            && !KeyboardKey.isModifierKey(Int(keyCode))
            && !KeyboardKey.isBlockedShortcutKey(Int(keyCode))
    }

    /// True when the same physical combination is held, ignoring which side of the keyboard it came from.
    func matches(_ other: KeyCombo) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// Matches a raw tap event. The tap reports device-dependent flag bits, so left and right
    /// modifiers are compared as one.
    func matches(eventFlags flags: CGEventFlags, keyCode: UInt16) -> Bool {
        guard self.keyCode == keyCode else { return false }
        let control = flags.contains(.maskControl)
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)
        return modifiers.containsControl == control
            && modifiers.containsOption == option
            && modifiers.containsShift == shift
            && modifiers.containsCommand == command
    }
}

/// The four hardware modifiers, Codable without a raw-value dance so the JSON stays readable.
struct ModifierSet: Codable, Hashable, Sendable {
    var containsControl = false
    var containsOption = false
    var containsShift = false
    var containsCommand = false

    static let none = ModifierSet(control: false, option: false, shift: false, command: false)

    init(control: Bool = false, option: Bool = false, shift: Bool = false, command: Bool = false) {
        containsControl = control
        containsOption = option
        containsShift = shift
        containsCommand = command
    }

    init(_ flags: NSEvent.ModifierFlags) {
        containsControl = flags.contains(.control)
        containsOption = flags.contains(.option)
        containsShift = flags.contains(.shift)
        containsCommand = flags.contains(.command)
    }

    /// A hand-edited file that names only the keys it holds — `{"containsOption": true}` — must
    /// still read as Option, not fail the whole shortcut. Synthesised decoding would demand all
    /// four keys, so they are read one at a time with `false` for anything absent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        containsControl = (try? container.decodeIfPresent(Bool.self, forKey: .containsControl)) ?? false
        containsOption = (try? container.decodeIfPresent(Bool.self, forKey: .containsOption)) ?? false
        containsShift = (try? container.decodeIfPresent(Bool.self, forKey: .containsShift)) ?? false
        containsCommand = (try? container.decodeIfPresent(Bool.self, forKey: .containsCommand)) ?? false
    }

    var glyphs: String {
        var out = ""
        if containsControl { out += "⌃" }
        if containsOption { out += "⌥" }
        if containsShift { out += "⇧" }
        if containsCommand { out += "⌘" }
        return out
    }

    var isEmpty: Bool { !containsControl && !containsOption && !containsShift && !containsCommand }

    var nsFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if containsControl { flags.insert(.control) }
        if containsOption { flags.insert(.option) }
        if containsShift { flags.insert(.shift) }
        if containsCommand { flags.insert(.command) }
        return flags
    }
}

/// macOS virtual key codes and their display names, from `HIServices/Events.h`.
/// Only what the recorder can produce is listed; unknown codes fall back to a number.
enum KeyboardKey {
    static let escape = 53
    static let delete = 51
    static let returnKey = 36
    static let space = 49
    static let tab = 48
    static let capsLock = 57
    static let fn = 63
    static let p = 35

    private static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 41: ";", 40: "K", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "", 51: "", 53: "⎋", 75: "⌅", 76: "⌤", 78: "–", 81: "⌈",
        65: "⌅", 67: "×", 69: "＋", 71: "☒",
        54: "⌘", 55: "⌘", 56: "⇧", 57: "⇪", 58: "⌥", 59: "⌃", 60: "⇧", 61: "⌥", 62: "⌃", 63: "fn",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "home", 116: "⇞", 119: "end", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func name(for keyCode: Int) -> String { names[keyCode] ?? "Key \(keyCode)" }

    static func isModifierKey(_ keyCode: Int) -> Bool {
        ActivationModifier.keyCodes[keyCode] != nil || keyCode == fn || keyCode == capsLock
    }

    /// Keys that must never become a global shortcut: they would break the system or the app
    /// the user is typing into. Escape is the wheel's cancel key; Caps Lock cannot be suppressed;
    /// Power and the media keys would take the machine down.
    static func isBlockedShortcutKey(_ keyCode: Int) -> Bool {
        keyCode == capsLock || keyCode == escape || keyCode == 127 || keyCode == 114
    }
}
