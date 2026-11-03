import AppKit
import QuartzCore
import SwiftUI

/// Draws emotes on screen: a circular-clipped image with a pop-in animation, living for a few
/// seconds. A shipped png stays a plain CALayer; a gif or a clip needs a decoder, so it gets one
/// view instead — and only the fired emote ever runs it.
final class EmoteFxContainerView: NSView {
    private struct Handle {
        let root: CALayer
        let itemID: EmoteStage.Item.ID
        /// Non-nil only for animated art, which cannot be drawn by a layer alone.
        let view: EmoteArtNSView?
    }

    /// Concurrent decoders on screen. A flood of clips falls back to their posters instead of
    /// asking every core in the machine to decode video at once.
    static let maximumAnimatedViews = 3

    private var handles: [Handle] = []
    private var canvasHeight: CGFloat = 0

    override var isFlipped: Bool { false }

    var animatedViewCount: Int { handles.filter { $0.view != nil }.count }

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
            handle.view?.stop()
            handle.view?.removeFromSuperview()
            return true
        }
        let present = Set(handles.map(\.itemID))
        for item in items where !present.contains(item.id) {
            add(item)
        }
    }

    func removeAll() {
        for handle in handles {
            handle.root.removeFromSuperlayer()
            handle.view?.stop()
            handle.view?.removeFromSuperview()
        }
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
        var view: EmoteArtNSView?
        if item.asset.isAnimated, animatedViewCount < Self.maximumAnimatedViews {
            let art = EmoteArtNSView(frame: CGRect(x: anchor.x - size / 2,
                                                   y: anchor.y - size / 2,
                                                   width: size,
                                                   height: size))
            art.corner = size / 2
            art.show(asset: item.asset, animates: true)
            addSubview(art)
            view = art
            animate(layer: art.layer, local: local, item: item, translated: true)
        } else {
            build(into: root, local: local, item: item)
        }
        handles.append(Handle(root: root, itemID: item.id, view: view))
    }

    private func build(into root: CALayer, local: CGPoint, item: EmoteStage.Item) {
        let s = item.size

        // The emote art: circular-clipped image with a pop-in animation.
        let art = CALayer()
        art.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        art.position = CGPoint(x: local.x, y: local.y)
        art.cornerRadius = s / 2
        art.masksToBounds = true
        art.opacity = 0

        if let image = EmoteLibrary.shared.poster(for: item.asset),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            art.contents = cgImage
            art.contentsGravity = .resizeAspect
        } else {
            art.backgroundColor = NSColor(hex: "#4a4e54").cgColor
        }

        root.addSublayer(art)
        animate(layer: art, local: local, item: item, translated: false)
    }

    /// The pop, the hold, the fade and the bob. A view's own layer gets the bob as a translation,
    /// because AppKit owns that layer's position and would undo it on the next layout.
    private func animate(layer: CALayer?, local: CGPoint, item: EmoteStage.Item, translated: Bool) {
        guard let layer else { return }
        let now = CACurrentMediaTime()
        let duration = item.lifetime

        layer.add(Self.keyframe(path: "transform.scale",
                                values: [0.3, 1.1, 1.0, 1.0, 0.8],
                                at: [0, 0.15, 0.25, 0.85, 1],
                                duration: duration, begin: now), forKey: "pop")
        layer.add(Self.keyframe(path: "opacity",
                                values: [0, 1, 1, 1, 0],
                                at: [0, 0.1, 0.85, 0.9, 1],
                                duration: duration, begin: now), forKey: "fade")

        let bob = CAKeyframeAnimation(keyPath: translated ? "transform.translation.y" : "position")
        if translated {
            bob.values = [0, 4, -4, 0]
        } else {
            bob.values = [local,
                          CGPoint(x: local.x, y: local.y + 4),
                          CGPoint(x: local.x, y: local.y - 4),
                          local]
        }
        bob.keyTimes = [0, 0.33, 0.66, 1]
        bob.duration = 1.4
        bob.beginTime = now + 0.3
        bob.repeatCount = .greatestFiniteMagnitude
        bob.calculationMode = .cubic
        layer.add(bob, forKey: "bob")
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
