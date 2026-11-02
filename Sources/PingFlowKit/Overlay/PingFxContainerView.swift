import AppKit
import QuartzCore
import SwiftUI

/// The ping animation, built from Core Animation layers rather than views: one layer group per
/// ping, all timing set up once at spawn, nothing rebuilt while the pointer moves or other pings
/// play. Every number mirrors the reference's CSS keyframes, so the motion is the same film
/// played back on a different projector.
final class PingFxContainerView: NSView {
    private struct Handle {
        let root: CALayer
        let itemID: PingStage.Item.ID
    }

    private var handles: [Handle] = []
    /// The panel's height, needed to turn the stage's y-down points into this view's y-up ones.
    private var canvasHeight: CGFloat = 0

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Diffs by identity: an arriving ping adds a layer group, a finished one drops it.
    func sync(items: [PingStage.Item], canvasHeight: CGFloat) {
        let resized = abs(canvasHeight - self.canvasHeight) > 0.5
        self.canvasHeight = canvasHeight
        if resized {
            // A display mode change moves the ground under existing pings; rebuild rather than skew.
            removeAll()
        }
        let live = Set(items.map(\.id))
        handles.removeAll { handle in
            guard !live.contains(handle.itemID) else { return false }
            handle.root.sublayers?.forEach { Self.strip($0) }
            handle.root.removeFromSuperlayer()
            return true
        }
        let present = Set(handles.map(\.itemID))
        for item in items where !present.contains(item.id) {
            add(item)
        }
    }

    func removeAll() {
        handles.forEach { $0.root.removeFromSuperlayer() }
        handles.removeAll()
    }

    private static func strip(_ layer: CALayer) {
        layer.sublayers?.forEach { strip($0) }
        layer.removeAllAnimations()
    }

    private func add(_ item: PingStage.Item) {
        let size = item.size
        let anchor = CGPoint(x: item.position.x, y: canvasHeight - item.position.y)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: size * 2, height: size * 2)
        root.position = anchor
        root.masksToBounds = false
        layer?.addSublayer(root)

