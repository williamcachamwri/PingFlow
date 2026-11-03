import AppKit
import SwiftUI
import Combine

/// One panel's worth of drawing: where the wheel sits on this display and which pings are live
/// on it. The controller talks to this; the SwiftUI tree reads it.
@MainActor
final class OverlayHost: ObservableObject {
    let scene: WheelScene
    let emoteScene: EmoteScene
    let stage = PingStage()
    let emoteStage = EmoteStage()
    /// Centre of the wheel in this panel's own coordinates (origin bottom-left).
    @Published private(set) var wheelCentre: CGPoint = .zero
    @Published private(set) var emoteWheelCentre: CGPoint = .zero
    @Published private(set) var canvasSize: CGSize

    private var screenFrame: CGRect
    private let store: SettingsStore

    init(scene: WheelScene, emoteScene: EmoteScene, store: SettingsStore, screenFrame: CGRect) {
        self.scene = scene
        self.emoteScene = emoteScene
        self.store = store
        self.screenFrame = screenFrame
        self.canvasSize = screenFrame.size
    }

    var isBusy: Bool {
        scene.phase != .hidden || emoteScene.phase != .hidden || !stage.isEmpty || !emoteStage.isEmpty
    }

    var rootView: NSView {
        let hosting = NSHostingView(rootView: OverlayContentView(host: self)
            .frame(width: canvasSize.width, height: canvasSize.height))
        hosting.frame = CGRect(origin: .zero, size: canvasSize)
        return hosting
    }

    func resize(to size: CGSize) {
        canvasSize = size
        screenFrame = CGRect(origin: screenFrame.origin, size: size)
    }

    /// Converts a CoreGraphics global point into this panel's SwiftUI space (y down from the top).
    func placeWheel(at globalPoint: CGPoint) {
        wheelCentre = swiftUIPoint(from: globalPoint)
    }

    func placeEmoteWheel(at globalPoint: CGPoint) {
        emoteWheelCentre = swiftUIPoint(from: globalPoint)
    }

    func spawnPing(_ definition: PingDefinition, at globalPoint: CGPoint) {
        stage.spawn(definition: definition, at: swiftUIPoint(from: globalPoint), settings: store.settings)
    }

    func spawnEmote(_ asset: EmoteAsset, at globalPoint: CGPoint) {
        emoteStage.spawn(asset: asset, at: swiftUIPoint(from: globalPoint), settings: store.settings)
    }

    /// CoreGraphics global → AppKit global → this panel's SwiftUI coordinates.
    private func swiftUIPoint(from globalPoint: CGPoint) -> CGPoint {
        let appKit = CoordinateSpace.appKitPoint(from: globalPoint)
        return CGPoint(x: appKit.x - screenFrame.minX,
                       y: canvasSize.height - (appKit.y - screenFrame.minY))
    }

    func retireWheel() {
        scene.close()
    }

    func retireEmoteWheel() {
        emoteScene.close()
    }
}

/// The panel's content: pings and emotes underneath, their wheels on top, neither of them reachable
/// by the mouse. Both layers are drawn only while something is happening.
struct OverlayContentView: View {
    @ObservedObject var host: OverlayHost

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            PingFxHost(stage: host.stage, canvasHeight: host.canvasSize.height)
            EmoteFxHost(stage: host.emoteStage, canvasHeight: host.canvasSize.height)
            WheelOverlayView(scene: host.scene, centre: host.wheelCentre)
            EmoteOverlayView(scene: host.emoteScene, centre: host.emoteWheelCentre)
        }
        .frame(width: host.canvasSize.width, height: host.canvasSize.height, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
