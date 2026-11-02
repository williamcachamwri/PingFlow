import SwiftUI

/// Places the wheel under the cursor and plays its two transitions. The reference opens with a
/// fade and a 0.85 → 1 scale over 120 ms and closes with a fade; the same two moves, driven by
/// `WheelScene.phase`, are all that happens here.
struct WheelOverlayView: View {
    @ObservedObject var scene: WheelScene

    /// Centre in the panel's SwiftUI space.
    var centre: CGPoint

    var body: some View {
        if scene.phase != .hidden {
            PingWheelView(slots: scene.slots,
                          hoveredSlice: scene.hoveredSlice,
                          confirmedSlice: scene.confirmedSlice,
                          size: scene.size,
                          dimUnhoveredIcons: scene.dimUnhoveredIcons,
                          showCentreLabel: scene.showCentreLabel,
                          centreText: scene.centreText,
                          hubImageName: scene.hubImageName)
                .opacity(opacity)
                .scaleEffect(scale)
                .position(x: centre.x, y: centre.y)
                .animation(.easeOut(duration: 0.12), value: scene.phase)
                .onChange(of: scene.phase) { phase in
                    if phase == .closing {
                        // Let the fade finish before the scene goes away, so nothing pops out.
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
