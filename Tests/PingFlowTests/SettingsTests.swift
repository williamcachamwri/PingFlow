import XCTest
@testable import PingFlowKit

/// Settings are the one piece of state that outlives the process, so they are tested against a
/// real file: a value that cannot be written and read back is not a setting.
@MainActor
final class SettingsTests: XCTestCase {

    private var directory: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PingFlowTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Round trip

    func testEverySettingSurvivesAWriteAndReload() throws {
        let store = SettingsStore(in: directory)
        store.commit {
            $0.isEnabled = false
            $0.showMenuBarIcon = false
            $0.activationKey = .command
            $0.secondaryActivationKey = .control
            $0.toggleShortcut = KeyCombo(keyCode: 7, modifiers: ModifierSet(shift: true, command: true))
            $0.dragThreshold = 21
            $0.clickBehaviour = .confirm
            $0.cancelOnRightClick = false
            $0.cancelOnOtherKeyPress = false
            $0.wheelSize = 611
            $0.wheelSlots = [.bait, .danger, .push, .onMyWay, .allIn, .assist, .needVision, .enemyMissing]
            $0.clickPing = .bait
            $0.showCentreLabel = false
            $0.dimUnhoveredIcons = false
            $0.volume = 0.33
            $0.isMuted = true
            $0.pingSoundsEnabled = false
            $0.tickSoundEnabled = false
            $0.tickVolume = 0.12
            $0.disabledPingSounds = [.danger, .bait]
            $0.appearanceMode = .dark
            $0.accentColor = .purple
            $0.pingSize = 144
            $0.pingDuration = 4.5
            $0.animationIntensity = 0.25
            $0.overlayOpacity = 0.6
        }
        store.flushSave()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))

        let reloaded = SettingsStore(in: directory)
        XCTAssertEqual(reloaded.settings, store.settings)
        XCTAssertNil(reloaded.fileIssue)
    }

    func testNothingIsWrittenBeforeAChange() {
        let store = SettingsStore(in: directory)
        _ = store.settings
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path),
                       "a first launch must not create a file for settings nobody chose")
    }

    func testUpdateDebouncesAndCommitWritesImmediately() async throws {
        let store = SettingsStore(in: directory)
        store.update { $0.volume = 0.5 }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path), "still debouncing")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path), "debounced write landed")

        store.commit { $0.wheelSize = 500 }
        let reloaded = SettingsStore(in: directory)
        XCTAssertEqual(reloaded.settings.wheelSize, 500, accuracy: 0.001)
    }

    func testResetToDefaultsRewritesTheFile() {
        let store = SettingsStore(in: directory)
        store.commit { $0.wheelSize = 900 }
        store.resetToDefaults()
        XCTAssertEqual(store.settings, AppSettings().normalized())
        XCTAssertEqual(SettingsStore(in: directory).settings, AppSettings().normalized())
    }

    // MARK: - Repairing a hand-edited or stale file

    func testPartialJSONFallsBackPerFieldInsteadOfFailing() throws {
        let json = #"{"volume": 0.25, "wheelSize": 500}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let store = SettingsStore(in: directory)
        XCTAssertNil(store.fileIssue)
        XCTAssertEqual(store.settings.volume, 0.25, accuracy: 0.001)
        XCTAssertEqual(store.settings.wheelSize, 500, accuracy: 0.001)
        XCTAssertEqual(store.settings.wheelSlots, PingDefinition.defaultWheel, "absent keys keep defaults")
        XCTAssertTrue(store.settings.isEnabled)
    }

    func testGarbageFileReportsItselfAndUsesDefaults() throws {
        try "not json {{{".data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let store = SettingsStore(in: directory)
        XCTAssertEqual(store.settings, AppSettings().normalized())
        XCTAssertNotNil(store.fileIssue, "the About page must be able to say what went wrong")
    }

    func testWrongTypesAreIgnoredNotCrashed() throws {
        let json = #"{"volume": "loud", "wheelSize": null, "dragThreshold": [1,2], "isEnabled": 1}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let store = SettingsStore(in: directory)
        XCTAssertEqual(store.settings.volume, AppSettings().volume, accuracy: 0.001)
        XCTAssertTrue(store.settings.isEnabled)
    }

    func testOutOfRangeNumbersAreClampedOnRead() throws {
        let json = #"{"wheelSize": 20000, "dragThreshold": -5, "overlayOpacity": 0, "pingDuration": 0, "animationIntensity": 9}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let settings = SettingsStore(in: directory).settings
        XCTAssertEqual(settings.wheelSize, 900, accuracy: 0.001)
        XCTAssertEqual(settings.dragThreshold, 2, accuracy: 0.001)
        XCTAssertEqual(settings.overlayOpacity, 0.35, accuracy: 0.001)
        XCTAssertEqual(settings.pingDuration, 1, accuracy: 0.001)
        XCTAssertEqual(settings.animationIntensity, 1.5, accuracy: 0.001)
    }

    func testADuplicatedWheelIsRepairedNotAccepted() throws {
        let json = #"{"wheelSlots": ["danger","danger","push","push","omw","allin","assist","needvision"]}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let settings = SettingsStore(in: directory).settings
        XCTAssertEqual(Set(settings.wheelSlots).count, 8)
        XCTAssertTrue(WheelEditor.isValid(settings.wheelSlots))
    }

    /// A ping id the app does not know is not a value the wheel can hold, so the list as a whole
    /// is rejected and the League arrangement comes back. Better a recognisable wheel than a
    /// half-repaired one.
    func testAnUnknownPingIDFallsBackToTheDefaultWheel() throws {
        let json = #"{"wheelSlots": ["danger","yasuo","push","omw","allin","assist","needvision","missing","enemyvision","bait"]}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let settings = SettingsStore(in: directory).settings
        XCTAssertEqual(settings.wheelSlots, PingDefinition.defaultWheel)
        XCTAssertTrue(WheelEditor.isValid(settings.wheelSlots))
    }

    func testABlockedGlobalShortcutIsReplacedNotKept() throws {
        let json = #"{"toggleShortcut": {"keyCode": 53, "modifiers": {"containsCommand": true}}}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let settings = SettingsStore(in: directory).settings
        XCTAssertEqual(settings.toggleShortcut, .controlOptionP, "Escape is the wheel's cancel key, not a shortcut")
    }

    /// A partial modifiers object is what a hand-edit looks like; absent flags read as false.
    func testAPartialModifierObjectStillDecodes() throws {
        let json = #"{"toggleShortcut": {"keyCode": 7, "modifiers": {"containsOption": true}}}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        let settings = SettingsStore(in: directory).settings
        XCTAssertEqual(settings.toggleShortcut?.displayString, "⌥X")
        XCTAssertEqual(settings.toggleShortcut?.modifiers, ModifierSet(option: true))
    }

    func testABareKeyShortcutIsRepaired() throws {
        let json = #"{"toggleShortcut": {"keyCode": 35, "modifiers": {}}}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        XCTAssertEqual(SettingsStore(in: directory).settings.toggleShortcut, .controlOptionP,
                       "a shortcut with no modifier would eat every P typed on the machine")
    }

    func testTheSettingsFileRoundTripsAShortcutWrittenByTheRecorder() {
        let store = SettingsStore(in: directory)
        store.commit { $0.toggleShortcut = KeyCombo(keyCode: 35, modifiers: ModifierSet(control: true, option: true, shift: true)) }
        let reloaded = SettingsStore(in: directory)
        XCTAssertEqual(reloaded.settings.toggleShortcut?.displayString, "⌃⌥⇧P")
    }

    func testSecondaryKeyEqualtoThePrimaryKeyIsDropped() throws {
        let json = #"{"activationKey": "option", "secondaryActivationKey": "option"}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("settings-test.json"))
        XCTAssertNil(SettingsStore(in: directory).settings.secondaryActivationKey)
    }

    /// Sound switches are stored per ping, not per slice — moving a slice must not silently
    /// unmute a ping the user turned off.
    func testDisabledSoundsOutliveTheSliceTheyWereOn() {
        let store = SettingsStore(in: directory)
        store.commit {
            $0.disabledPingSounds = [.danger]
        }
        store.commit { $0.wheelSlots = [.bait, .push, .onMyWay, .allIn, .assist, .needVision, .enemyMissing, .enemyVision] }
        XCTAssertEqual(store.settings.disabledPingSounds, [.danger])
        XCTAssertFalse(store.settings.isPingSoundEnabled(.danger))
        XCTAssertTrue(store.settings.isPingSoundEnabled(.bait))
    }

    func testPingSoundsAreOffWhenTheMasterSwitchIsOff() {
        var settings = AppSettings()
        settings.disabledPingSounds = []
        XCTAssertTrue(settings.isPingSoundEnabled(.danger))
        settings.pingSoundsEnabled = false
        XCTAssertFalse(settings.isPingSoundEnabled(.danger))
    }
}
