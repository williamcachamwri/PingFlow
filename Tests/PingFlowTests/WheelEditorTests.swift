import XCTest
@testable import PingFlowKit

/// The rules the wheel editor is built on. If these are wrong the UI can only ever be wrong
/// with them, so they are tested on their own, without a view in sight.
final class WheelEditorTests: XCTestCase {

    private var league = PingDefinition.defaultWheel

    func testNormalizeRepairsAnEmptyOrMissingWheel() {
        XCTAssertEqual(WheelEditor.normalize(nil), league)
        XCTAssertEqual(WheelEditor.normalize([]), league)
    }

    func testNormalizeDropsRepeats() {
        let repaired = WheelEditor.normalize([.danger, .danger, .push, .onMyWay])
        XCTAssertEqual(repaired.count, WheelGeometry.sliceCount)
        XCTAssertEqual(Set(repaired).count, repaired.count, "no ping may appear twice")
        XCTAssertEqual(repaired[0], PingDefinition.ID.danger)
        XCTAssertEqual(repaired[1], PingDefinition.ID.push)
        XCTAssertEqual(repaired[2], PingDefinition.ID.onMyWay)
        XCTAssertTrue(repaired.allSatisfy { PingDefinition.allByID[$0] != nil })
    }

    func testNormalizeKeepsTheFirstEightOfALongerList() {
        let long = PingDefinition.ID.allCases
        let repaired = WheelEditor.normalize(long)
        XCTAssertEqual(repaired.count, 8)
        XCTAssertEqual(repaired, Array(long.prefix(8)))
    }

    /// A wheel that only holds one usable ping is topped up from the default arrangement, in
    /// order, so the user keeps a recognisable wheel instead of an empty one.
    func testNormalizeTopsUpFromTheDefaultArrangement() {
        XCTAssertEqual(WheelEditor.normalize([.bait, .bait]), WheelEditor.normalize([.bait]))
        XCTAssertEqual(WheelEditor.normalize([.bait]), [.bait] + Array(league.prefix(7)))
        XCTAssertEqual(WheelEditor.normalize([.bait]).count, WheelGeometry.sliceCount)
    }

    func testIsValid() {
        XCTAssertTrue(WheelEditor.isValid(league))
        XCTAssertFalse(WheelEditor.isValid(Array(league.dropFirst())))
        var broken = league
        broken[3] = broken[4]
        XCTAssertFalse(WheelEditor.isValid(broken))
    }

    // MARK: - assign

    func testAssignSwapsAnExistingWheelPingIntoTheSlot() {
        // `assist` lives at index 4; assigning it to index 0 trades places with `danger`.
        let next = WheelEditor.assign(league, ping: .assist, to: .slice(0))
        XCTAssertEqual(next?[0], PingDefinition.ID.assist)
        XCTAssertEqual(next?[4], PingDefinition.ID.danger)
        XCTAssertTrue(WheelEditor.isValid(next ?? []))
    }

    func testAssignRefusesALibraryPingAndNoChange() {
        // A ping that is not on the wheel cannot be "assigned" — that is `place`'s job.
        XCTAssertNil(WheelEditor.assign(league, ping: .bait, to: .slice(0)))
        // Same slot, same ping: nothing changed, so nothing to report.
        XCTAssertNil(WheelEditor.assign(league, ping: .danger, to: .slice(0)))
        // The hub is not a slice.
        XCTAssertNil(WheelEditor.assign(league, ping: .assist, to: .hub))
        XCTAssertNil(WheelEditor.assign(league, ping: .assist, to: .slice(8)))
    }

    // MARK: - place

    func testPlaceFromTheLibraryReplacesTheOccupant() {
        let next = WheelEditor.place(league, ping: .bait, at: 2)
        XCTAssertEqual(next?[2], PingDefinition.ID.bait)
        XCTAssertEqual(next?.contains(.onMyWay), false, "the replaced ping leaves the wheel")
        XCTAssertTrue(WheelEditor.isValid(next ?? []))
    }

    func testPlaceOfAWheelPingSwapsThem() {
        let next = WheelEditor.place(league, ping: .needVision, at: 0)
        XCTAssertEqual(next?[0], PingDefinition.ID.needVision)
        XCTAssertEqual(next?[5], .danger, "the occupant moves to the dropped ping's old slice")
        XCTAssertTrue(WheelEditor.isValid(next ?? []))
    }

    func testPlaceIsANoOpWhenItWouldChangeNothing() {
        XCTAssertNil(WheelEditor.place(league, ping: .danger, at: 0))
        XCTAssertNil(WheelEditor.place(league, ping: .danger, at: 99))
        XCTAssertNil(WheelEditor.place(league, ping: .danger, at: -1))
    }

    // MARK: - swap

    func testSwapExchangesTwoSlices() {
        let next = WheelEditor.swap(league, 0, 7)
        XCTAssertEqual(next?[0], PingDefinition.ID.enemyVision)
        XCTAssertEqual(next?[7], PingDefinition.ID.danger)
        XCTAssertNil(WheelEditor.swap(league, 3, 3))
        XCTAssertNil(WheelEditor.swap(league, 0, 8))
    }

    func testSlotSliceIndex() {
        XCTAssertEqual(WheelEditor.slotSliceIndex(of: .slice(4)), 4)
        XCTAssertNil(WheelEditor.slotSliceIndex(of: .hub))
    }
}
