import AppKit
import SwiftUI

/// The scope framing around an editor wheel, in two layers: `StageGlow` lifts the disc off the
/// card from underneath, while `StageMarks` — the dashed range ring, the boundary ticks and the
/// slice index at each spoke — sits above the wheel, because the wheel's own cardinal beams would
/// otherwise swallow the cardinal labels.
struct StageGlow: View {
    let layout: WheelLayout

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = layout.extensionRadius + 12
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2)),
                with: .radialGradient(Gradient(colors: [Palette.primaryText.opacity(0.05), .clear]),
                                      center: centre, startRadius: layout.innerRadius, endRadius: ring))
        }
        .allowsHitTesting(false)
    }
}

struct StageMarks: View {
    let layout: WheelLayout
    let selected: Int?
    let compass: (Int) -> String

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = layout.extensionRadius + 12

            var circle = Path()
            circle.addEllipse(in: CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2))
            context.stroke(circle, with: .color(Palette.tertiaryText.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 6]))

            for index in 0..<8 {
                let boundary = Angle(degrees: -90 + Double(index) * 45 + 22.5).radians
                var tick = Path()
                tick.move(to: point(around: centre, angle: boundary, radius: ring - 4))
                tick.addLine(to: point(around: centre, angle: boundary, radius: ring + 4))
                context.stroke(tick, with: .color(Palette.tertiaryText.opacity(0.35)), lineWidth: 1)

                let spoke = Angle(degrees: -90 + Double(index) * 45).radians
                let at = point(around: centre, angle: spoke, radius: ring + 18)
                let isActive = selected == index
                // The cardinal spokes carry the wheel's light beams, so every label sits on its
                // own plate or the cardinal four vanish into the glow.
                let plate = CGRect(x: at.x - 14, y: at.y - 12, width: 28, height: 24)
                context.fill(Path(roundedRect: plate, cornerRadius: 7), with: .color(Palette.cardBackground))
                context.stroke(Path(roundedRect: plate, cornerRadius: 7),
                               with: .color(isActive ? Palette.accent.opacity(0.5) : Palette.tertiaryText.opacity(0.2)),
                               lineWidth: 1)
                context.draw(
                    Text("\(index)")
                        .font(.system(size: 10, weight: isActive ? .bold : .medium, design: .monospaced))
                        .foregroundColor(isActive ? Palette.accent : Palette.tertiaryText.opacity(0.75)),
                    at: CGPoint(x: at.x, y: at.y - 6))
                context.draw(
                    Text(compass(index))
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundColor(isActive ? Palette.accent.opacity(0.8) : Palette.tertiaryText.opacity(0.5)),
                    at: CGPoint(x: at.x, y: at.y + 5))
            }
        }
        .allowsHitTesting(false)
    }

    private func point(around centre: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
    }
}

/// The wheel stage and the library it feeds side by side while the page has room for both, so a
/// drag from a library cell to a slice travels a hand's width instead of down a scroll view.
/// The stage keeps the width its spoke labels need; the library takes the rest.
struct Workbench: Layout {
    var stageMin: CGFloat = 492
    var columnMin: CGFloat = 196
    var columnMax: CGFloat = 320
    var gutter: CGFloat = 16

    private var sideBySideAt: CGFloat { stageMin + columnMin + gutter }

    private func columnWidth(for width: CGFloat) -> CGFloat {
        min(columnMax, max(columnMin, width - stageMin - gutter))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? sideBySideAt
        if width >= sideBySideAt {
            let side = columnWidth(for: width)
            let stage = subviews[0].sizeThatFits(ProposedViewSize(width: width - side - gutter, height: nil)).height
            let trail = subviews[1].sizeThatFits(ProposedViewSize(width: side, height: nil)).height
            return CGSize(width: width, height: max(stage, trail))
        }
        let stage = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let trail = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: stage + gutter + trail)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let width = bounds.width
        if width >= sideBySideAt {
            let side = columnWidth(for: width)
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: width - side - gutter, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.maxX - side, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: side, height: nil))
        } else {
            let stage = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + stage + gutter), anchor: .topLeading,
                              proposal: ProposedViewSize(width: width, height: nil))
        }
    }
}

/// A scroll area that shrinks to its content and only keeps its cap once the content outgrows it,
/// so a short library never leaves a card full of empty scroll view.
struct CappedScroll<Content: View>: View {
    let cap: CGFloat
    @ViewBuilder var content: Content

    @State private var measured: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                })
        }
        .frame(height: measured > 0 ? min(cap, measured + 1) : cap)
        .overlay(alignment: .bottom) {
            if measured + 1 > cap {
                LinearGradient(colors: [.clear, Palette.cardBackground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 26)
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(HeightKey.self) { measured = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
