import SwiftUI

/// Places the emote wheel under the cursor with the same open/close transitions as the ping wheel.
struct EmoteOverlayView: View {
    @ObservedObject var scene: EmoteScene
    var centre: CGPoint

    var body: some View {
        if scene.phase != .hidden {
            EmoteWheelView(slots: scene.slots,
                           hoveredSlice: scene.hoveredSlice,
                           confirmedSlice: scene.confirmedSlice,
                           size: scene.size,
                           centreText: scene.centreText)
                .opacity(opacity)
                .scaleEffect(scale)
                .position(x: centre.x, y: centre.y)
                .animation(.easeOut(duration: 0.12), value: scene.phase)
                .onChange(of: scene.phase) { phase in
                    if phase == .closing {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            scene.markHidden()
                        }
                    }
                }
                .accessibilityHidden(true)
        }
    }

    private var scale: CGFloat {
        switch scene.phase {
        case .hidden: return 0.85
        case .opening: return 0.85
        case .active, .closing: return scene.phase == .closing ? 0.94 : 1
        }
    }

    private var opacity: Double {
        switch scene.phase {
        case .hidden, .closing: return 0
        case .opening, .active: return scene.overlayOpacity
        }
    }
}
