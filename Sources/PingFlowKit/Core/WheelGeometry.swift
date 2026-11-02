import Foundation
import CoreGraphics

/// Wheel geometry in points, taken from the reference implementation (`src/shared/geometry.ts`)
/// so the proportions match League's wheel. The reference draws a 600 pt canvas whose slices run
/// from radius 86 to 188, with the four cardinal slices reaching 288 and icons at 137.
struct WheelGeometry: Hashable, Sendable {
    static let reference = WheelGeometry()

    /// Canvas side the constants are expressed against.
    var canvas: CGFloat = 600
    /// Dead zone: closer than this to the centre selects nothing.
    var innerRadius: CGFloat = 86
    /// Outer edge of the eight slices.
    var outerRadius: CGFloat = 188
    /// Outer edge of the four cardinal slices, which fade out past `outerRadius`.
    var extensionRadius: CGFloat = 288
    /// Radius the slice icons sit on.
    var iconRadius: CGFloat = 137
    /// Icon side length.
    var iconSize: CGFloat = 48

    static let sliceCount = 8
    static let sliceAngle: CGFloat = 45

    /// Scale factor from the reference canvas to the user's wheel size setting.
    func scale(forSize size: CGFloat) -> CGFloat { size / canvas }

    func innerRadius(atSize size: CGFloat) -> CGFloat { innerRadius * scale(forSize: size) }
    func outerRadius(atSize size: CGFloat) -> CGFloat { outerRadius * scale(forSize: size) }
    func extensionRadius(atSize size: CGFloat) -> CGFloat { extensionRadius * scale(forSize: size) }
    func iconRadius(atSize size: CGFloat) -> CGFloat { iconRadius * scale(forSize: size) }
    func iconSize(atSize size: CGFloat) -> CGFloat { iconSize * scale(forSize: size) }

    /// Centre angle of slice `index` in degrees, measured the way `atan2(dy, dx)` is on a
    /// y-down screen: 0° points east, 90° south. Slice 0 is north, indices run clockwise.
    static func centreAngle(of index: Int) -> CGFloat { -90 + CGFloat(index) * sliceAngle }

    /**
     Slice under an offset from the wheel centre, in screen coordinates (y points down).
     Returns `-1` inside the dead zone, else `0..7` with `0` = north, increasing clockwise.
     Mirrors `pickSlice()` in the reference: the same 22.5° phase shift, so slices are centred
     on the compass directions rather than straddling them.
     */
    static func sliceIndex(dx: CGFloat, dy: CGFloat, deadZone: CGFloat) -> Int {
        if hypot(dx, dy) < deadZone { return -1 }
        let degrees = (atan2(dy, dx) * 180 / .pi + 90 + 22.5 + 360).truncatingRemainder(dividingBy: 360)
        return Int(floor(degrees / sliceAngle)) % sliceCount
    }

    /// Polar point in the same y-down screen sense as `sliceIndex`.
    static func point(radius: CGFloat, degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: radius * cos(radians), y: radius * sin(radians))
    }
}

/// Pure layout numbers for one wheel, derived once per geometry change so the view never
/// recomputes trigonometry while the pointer moves.
struct WheelLayout: Hashable, Sendable {
    var size: CGFloat
    var canvas: CGFloat
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var extensionRadius: CGFloat
    var iconRadius: CGFloat
    var iconSize: CGFloat

    init(size: CGFloat, geometry: WheelGeometry = .reference) {
        self.size = size
        self.canvas = geometry.canvas
        self.innerRadius = geometry.innerRadius(atSize: size)
        self.outerRadius = geometry.outerRadius(atSize: size)
        self.extensionRadius = geometry.extensionRadius(atSize: size)
        self.iconRadius = geometry.iconRadius(atSize: size)
        self.iconSize = geometry.iconSize(atSize: size)
    }

    /// Reference canvas → this wheel. Every decorative offset in the view is multiplied by it,
    /// so a 300 pt wheel and a 900 pt wheel are the same drawing.
    var scale: CGFloat { size / canvas }

    /// Cardinal slices (N, E, S, W) are the ones League draws longer.
    static func isCardinal(_ index: Int) -> Bool { index % 2 == 0 }

    func outerRadius(forSlice index: Int) -> CGFloat {
        Self.isCardinal(index) ? extensionRadius : outerRadius
    }

    func iconCentre(forSlice index: Int) -> CGPoint {
        WheelGeometry.point(radius: iconRadius, degrees: WheelGeometry.centreAngle(of: index))
    }
}
