import AVFoundation
import AppKit
import SwiftUI

/// Draws one emote's art inside SwiftUI: a still, an animated gif, or a looping clip.
///
/// `animates` is off until a cell is hovered or an emote is firing, so a library of forty
/// imports never costs forty decoders. A clip never makes a sound here — the player is muted and
/// the emote's own sound slot is what you hear.
struct EmoteArtView: NSViewRepresentable {
    let asset: EmoteAsset
    var animates = false
    var corner: CGFloat = 0

    func makeNSView(context: Context) -> EmoteArtNSView {
        let view = EmoteArtNSView()
        view.corner = corner
        view.show(asset: asset, animates: animates)
        return view
    }

    func updateNSView(_ nsView: EmoteArtNSView, context: Context) {
        nsView.corner = corner
        nsView.show(asset: asset, animates: animates)
    }
}

/// The hosting view. Sublayers are clipped by its own cornerRadius, which is how a square clip
/// becomes the wheel's circle without a mask per media kind.
final class EmoteArtNSView: NSView {
    private let imageView = NSImageView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var current: EmoteAsset?
    private var shownAnimates = false

    var corner: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = false
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The image view is pinned to the bounds rather than to constraints: an `NSImageView` reports
    /// its picture's own size as its intrinsic content size, and a 256 px emote would otherwise
    /// push a 34 pt cell out to 256.
    override func layout() {
        super.layout()
        imageView.frame = bounds
        layer?.cornerRadius = corner
        playerLayer?.frame = bounds
    }

    func show(asset: EmoteAsset, animates: Bool) {
        guard current?.id != asset.id || shownAnimates != animates else { return }
        current = asset
        shownAnimates = animates

        let moving = animates && asset.isAnimated
        if moving, asset.kind == .video, asset.mediaURL != nil {
            startVideo(asset)
        } else {
            stopVideo()
        }
        // A clip plays over its poster rather than replacing it: the poster is what shows while
        // AVFoundation buffers the first frame, and a cell that goes blank reads as a bug.
        imageView.animates = moving && asset.kind == .gif
        imageView.image = EmoteLibrary.shared.artwork(for: asset, animates: moving)
    }

    /// Frees the decoder and the gif timer without changing what is on screen — what the overlay
    /// calls the moment an emote dies, so thirty fired clips cannot leave thirty players running.
    func stop() {
        guard current != nil else { return }
        shownAnimates = false
        imageView.animates = false
        stopVideo()
        self.current = nil
    }

    private func startVideo(_ asset: EmoteAsset) {
        guard let url = asset.mediaURL else { return }
        if player == nil || playerLayer == nil {
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            queue.isMuted = true
            let looper = AVPlayerLooper(player: queue, templateItem: item)
            let layer = AVPlayerLayer(player: queue)
            layer.videoGravity = .resizeAspect
            layer.isOpaque = false
            // `zPosition` is what puts the picture above the poster: AppKit owns the order of a
            // layer-backed view's sublayers, and an `addSublayer` on its own can land underneath
            // the image view.
            layer.zPosition = 1
            self.player = queue
            self.looper = looper
            self.playerLayer = layer
            layer.frame = bounds
            self.layer?.addSublayer(layer)
        }
        playerLayer?.frame = bounds
        player?.play()
    }

    private func stopVideo() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        looper = nil
        playerLayer = nil
    }
}
