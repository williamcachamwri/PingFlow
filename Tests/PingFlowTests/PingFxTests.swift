import AppKit
import QuartzCore
import XCTest
@testable import PingFlowKit

/// A Core Animation only owns a layer from its `beginTime` onward; before that the layer shows its
/// model values. Three of the ping's rings are told to start later than the ping itself, so unless
/// the model already sits at the animation's first keyframe, a hard circle stands parked around the
/// icon for up to 1.4 s — the frozen ring nobody sees in the game.
final class PingFxTests: XCTestCase {
    @MainActor
    func testRingsAreInvisibleUntilTheirOwnAnimationBegins() {
        guard let definition = PingDefinition.allByID[.allIn] else {
            return XCTFail("All In is missing from the catalogue")
        }
        let view = PingFxContainerView(frame: NSRect(x: 0, y: 0, width: 700, height: 700))
        var settings = AppSettings()
        settings.pingSize = 160
        let item = PingStage().spawn(definition: definition,
                                     at: CGPoint(x: 350, y: 350),
                                     settings: settings)
        view.sync(items: [item], canvasHeight: 700)

        let rings = Self.shapeLayers(in: view.layer!)
        XCTAssertEqual(rings.count, 3, "one shape layer per pulse")
        for ring in rings {
            XCTAssertEqual(ring.opacity, 0, accuracy: 0.001, "a ring must never be parked on screen")
            XCTAssertEqual(ring.affineTransform().a, 0.25, accuracy: 0.001,
                           "and it must wait at the size its animation starts from")
        }
    }

    @MainActor
    private static func shapeLayers(in layer: CALayer) -> [CAShapeLayer] {
        var found: [CAShapeLayer] = []
        if let shape = layer as? CAShapeLayer { found.append(shape) }
        for child in layer.sublayers ?? [] { found.append(contentsOf: shapeLayers(in: child)) }
        return found
    }
}
