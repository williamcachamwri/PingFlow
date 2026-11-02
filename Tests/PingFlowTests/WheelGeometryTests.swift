import XCTest
@testable import PingFlowKit

/// The wheel's geometry is the one thing that has to match League exactly, because it decides
/// which ping a gesture means. These are the reference's own numbers.
final class WheelGeometryTests: XCTestCase {

    func testCardinalDirectionsMapToTheRightSlice() {
        let dead: CGFloat = 10
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 0, dy: -100, deadZone: dead), 0, "north")
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 100, dy: 0, deadZone: dead), 2, "east")
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 0, dy: 100, deadZone: dead), 4, "south")
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: -100, dy: 0, deadZone: dead), 6, "west")
    }

    func testDiagonalsFillInClockwise() {
        let dead: CGFloat = 10
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 70, dy: -70, deadZone: dead), 1, "north-east")
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 70, dy: 70, deadZone: dead), 3, "south-east")
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: -70, dy: 70, deadZone: dead), 5, "south-west")
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: -70, dy: -70, deadZone: dead), 7, "north-west")
    }

    func testDeadZoneSelectsNothing() {
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 0, dy: 0, deadZone: 43), -1)
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 20, dy: -20, deadZone: 43), -1)
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: 44, dy: 0, deadZone: 43), 2)
    }

    /// Slices are centred on the compass points, so the boundary sits half a sector away:
    /// 22.5° east of north. Inside it is still Danger, outside it is Push.
    func testSliceBoundariesAreCentredOnTheCompass() {
        let dead: CGFloat = 1
        let justInside = WheelGeometry.point(radius: 100, degrees: -90 + 22.4)
        let justOutside = WheelGeometry.point(radius: 100, degrees: -90 + 22.6)
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: justInside.x, dy: justInside.y, deadZone: dead), 0)
        XCTAssertEqual(WheelGeometry.sliceIndex(dx: justOutside.x, dy: justOutside.y, deadZone: dead), 1)
    }

    func testEveryAngleBelongsToExactlyOneSlice() {
        var counts = Array(repeating: 0, count: WheelGeometry.sliceCount)
        for degree in stride(from: 0, to: 360, by: 1) {
            let p = WheelGeometry.point(radius: 100, degrees: CGFloat(degree))
            let index = WheelGeometry.sliceIndex(dx: p.x, dy: p.y, deadZone: 1)
            XCTAssertTrue((0..<WheelGeometry.sliceCount).contains(index), "degree \(degree) fell out of the wheel")
            counts[index] += 1
        }
        XCTAssertEqual(counts, [45, 45, 45, 45, 45, 45, 45, 45], "sectors must be exactly 45° each")
    }

    func testLayoutScalesProportionallyWithWheelSize() {
        let small = WheelLayout(size: 300)
        let large = WheelLayout(size: 900)
        XCTAssertEqual(small.scale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(large.scale, 1.5, accuracy: 0.0001)
        XCTAssertEqual(large.outerRadius / small.outerRadius, 3, accuracy: 0.0001)
        XCTAssertEqual(large.iconRadius / small.iconRadius, 3, accuracy: 0.0001)
        XCTAssertEqual(small.innerRadius, 43, accuracy: 0.001)
        XCTAssertEqual(small.outerRadius, 94, accuracy: 0.001)
        XCTAssertEqual(small.extensionRadius, 144, accuracy: 0.001)
    }

    func testCardinalSlicesReachFurtherThanTheOthers() {
        let layout = WheelLayout(size: 600)
        for index in 0..<8 {
            let radius = layout.outerRadius(forSlice: index)
            if index % 2 == 0 {
                XCTAssertEqual(radius, layout.extensionRadius, accuracy: 0.0001, "slice \(index)")
            } else {
                XCTAssertEqual(radius, layout.outerRadius, accuracy: 0.0001, "slice \(index)")
            }
        }
    }

    func testIconCentresSitOnTheirOwnSlice() {
        let layout = WheelLayout(size: 600)
        let north = layout.iconCentre(forSlice: 0)
        XCTAssertEqual(north.x, 0, accuracy: 0.001)
        XCTAssertLessThan(north.y, 0, "north is above the centre in a y-down space")
        let east = layout.iconCentre(forSlice: 2)
        XCTAssertGreaterThan(east.x, 0)
        XCTAssertEqual(east.y, 0, accuracy: 0.001)
    }

    func testCentreAnglesMatchTheSliceIndex() {
        for index in 0..<WheelGeometry.sliceCount {
            let angle = WheelGeometry.centreAngle(of: index)
            let point = WheelGeometry.point(radius: 100, degrees: angle)
            XCTAssertEqual(WheelGeometry.sliceIndex(dx: point.x, dy: point.y, deadZone: 1), index,
                           "slice \(index) must select at its own centre angle")
        }
    }
}