        // The anchor sits at the middle of the root, so every offset below reads the way the
        // reference's CSS reads: 0.42 × size left, 0.73 × size up, and so on.
        let local = CGPoint(x: size, y: size)
        build(into: root, local: local, item: item)
        handles.append(Handle(root: root, itemID: item.id))
    }

    // MARK: - Building one ping

    private func build(into root: CALayer, local: CGPoint, item: PingStage.Item) {
        let s = item.size
        let duration = item.duration
        let intensity = CGFloat(item.intensity)
        let colour = NSColor(hex: item.definition.colorHex).cgColor
        let now = CACurrentMediaTime()

        // 1. The coloured ground ellipse the ping stands on.
        let ground = Self.gradientLayer(
            frame: CGRect(x: local.x - s * 0.42, y: local.y - s * 0.44, width: s * 0.84, height: s * 0.24),
            colour: colour)
        ground.add(Self.keyframe(path: "opacity", values: [0, 0.75, 0.55, 0], at: [0, 0.1, 0.85, 1],
                                 duration: duration, begin: now), forKey: "ground")
        root.addSublayer(ground)

        // 2. Three rings: 0 ms, 220 ms and 1.4 s, each 0.25× → 1.35× over 650 ms.
        for delay in [0.0, 0.22, 1.4] {
            let ring = Self.ringLayer(side: s * 1.09, centre: local, colour: colour)
            // A CAAnimation only owns the presentation from its `beginTime` onward; before that the
            // layer shows its model values, which for a ring means a full-size circle parked around
            // the icon for up to 1.4 s — the "frozen ring" CSS avoids with `fill-mode: backwards`.
            // Starting the model at the from-state is the same promise in Core Animation.
            ring.opacity = 0
            ring.setAffineTransform(CGAffineTransform(scaleX: 0.25, y: 0.25))
            let begin = now + delay
            ring.add(Self.simple("transform.scale", from: 0.25, to: 1.35, duration: 0.65,
                                 begin: begin, easeOut: true), forKey: "scale")
            ring.add(Self.simple("opacity", from: 0.95, to: 0, duration: 0.65,
                                 begin: begin, easeOut: true), forKey: "fade")
            root.addSublayer(ring)
        }

        // 3. The art, with the whole-group fade over the last 13% of its life.
        let art = CALayer()
        art.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        art.position = CGPoint(x: local.x, y: local.y - s * 0.27 + s / 2)
        art.masksToBounds = false
        art.add(Self.keyframe(path: "opacity", values: [1, 1, 0], at: [0, 0.87, 1],
                              duration: duration, begin: now), forKey: "life")
        root.addSublayer(art)

        // The bob rides on its own layer so it never fights the pop's transform. It is a child of
        // `art`, so its position is in the art's own space — the centre of its bounds, not the
        // root-relative point again, which would walk the art half a size off to the upper right.
        let bob = CALayer()
        bob.bounds = art.bounds
        bob.position = CGPoint(x: art.bounds.midX, y: art.bounds.midY)
        bob.masksToBounds = false
        art.addSublayer(bob)

        if item.definition.isAllIn {
            buildAllIn(into: bob, bounds: art.bounds, item: item, colour: colour,
                       start: now, intensity: intensity)
        } else {
            buildSingle(into: bob, bounds: art.bounds, item: item, colour: colour,
                        start: now, intensity: intensity)
        }
    }

    /// Pop → hold → fade: 0.4 → 1.15 → 1.0 over 280 ms with an overshoot ease, then the bob.
    private func buildSingle(into bob: CALayer, bounds: CGRect, item: PingStage.Item,
                             colour: CGColor, start: Double, intensity: CGFloat) {
        guard let art = imageLayer(for: item.definition.artTextures.first, bounds: bounds) else { return }
        Self.applyGlow(to: art, colour: colour)
        bob.addSublayer(art)

        art.add(Self.keyframe(path: "transform.scale", values: [0.4, 1.15, 1.0], at: [0, 0.6, 1],
                              duration: 0.28, begin: start,
                              bezier: Self.overshootBezier), forKey: "pop")
        art.add(Self.simple("opacity", from: 0, to: 1, duration: 0.28, begin: start, easeOut: true),
                forKey: "popFade")
        addBob(to: bob, begin: start + 0.3, amplitude: 5 * intensity)
    }

    /// All In: two halves slide in from opposite diagonals, a white flash, a shake, then the bob.
    private func buildAllIn(into bob: CALayer, bounds: CGRect, item: PingStage.Item,
                            colour: CGColor, start: Double, intensity: CGFloat) {
        let s = bounds.width
        let clash = CALayer()
        clash.bounds = bounds
        clash.position = CGPoint(x: bounds.midX, y: bounds.midY)
        clash.masksToBounds = false
        bob.addSublayer(clash)

        for (index, texture) in item.definition.artTextures.enumerated() {
            guard let art = imageLayer(for: texture, bounds: bounds) else { continue }
            Self.applyGlow(to: art, colour: colour)
            let dx: CGFloat = index == 0 ? s * 0.64 : -s * 0.64
            // CSS `translate(±0.64s, -0.64s)` means "from above"; in this y-up layer that is +y.
            let from = CGPoint(x: bounds.midX + dx, y: bounds.midY + s * 0.64)
            art.add(Self.keyframe(path: "position", values: [from, CGPoint(x: bounds.midX, y: bounds.midY)],
                                  at: [0, 1], duration: 0.22, begin: start,
                                  bezier: Self.clashBezier), forKey: "slide")
            art.add(Self.simple("opacity", from: 0, to: 1, duration: 0.22, begin: start, easeOut: false),
                    forKey: "slideFade")
            clash.addSublayer(art)
        }

        let flash = Self.gradientLayer(
            frame: CGRect(x: bounds.midX - s * 0.25, y: bounds.midY - s * 0.25, width: s * 0.5, height: s * 0.5),
            colour: NSColor.white.cgColor,
            halo: colour)
        // Same rule as the rings: invisible until its own 0.2 s mark.
        flash.opacity = 0
        flash.setAffineTransform(CGAffineTransform(scaleX: 0.3, y: 0.3))
        flash.add(Self.keyframe(path: "transform.scale", values: [0.3, 1, 2.2], at: [0, 0.3, 1],
                                duration: 0.35, begin: start + 0.2), forKey: "flashScale")
        flash.add(Self.keyframe(path: "opacity", values: [0, 1, 0], at: [0, 0.3, 1],
                                duration: 0.35, begin: start + 0.2), forKey: "flashFade")
        clash.addSublayer(flash)

        clash.add(Self.keyframe(path: "transform.translation",
                                values: [CGPoint(x: 0, y: 0),
                                         CGPoint(x: -3 * intensity, y: -2 * intensity),
                                         CGPoint(x: 3 * intensity, y: 2 * intensity),
                                         CGPoint(x: -2 * intensity, y: 1 * intensity),
                                         CGPoint(x: 0, y: 0)],
                                at: [0, 0.25, 0.5, 0.75, 1],
                                duration: 0.25, begin: start + 0.22), forKey: "shake")
        addBob(to: bob, begin: start + 0.5, amplitude: 5 * intensity)
    }

    /// A gentle 5 px rise and fall on a 1.6 s cycle, repeating until the ping is removed.
    private func addBob(to layer: CALayer, begin: Double, amplitude: CGFloat) {
        guard amplitude > 0.01 else { return }
        let bob = CAKeyframeAnimation(keyPath: "position")
        let centre = layer.position
        bob.values = [centre, CGPoint(x: centre.x, y: centre.y + amplitude), centre]
        bob.keyTimes = [0, 0.5, 1]
        bob.duration = 1.6
        bob.beginTime = begin
        bob.repeatCount = .greatestFiniteMagnitude
        bob.calculationMode = .cubic
        layer.add(bob, forKey: "bob")
    }

    private func imageLayer(for texture: String?, bounds: CGRect) -> CALayer? {
        guard let name = texture else { return nil }
        let layer = CALayer()
        layer.bounds = bounds
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer.contentsGravity = .resizeAspect
        layer.masksToBounds = false
        if let image = AssetCatalog.shared.cgImage(named: name) {
            layer.contents = image
        } else if let fallback = AssetCatalog.shared.cgImage(named: PingDefinition.fallbackTexture) {
            // Same rule as the reference's `img.onerror`: fall back to the generic ping art.
            layer.contents = fallback
        } else {
            return nil
        }
        return layer
    }

    // MARK: - Layer factories

    private static func gradientLayer(frame: CGRect, colour: CGColor, halo: CGColor? = nil) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.frame = frame
        gradient.type = .radial
        gradient.colors = [colour, Self.clearCopy(of: halo ?? colour)]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        return gradient
    }

    /// The same colour with nothing in it — the outer stop of every radial. `copy(alpha:)` is
    /// optional, and a gradient that cannot read a stop drops the whole array, so the fallback is
    /// explicit rather than an implicit `Any` coercion.
    private static func clearCopy(of colour: CGColor) -> CGColor {
        colour.copy(alpha: 0) ?? CGColor(red: 0, green: 0, blue: 0, alpha: 0)
    }

    private static func ringLayer(side: CGFloat, centre: CGPoint, colour: CGColor) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        ring.position = CGPoint(x: centre.x, y: centre.y)
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.strokeColor = colour
        ring.fillColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        ring.lineWidth = 3
        ring.shadowColor = colour
        ring.shadowOpacity = 1
        ring.shadowRadius = 18
        return ring
    }

    /// `filter: drop-shadow(0 0 10px var(--c))` on the art.
    static func applyGlow(to layer: CALayer, colour: CGColor) {
        layer.shadowColor = colour
        layer.shadowOpacity = 0.9
        layer.shadowRadius = 10
        layer.shadowOffset = .zero
    }

    // MARK: - Animation factories

    private static func simple(_ keyPath: String, from: Any, to: Any, duration: Double,
                               begin: Double, easeOut: Bool) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = begin
        animation.timingFunction = CAMediaTimingFunction(name: easeOut ? .easeOut : .linear)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// `values` and `at` are the keyframes; `bezier` is one CSS cubic-bezier applied to every
    /// interval, which is what `animation-timing-function` does in the reference's sheet.
    private static func keyframe(path: String, values: [Any], at times: [Double], duration: Double,
                                 begin: Double, bezier: (Float, Float, Float, Float)? = nil)
        -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = duration
        animation.beginTime = begin
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.calculationMode = .cubic
        if let bezier {
            let function = CAMediaTimingFunction(controlPoints: bezier.0, bezier.1, bezier.2, bezier.3)
            animation.timingFunctions = Array(repeating: function, count: max(1, values.count - 1))
        }
        return animation
    }

    /// `cubic-bezier(.2, 1.6, .4, 1)` — the overshoot that gives the pop its League snap.
    static let overshootBezier: (Float, Float, Float, Float) = (0.2, 1.6, 0.4, 1.0)
    /// `cubic-bezier(.5, 0, .9, .5)` — the ease the two All In halves arrive on.
    static let clashBezier: (Float, Float, Float, Float) = (0.5, 0.0, 0.9, 0.5)
}

/// SwiftUI bridge: the stage publishes items, this view keeps the layer tree in step.
struct PingFxHost: NSViewRepresentable {
    @ObservedObject var stage: PingStage
    let canvasHeight: CGFloat

    func makeNSView(context: Context) -> PingFxContainerView {
        let view = PingFxContainerView(frame: .zero)
        view.sync(items: stage.items, canvasHeight: canvasHeight)
        return view
    }

    func updateNSView(_ nsView: PingFxContainerView, context: Context) {
        nsView.sync(items: stage.items, canvasHeight: canvasHeight)
    }
}
