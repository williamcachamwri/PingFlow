import AppKit
import SwiftUI

/// SwiftUI's gesture coordinate spaces proved unreliable for the library→wheel drag, so the drag
/// reads the real cursor from `NSEvent` and converts it through real AppKit views instead.
final class DragSpace {
    weak var paneView: NSView?
    weak var wheelView: NSView?

    /// The cursor in the pane's own space, y down, origin at the pane's top-left.
    func cursorInPane() -> CGPoint? { converted(using: paneView) }

    /// The cursor in the wheel editor's space, y down, origin at the wheel's top-left.
    func cursorInWheel() -> CGPoint? { converted(using: wheelView) }

    private func converted(using view: NSView?) -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let mouse = NSEvent.mouseLocation
        let topLeft = window.convertPoint(toScreen: view.convert(NSPoint(x: 0, y: view.bounds.maxY), to: nil))
        return CGPoint(x: mouse.x - topLeft.x, y: topLeft.y - mouse.y)
    }
}

/// A zero-interaction AppKit view used only as a coordinate anchor for `DragSpace`.
struct SpaceMarker: NSViewRepresentable {
    let assign: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        assign(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
