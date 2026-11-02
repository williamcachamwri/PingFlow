import XCTest
@testable import PingFlowKit

/// The scene is the only thing the input layer writes and the only thing the wheel view reads,
/// so its state machine has to be right on its own — no windows, no taps.
@MainActor
final class WheelSceneTests: XCTestCase {

    private func settings(_ mutate: (inout AppSettings) -> Void = { _ in }) -> AppSettings {
        var s = AppSettings()
        mutate(&s)
        return s.normalized()
    }

    func testSyncCopiesTheNumbersTheViewNeeds() {
        let scene = WheelScene()
        let custom = settings {
            $0.wheelSlots = [.bait, .push, .onMyWay, .allIn, .assist, .needVision, .enemyMissing, .enemyVision]
            $0.wheelSize = 520
            $0.dimUnhoveredIcons = false
            $0.showCentreLabel = false
            $0.overlayOpacity = 0.7
            $0.accentColor = .green
        }
        scene.sync(settings: custom)
        XCTAssertEqual(scene.slots, custom.wheelSlots)
        XCTAssertEqual(scene.size, 520, accuracy: 0.001)
        XCTAssertFalse(scene.dimUnhoveredIcons)
        XCTAssertFalse(scene.showCentreLabel)
        XCTAssertEqual(scene.overlayOpacity, 0.7, accuracy: 0.001)
        XCTAssertEqual(scene.accentHex, AccentColorChoice.green.hex)
    }

    func testOpenThenHoverThenClose() async {
        let scene = WheelScene()
        XCTAssertEqual(scene.phase, .hidden)
        XCTAssertFalse(scene.isOpen)

        scene.open(at: CGPoint(x: 400, y: 400), settings: settings())
        XCTAssertEqual(scene.phase, .opening, "the wheel must appear before it can animate")
        XCTAssertTrue(scene.isOpen)
        XCTAssertEqual(scene.origin, CGPoint(x: 400, y: 400), "the press point is where the ping lands")

        // The view's 120 ms opening is driven by the phase flip below, on the next runloop.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(scene.phase, .active)

        XCTAssertTrue(scene.setHovered(0), "the first slice is a change")
        XCTAssertEqual(scene.centreText, "Danger", "the hub names what is about to be sent")
        XCTAssertFalse(scene.setHovered(0), "repeating the same slice must not tick again")
        XCTAssertTrue(scene.setHovered(nil))
        XCTAssertEqual(scene.centreText, "PING", "the dead zone clears the label")

        scene.close()
        XCTAssertEqual(scene.phase, .closing)
        XCTAssertNil(scene.hoveredSlice)
        XCTAssertFalse(scene.isOpen)
        scene.markHidden()
        XCTAssertEqual(scene.phase, .hidden)
    }

    func testHoveringAnUnknownSliceIsIgnored() {
        let scene = WheelScene()
        scene.open(at: .zero, settings: settings())
        XCTAssertTrue(scene.setHovered(99))
        XCTAssertNil(scene.hoveredDefinition)
        XCTAssertEqual(scene.centreText, "PING")
    }

    func testHoveredDefinitionFollowsTheSlots() {
        let scene = WheelScene()
        let custom = settings { $0.wheelSlots = [.bait] + Array(PingDefinition.defaultWheel.dropFirst()) }
        scene.sync(settings: custom)
        // Opening re-syncs from the settings handed to it, so the same arrangement must be passed.
        scene.open(at: .zero, settings: custom)
        XCTAssertEqual(scene.slots, custom.wheelSlots)
        scene.setHovered(0)
        XCTAssertEqual(scene.hoveredDefinition?.id, .bait)
    }

    func testCloseOnAHiddenWheelDoesNothing() {
        let scene = WheelScene()
        scene.close()
        XCTAssertEqual(scene.phase, .hidden)
    }

    func testConfirmedSliceFlashesAndClears() async {
        let scene = WheelScene()
        scene.open(at: .zero, settings: settings())
        scene.flashConfirmed(3)
        XCTAssertEqual(scene.confirmedSlice, 3)
        try? await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertNil(scene.confirmedSlice, "the flash is a transient, not a stuck highlight")
    }

    func testOpeningAgainResetsTheGesture() {
        let scene = WheelScene()
        scene.open(at: .zero, settings: settings())
        scene.setHovered(2)
        scene.flashConfirmed(2)
        scene.open(at: CGPoint(x: 10, y: 10), settings: settings())
        XCTAssertNil(scene.hoveredSlice, "a new gesture starts clean")
        XCTAssertNil(scene.confirmedSlice)
        XCTAssertEqual(scene.centreText, "PING")
    }
}

/// Pings are independent of the wheel and of each other: several may be on screen at once, and
/// each one must leave by itself.
@MainActor
final class PingStageTests: XCTestCase {

    private func shortSettings() -> AppSettings {
        var s = AppSettings()
        s.pingDuration = 1
        return s.normalized()
    }

    func testSpawnsStackAndClearIndependently() throws {
        let stage = PingStage()
        XCTAssertTrue(stage.isEmpty)
        let settings = shortSettings()
        stage.spawn(definition: .init(id: .danger, name: "Danger", iconTexture: "x",
                                      artTextures: ["x"], sound: "y", colorHex: "#fff",
                                      usage: "", category: .defend),
                    at: CGPoint(x: 10, y: 20), settings: settings)
        stage.spawn(definition: PingDefinition.definition(for: .push), at: .zero, settings: settings)
        XCTAssertEqual(stage.items.count, 2, "two pings at once is normal play")
        XCTAssertEqual(stage.items.first?.position, CGPoint(x: 10, y: 20))
        let first = try XCTUnwrap(stage.items.first)
        XCTAssertEqual(first.size, CGFloat(settings.pingSize), accuracy: 0.001)
        XCTAssertEqual(first.duration, 1, accuracy: 0.001)
        stage.clear()
        XCTAssertTrue(stage.isEmpty)
    }

    func testRemovalIsScheduledNotImmediate() async {
        let stage = PingStage()
        let settings = shortSettings()
        let item = stage.spawn(definition: PingDefinition.definition(for: .assist), at: .zero, settings: settings)
        XCTAssertEqual(stage.items.count, 1)
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        XCTAssertTrue(stage.isEmpty, "a finished ping must leave the layer tree by itself")
        _ = item
    }
}
