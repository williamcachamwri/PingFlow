import AppKit
import QuartzCore
import SwiftUI

/// Draws emotes on screen: a circular-clipped image with a pop-in animation, living for 3 seconds.
/// Simpler than pings — no rings, no ground glow, just the emote itself.
final class EmoteFxContainerView: NSView {
    private struct Handle {
        let root: CALayer
        let itemID: EmoteStage.Item.ID
    }

    private var handles: [Handle] = []
    private var canvasHeight: CGFloat = 0

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func sync(items: [EmoteStage.Item], canvasHeight: CGFloat) {
        let resized = abs(canvasHeight - self.canvasHeight) > 0.5
        self.canvasHeight = canvasHeight
        if resized {
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

    private func add(_ item: EmoteStage.Item) {
        let size = item.size
        let anchor = CGPoint(x: item.position.x, y: canvasHeight - item.position.y)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: size * 2, height: size * 2)
        root.position = anchor
        root.masksToBounds = false
        layer?.addSublayer(root)

        let local = CGPoint(x: size, y: size)
        build(into: root, local: local, item: item)
        handles.append(Handle(root: root, itemID: item.id))
    }

    private func build(into root: CALayer, local: CGPoint, item: EmoteStage.Item) {
        let s = item.size
        let now = CACurrentMediaTime()
        let duration = EmoteStage.displayDuration

        // The emote art: circular-clipped image with a pop-in animation.
        let art = CALayer()
        art.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        art.position = CGPoint(x: local.x, y: local.y)
        art.cornerRadius = s / 2
        art.masksToBounds = true
        art.opacity = 0

        if let image = AssetCatalog.shared.emoteImage(named: item.definition.textureName),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            art.contents = cgImage
            art.contentsGravity = .resizeAspect
        } else {
            art.backgroundColor = NSColor(hex: "#4a4e54").cgColor
        }

        // Pop in: scale 0.3 → 1.1 → 1.0 over 280ms, then hold, then fade out.
        art.add(Self.keyframe(path: "transform.scale",
                              values: [0.3, 1.1, 1.0, 1.0, 0.8],
                              at: [0, 0.15, 0.25, 0.85, 1],
                              duration: duration, begin: now), forKey: "pop")
        art.add(Self.keyframe(path: "opacity",
                              values: [0, 1, 1, 1, 0],
                              at: [0, 0.1, 0.85, 0.9, 1],
                              duration: duration, begin: now), forKey: "fade")
        root.addSublayer(art)

        // A gentle bob after the pop.
        let bob = CAKeyframeAnimation(keyPath: "position")
        bob.values = [local,
                      CGPoint(x: local.x, y: local.y + 4),
                      CGPoint(x: local.x, y: local.y - 4),
                      local]
        bob.keyTimes = [0, 0.33, 0.66, 1]
        bob.duration = 1.4
        bob.beginTime = now + 0.3
        bob.repeatCount = .greatestFiniteMagnitude
        bob.calculationMode = .cubic
        art.add(bob, forKey: "bob")
    }

    // MARK: - Animation factories

    private static func keyframe(path: String, values: [Any], at times: [Double],
                                 duration: Double, begin: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = duration
        animation.beginTime = begin
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.calculationMode = .cubic
        return animation
    }
}

struct EmoteFxHost: NSViewRepresentable {
    @ObservedObject var stage: EmoteStage
    let canvasHeight: CGFloat

    func makeNSView(context: Context) -> EmoteFxContainerView {
        let view = EmoteFxContainerView(frame: .zero)
        view.sync(items: stage.items, canvasHeight: canvasHeight)
        return view
    }

    func updateNSView(_ nsView: EmoteFxContainerView, context: Context) {
        nsView.sync(items: stage.items, canvasHeight: canvasHeight)
    }
}
