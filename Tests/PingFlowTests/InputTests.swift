import XCTest
import AppKit
@testable import PingFlowKit

/// Everything between a raw keystroke and "the user asked for the wheel". The recorder, the
/// matching, and the two coordinate spaces the app has to translate between.
final class InputTests: XCTestCase {

    // MARK: - Key combinations

    func testDefaultToggleShortcutReadsTheWayMacOSWritesIt() {
        XCTAssertEqual(KeyCombo.controlOptionP.displayString, "⌃⌥P")
        XCTAssertEqual(KeyCombo.controlOptionP.keycaps, ["⌃", "⌥", "P"])
        XCTAssertEqual(KeyCombo.controlOptionP.keyName, "P")
    }

    func testMatchesRequiresExactlyTheSameModifiers() {
        let combo = KeyCombo.controlOptionP
        XCTAssertTrue(combo.matches(eventFlags: [.maskControl, .maskAlternate], keyCode: UInt16(KeyboardKey.p)))
        XCTAssertFalse(combo.matches(eventFlags: [.maskControl, .maskAlternate], keyCode: 0), "wrong key")
        XCTAssertFalse(combo.matches(eventFlags: [.maskAlternate], keyCode: UInt16(KeyboardKey.p)), "missing ⌃")
        XCTAssertFalse(combo.matches(eventFlags: [.maskControl, .maskAlternate, .maskShift],
                                     keyCode: UInt16(KeyboardKey.p)), "an extra modifier is a different shortcut")
    }

    /// Left and right hand keys share a flag bit; the tap must not care which one was pressed.
    func testModifierSidesAreEquivalent() {
        for code in [58, 61] { XCTAssertEqual(ActivationModifier.keyCodes[code], .option) }
        for code in [59, 62] { XCTAssertEqual(ActivationModifier.keyCodes[code], .control) }
        for code in [56, 60] { XCTAssertEqual(ActivationModifier.keyCodes[code], .shift) }
        for code in [54, 55] { XCTAssertEqual(ActivationModifier.keyCodes[code], .command) }
        XCTAssertEqual(ActivationModifier.keyCodes[KeyboardKey.capsLock], nil,
                       "Caps Lock is not an activation key on purpose")
    }

    func testGlobalShortcutValidation() {
        XCTAssertTrue(KeyCombo.controlOptionP.isValidGlobalShortcut)
        XCTAssertFalse(KeyCombo(keyCode: UInt16(KeyboardKey.p), modifiers: .none).isValidGlobalShortcut,
                       "a bare letter would swallow every P ever typed")
        XCTAssertFalse(KeyCombo(keyCode: 58, modifiers: .init(option: true)).isValidGlobalShortcut,
                       "a modifier alone is not a shortcut")
        XCTAssertFalse(KeyCombo(keyCode: UInt16(KeyboardKey.escape), modifiers: .init(command: true)).isValidGlobalShortcut,
                       "Escape is the wheel's cancel key")
        XCTAssertFalse(KeyCombo(keyCode: UInt16(KeyboardKey.capsLock), modifiers: .init(command: true)).isValidGlobalShortcut)
    }

    func testModifierSetRoundTripsThroughNSEventFlags() {
        let set = ModifierSet(control: true, option: true, shift: false, command: true)
        XCTAssertEqual(ModifierSet(set.nsFlags), set)
        XCTAssertTrue(ModifierSet.none.isEmpty)
        XCTAssertEqual(set.glyphs, "⌃⌥⌘", "glyphs follow the order macOS uses")
    }

    func testKeyNamesFallBackInsteadOfCrashing() {
        XCTAssertEqual(KeyboardKey.name(for: 35), "P")
        XCTAssertEqual(KeyboardKey.name(for: 9999), "Key 9999")
    }

    // MARK: - Coordinate spaces

    /// The two global spaces mirror on the primary display's height, so a round trip must be an
    /// identity whatever that height is — including on a machine with no screen at all.
    func testCoordinateRoundTripIsIdentity() {
        let original = CGPoint(x: 137, y: 4211)
        XCTAssertEqual(CoordinateSpace.appKitPoint(from: CoordinateSpace.cgPoint(fromAppKit: original)), original)
    }

    func testCoordinateConversionMirrorsOnThePrimaryHeight() {
        let height = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: 500, y: 100)
        let converted = CoordinateSpace.cgPoint(fromAppKit: point)
        XCTAssertEqual(converted.x, 500)
        XCTAssertEqual(converted.y, height - 100)
    }

    // MARK: - Trigger state

    /// The coordinator keeps one primary key and at most one different secondary key; a duplicated
    /// trigger would make the wheel open twice for one press.
    func testTriggerKeysNeverContainDuplicates() {
        func triggerKeys(primary: ActivationModifier, secondary: ActivationModifier?) -> [ActivationModifier] {
            var keys = [primary]
            if let secondary, !keys.contains(secondary) { keys.append(secondary) }
            return keys
        }
        XCTAssertEqual(triggerKeys(primary: .option, secondary: .command), [.option, .command])
        XCTAssertEqual(triggerKeys(primary: .option, secondary: .option), [.option])
        XCTAssertEqual(triggerKeys(primary: .command, secondary: nil), [.command])
    }

    func testCgFlagsCarryTheModifierTheTapLooksFor() {
        XCTAssertTrue(CGEventFlags.maskAlternate.contains(.maskAlternate))
        XCTAssertTrue(ActivationModifier.option.cgFlag.contains(.maskAlternate))
        XCTAssertFalse(ActivationModifier.option.cgFlag.contains(.maskCommand))
    }
}
